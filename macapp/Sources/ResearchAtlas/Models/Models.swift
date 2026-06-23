import Foundation

// Codable mirrors of the FastAPI schemas. Field names match the JSON exactly.

struct PageCard: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let type: String
    let tags: [String]
    let summary_ja: String
    let authors: [String]
    let year: Int?
    let updated_at: Date
}

struct SectionSummary: Codable, Hashable {
    let heading: String
    let summary: String
}

struct LLMOutput: Codable, Hashable {
    var summary_ja: String = ""
    var suggested_tags: [String] = []
    var abstract_ja: String = ""
    var translation_ja: String = ""
    var section_summaries: [SectionSummary] = []
    var important_quotes: [String] = []
    var related_candidates: [String] = []
}

struct Page: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var body: String
    var type: String
    var summary_ja: String
    var source_url: String?
    var video_url: String?
    var pdf_path: String?
    var thumbnail_path: String?
    var authors: [String]
    var year: Int?
    var tags: [String]
    var backlinks: [String]
    var outgoing_links: [String]
    var related_page_ids: [String]
    let created_at: Date
    let updated_at: Date
    var llm: LLMOutput?
}

struct TagInfo: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let category: String
    let count: Int
}

struct SimilarPage: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let type: String
    let score: Double
    let reason: String
}

enum PageTypeStyle {
    static let all = ["paper", "artwork", "exhibition", "video", "note", "other"]
    static func symbol(_ type: String) -> String {
        switch type {
        case "paper": return "doc.text"
        case "artwork": return "paintpalette"
        case "exhibition": return "building.columns"
        case "video": return "play.rectangle"
        case "note": return "note.text"
        default: return "circle"
        }
    }
}
