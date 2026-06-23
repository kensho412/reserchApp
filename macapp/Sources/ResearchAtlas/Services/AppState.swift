import Foundation
import SwiftUI

/// Central observable store. Owns the search query (Cosense-style), the page
/// list, the tag list, and the currently open page.
@MainActor
final class AppState: ObservableObject {
    @Published var searchText: String = ""
    @Published var sort: String = "updated"
    @Published var cards: [PageCard] = []
    @Published var tags: [TagInfo] = []
    @Published var openPage: Page?
    @Published var similar: [SimilarPage] = []
    @Published var statusMessage: String?
    @Published var isWorking = false

    @AppStorage("serverURL") var serverURLString: String = "http://127.0.0.1:8000"

    private(set) lazy var api = APIClient(baseURL: URL(string: serverURLString)!)

    /// Parsed required tags from the search field (#foo #bar -> ["foo","bar"]).
    var activeTags: [String] {
        searchText.split(separator: " ")
            .filter { $0.hasPrefix("#") }
            .map { String($0.dropFirst()).lowercased() }
            .filter { !$0.isEmpty }
    }

    var freeText: String {
        searchText.split(separator: " ")
            .filter { !$0.hasPrefix("#") }
            .joined(separator: " ")
    }

    func applyServerURL() async {
        if let url = URL(string: serverURLString) { await api.setBaseURL(url) }
        await reload()
    }

    func reload() async {
        await refreshTags()
        await search()
    }

    func search() async {
        do {
            cards = try await api.listPages(query: freeText, tags: activeTags, sort: sort)
        } catch {
            status("Search failed: \(error.localizedDescription)")
        }
    }

    func refreshTags() async {
        do { tags = try await api.listTags(onlyUsed: false) }
        catch { /* keep previous tags on failure */ }
    }

    // MARK: Search-bar driven tag toggling (AND filter)
    func toggleTag(_ name: String) {
        let token = "#\(name)"
        var parts = searchText.split(separator: " ").map(String.init)
        if let idx = parts.firstIndex(of: token) {
            parts.remove(at: idx)
        } else {
            parts.append(token)
        }
        searchText = parts.joined(separator: " ")
        Task { await search() }
    }

    func clearFilter() {
        // Keep free text, drop tags.
        searchText = freeText
        Task { await search() }
    }

    // MARK: Page creation
    /// Create a fresh page and open its editor immediately.
    /// Uses a unique placeholder title (the backend de-dupes by exact title),
    /// which the user overwrites in the editor's title field.
    func createNewPage() async {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd HH:mm:ss"
        let placeholder = "無題 \(fmt.string(from: Date()))"
        do {
            let page = try await api.createPage(title: placeholder)
            await refreshTags()
            openPage = page
        } catch { status("作成に失敗しました: \(error.localizedDescription)") }
    }

    func open(_ id: String) async {
        do {
            openPage = try await api.getPage(id)
            similar = (try? await api.similar(id)) ?? []
        } catch { status("Open failed: \(error.localizedDescription)") }
    }

    func closePage() {
        openPage = nil
        similar = []
        Task { await reload() }
    }

    // MARK: Mutations
    /// Auto-save: PATCH the given page (by id, so it works even after the editor
    /// has moved on or closed). Quiet — no status spam, no similar() recompute.
    func autoSaveFields(pageID: String, fields: [String: Any]) async {
        do {
            let updated = try await api.updatePage(pageID, fields: fields)
            if openPage?.id == pageID { openPage = updated }
            await refreshTags()
        } catch {
            status("自動保存に失敗: \(error.localizedDescription)")
        }
    }

    func setTags(_ tags: [String]) async {
        guard let id = openPage?.id else { return }
        do {
            openPage = try await api.updatePage(id, fields: ["tags": tags])
            await refreshTags()
        } catch { status("Tag update failed: \(error.localizedDescription)") }
    }

    func submitURL(_ url: String) async {
        guard let id = openPage?.id else { return }
        work("URL を解析中…")
        do { openPage = try await api.submitURL(id, url: url) }
        catch { status("URL submit failed: \(error.localizedDescription)") }
        await pollAfterIngest(id)
    }

    func uploadPDF(_ fileURL: URL) async {
        guard let id = openPage?.id else { return }
        work("PDF を解析中…")
        do { openPage = try await api.uploadPDF(id, fileURL: fileURL) }
        catch { status("PDF upload failed: \(error.localizedDescription)") }
        await pollAfterIngest(id)
    }

    func reanalyze() async {
        guard let id = openPage?.id else { return }
        work("LLM 再解析中…")
        do {
            _ = try await api.analyze(id)
            openPage = try await api.getPage(id)
            await refreshTags()
            status("解析が完了しました")
        } catch { status("Analyze failed: \(error.localizedDescription)") }
        isWorking = false
    }

    func translate(full: Bool) async {
        guard let id = openPage?.id else { return }
        work(full ? "全文翻訳中…" : "章ごとに翻訳中…")
        do {
            _ = try await api.translate(id, sections: true, full: full)
            openPage = try await api.getPage(id)
            status("翻訳が完了しました")
        } catch { status("Translate failed: \(error.localizedDescription)") }
        isWorking = false
    }

    /// Ingestion runs as a backend background task; poll a few times for results.
    private func pollAfterIngest(_ id: String) async {
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let page = try? await api.getPage(id) {
                openPage = page
                if page.llm?.summary_ja.isEmpty == false { break }
            }
        }
        await refreshTags()
        isWorking = false
        statusMessage = nil
    }

    // MARK: status helpers
    private func work(_ msg: String) { isWorking = true; statusMessage = msg }
    func status(_ msg: String) { statusMessage = msg }
}
