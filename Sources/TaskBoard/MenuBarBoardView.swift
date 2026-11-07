import SwiftUI
import UniformTypeIdentifiers

struct MenuBarBoardView: View {
    let openBoard: () -> Void
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var categories: CategorySettings
    @EnvironmentObject private var publisher: BoardPublisher
    @AppStorage(BoardPublisher.showButtonKey) private var showPublishButton = false
    @State private var editor: ColumnEditor?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Task Board").font(.headline)
                Spacer()
                if store.isLoading || publisher.isPublishing {
                    ProgressView().controlSize(.small)
                }
                if showPublishButton {
                    Button("Publish", systemImage: "paperplane") {
                        Task { await publisher.publish() }
                    }
                    .disabled(publisher.isPublishing)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                Button("Open board", systemImage: "arrow.up.left.and.arrow.down.right") {
                    openBoard()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .padding(12)

            if let status = publisher.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(ReminderStore.columns, id: \.self) { column in
                    columnView(column)
                }
            }
            .padding([.horizontal, .bottom], 10)
        }
        .frame(width: 720, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            QuickCaptureCoordinator.shared.store = store
            await store.refresh()
        }
        .sheet(item: $editor) { value in
            TaskEditorView(column: value.column, task: value.task)
                .environmentObject(store)
                .environmentObject(categories)
        }
        .alert("Task Board", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func columnView(_ column: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(column.uppercased()).font(.caption.bold())
                Text("\((store.tasks[column] ?? []).count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editor = ColumnEditor(column: column, task: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add reminder to \(column)")
            }
            .padding(9)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(store.tasks[column] ?? []) { task in
                        card(task)
                    }
                }
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let id = object as? String else { return }
                    Task { @MainActor in await store.move(id, to: column) }
                }
                return true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func card(_ task: BoardTask) -> some View {
        let tint = categories.color(for: task.categoryID)
        return HStack(alignment: .top, spacing: 6) {
            Button {
                Task { await store.complete(task.id) }
            } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.plain)
            .help("Complete reminder")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let name = categories.name(for: task.categoryID) {
                        Text(name)
                    }
                    if let dueDate = task.dueDate {
                        Text(dueDate, format: .dateTime.day().month(.abbreviated))
                    }
                    if task.priority > 0 {
                        Image(systemName: "exclamationmark")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint?.opacity(0.17) ?? Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Menu("Move to") {
                ForEach(ReminderStore.columns.filter { $0 != task.column }, id: \.self) { column in
                    Button(column) { Task { await store.move(task.id, to: column) } }
                }
            }
            Button("Edit reminder…") {
                editor = ColumnEditor(column: task.column, task: task)
            }
        }
        .onDrag { NSItemProvider(object: task.id as NSString) }
    }
}

private struct ColumnEditor: Identifiable {
    let id = UUID()
    let column: String
    let task: BoardTask?
}
