import Foundation

@MainActor
final class BoardPublisher: ObservableObject {
    nonisolated static let showButtonKey = "showPublishButton"

    @Published private(set) var isPublishing = false
    @Published private(set) var status: String?

    func publish() async {
        guard !isPublishing else { return }
        isPublishing = true
        status = nil
        defer { isPublishing = false }

        do {
            let result = try await Task.detached(priority: .userInitiated) { () throws -> (Int32, String) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", "Publish Task Board"]
                process.standardOutput = FileHandle.nullDevice
                let errors = Pipe()
                process.standardError = errors
                try process.run()
                process.waitUntilExit()
                let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return (process.terminationStatus, detail)
            }.value
            if result.0 == 0 {
                status = "Shortcut finished."
            } else {
                status = "Publish failed: \(result.1.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        } catch {
            status = "Publish failed: \(error.localizedDescription)"
        }
    }
}
