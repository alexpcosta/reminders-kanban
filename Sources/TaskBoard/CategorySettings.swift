import AppKit
import SwiftUI

@MainActor
final class CategorySettings: ObservableObject {
    @Published private(set) var categories: [BoardCategory]
    private let defaults: UserDefaults
    private let key = "boardCategories"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([BoardCategory].self, from: data) {
            categories = saved
        } else {
            categories = BoardCategory.defaults
            persist()
        }
    }

    func category(for id: String?) -> BoardCategory? {
        categories.first { $0.id == id }
    }

    func name(for id: String?) -> String? {
        guard let category = category(for: id) else { return nil }
        let trimmed = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? category.id : trimmed
    }

    func color(for id: String?) -> Color? {
        guard let category = category(for: id), let color = NSColor(hex: category.hex) else { return nil }
        return Color(nsColor: color)
    }

    func canAdd(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !categories.contains { $0.id == BoardCategory.slug(for: trimmed) }
    }

    func add(name: String, color: Color) {
        guard canAdd(name) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        categories.append(BoardCategory(id: BoardCategory.slug(for: trimmed),
                                        name: trimmed, hex: Self.hex(for: color)))
        persist()
    }

    func remove(_ id: String) {
        categories.removeAll { $0.id == id }
        persist()
    }

    func setName(_ name: String, for id: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
        persist()
    }

    func setColor(_ color: Color, for id: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].hex = Self.hex(for: color)
        persist()
    }

    private static func hex(for color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "#808080" }
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X",
                      channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(categories) {
            defaults.set(data, forKey: key)
        }
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        guard hex.count == 7, hex.first == "#",
              let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

struct CategorySettingsView: View {
    @EnvironmentObject private var settings: CategorySettings
    @AppStorage(BoardPublisher.showButtonKey) private var showPublishButton = false
    @State private var newName = ""
    @State private var newColor = Color.gray

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Categories").font(.title2.bold())
            Form {
                ForEach(settings.categories) { category in
                    HStack {
                        TextField("Name", text: Binding(
                            get: { settings.category(for: category.id)?.name ?? "" },
                            set: { settings.setName($0, for: category.id) }
                        ))
                        .frame(width: 170)
                        ColorPicker("Colour", selection: Binding(
                            get: { settings.color(for: category.id) ?? .gray },
                            set: { settings.setColor($0, for: category.id) }
                        ), supportsOpacity: false)
                        .frame(width: 100)
                        Text(category.marker)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { settings.remove(category.id) } label: {
                            Image(systemName: "trash")
                        }
                        .help("Remove \(category.name)")
                    }
                }
            }
            Divider()
            HStack {
                TextField("New category", text: $newName)
                    .frame(width: 170)
                ColorPicker("Colour", selection: $newColor, supportsOpacity: false)
                    .frame(width: 100)
                Button("Add Category") {
                    settings.add(name: newName, color: newColor)
                    newName = ""
                }
                .disabled(!settings.canAdd(newName))
                Spacer()
            }
            Text("Removing a category leaves its Notes markers in Reminders. Add it again with the same name to restore those cards.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle("Show Publish to display button", isOn: $showPublishButton)
            Text("The button runs a Shortcut named Publish Task Board.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 600)
    }
}
