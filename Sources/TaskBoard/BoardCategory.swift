import Foundation

struct BoardCategory: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var hex: String

    var marker: String { "#board-\(id)" }

    static let defaults = [
        BoardCategory(id: "family", name: "Family", hex: "#3B82F6"),
        BoardCategory(id: "work", name: "Work", hex: "#8B5CF6"),
        BoardCategory(id: "personal", name: "Personal", hex: "#22C55E"),
    ]

    static func read(from notes: String, categories: [BoardCategory]) -> (categoryID: String?, notes: String) {
        let activeIDs = Set(categories.map(\.id))
        var categoryID: String?
        let lines = notes.components(separatedBy: "\n").filter { line in
            guard let id = markerID(in: line), activeIDs.contains(id) else { return true }
            categoryID = id
            return false
        }
        return (categoryID, lines.joined(separator: "\n").trimmingCharacters(in: .newlines))
    }

    static func write(_ categoryID: String?, to notes: String, categories: [BoardCategory]) -> String {
        let activeIDs = Set(categories.map(\.id))
        let body = notes.components(separatedBy: "\n")
            .filter { line in
                guard let id = markerID(in: line) else { return true }
                return categoryID == nil && !activeIDs.contains(id)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        guard let categoryID else { return body }
        let marker = "#board-\(categoryID)"
        return body.isEmpty ? marker : "\(body)\n\(marker)"
    }

    static func slug(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let slug = folded.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "category" : slug
    }

    private static func markerID(in line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.range(of: "^#board-[a-z0-9-]+$", options: .regularExpression) != nil else {
            return nil
        }
        return String(value.dropFirst(7))
    }
}
