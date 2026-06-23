import Foundation

/// Talks to the FastAPI backend. Base URL points at localhost during dev and at
/// the desktop server's Tailscale IP in production (configurable in Settings).
actor APIClient {
    var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601WithFractional
        return d
    }

    private func request(_ path: String, method: String = "GET",
                         query: [URLQueryItem] = [], body: Data? = nil,
                         contentType: String = "application/json",
                         timeout: TimeInterval = 30) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        // LLM calls over Tailscale can be slow on a local model; allow long waits.
        req.timeoutInterval = timeout
        if let body {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: Pages
    func listPages(query: String, tags: [String], sort: String) async throws -> [PageCard] {
        var q = [URLQueryItem(name: "query", value: query),
                 URLQueryItem(name: "sort", value: sort)]
        if !tags.isEmpty { q.append(URLQueryItem(name: "tags", value: tags.joined(separator: ","))) }
        let data = try await request("/pages", query: q)
        return try decoder.decode([PageCard].self, from: data)
    }

    func getPage(_ id: String) async throws -> Page {
        try decoder.decode(Page.self, from: try await request("/pages/\(id)"))
    }

    func createPage(title: String, type: String = "note", body: String = "") async throws -> Page {
        let payload = try JSONSerialization.data(withJSONObject: ["title": title, "type": type, "body": body])
        return try decoder.decode(Page.self, from: try await request("/pages", method: "POST", body: payload))
    }

    func updatePage(_ id: String, fields: [String: Any]) async throws -> Page {
        let payload = try JSONSerialization.data(withJSONObject: fields)
        return try decoder.decode(Page.self, from: try await request("/pages/\(id)", method: "PATCH", body: payload))
    }

    func deletePage(_ id: String) async throws {
        _ = try await request("/pages/\(id)", method: "DELETE")
    }

    func submitURL(_ id: String, url: String) async throws -> Page {
        let payload = try JSONSerialization.data(withJSONObject: ["url": url])
        return try decoder.decode(Page.self, from: try await request("/pages/\(id)/submit_url", method: "POST", body: payload))
    }

    func uploadPDF(_ id: String, fileURL: URL) async throws -> Page {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: application/pdf\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")
        let data = try await request("/pages/\(id)/upload_pdf", method: "POST", body: body,
                                     contentType: "multipart/form-data; boundary=\(boundary)", timeout: 180)
        return try decoder.decode(Page.self, from: data)
    }

    func similar(_ id: String) async throws -> [SimilarPage] {
        try decoder.decode([SimilarPage].self, from: try await request("/pages/\(id)/similar"))
    }

    // MARK: LLM  (synchronous; a local 7B model + translation can take minutes)
    func analyze(_ id: String) async throws -> LLMOutput {
        try decoder.decode(LLMOutput.self,
                           from: try await request("/pages/\(id)/llm/analyze", method: "POST", timeout: 600))
    }

    func translate(_ id: String, sections: Bool = true, full: Bool = false) async throws -> LLMOutput {
        let q = [URLQueryItem(name: "sections", value: String(sections)),
                 URLQueryItem(name: "full", value: String(full))]
        return try decoder.decode(LLMOutput.self,
                                  from: try await request("/pages/\(id)/llm/translate", method: "POST", query: q, timeout: 900))
    }

    // MARK: Tags
    func listTags(onlyUsed: Bool = false) async throws -> [TagInfo] {
        let q = [URLQueryItem(name: "only_used", value: String(onlyUsed))]
        return try decoder.decode([TagInfo].self, from: try await request("/tags", query: q))
    }

    func setBaseURL(_ url: URL) { baseURL = url }
}

enum APIError: LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) { append(string.data(using: .utf8)!) }
}

extension JSONDecoder.DateDecodingStrategy {
    /// FastAPI emits ISO-8601 timestamps with fractional seconds; accept both.
    static var iso8601WithFractional: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: s) { return d }
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            if let d = f2.date(from: s) { return d }
            // Bare 'YYYY-MM-DDTHH:MM:SS(.ffffff)' without timezone.
            let f3 = DateFormatter()
            f3.locale = Locale(identifier: "en_US_POSIX")
            f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            if let d = f3.date(from: s) { return d }
            f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f3.date(from: s) ?? Date()
        }
    }
}
