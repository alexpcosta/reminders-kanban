import SwiftUI
import UniformTypeIdentifiers

@main
struct TaskBoardApp: App {
    @NSApplicationDelegateAdaptor(TaskBoardAppDelegate.self) private var appDelegate
    @StateObject private var store = ReminderStore()
    @StateObject private var publisher = BoardPublisher()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Task Board", id: "board") {
            BoardView(appDelegate: appDelegate)
                .environmentObject(store)
                .environmentObject(store.categories)
                .environmentObject(publisher)
                .task { await store.refresh() }
                .onAppear { QuickCaptureCoordinator.shared.store = store }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refresh() } }
                }
        }
        .defaultSize(width: 1060, height: 700)

        Settings {
            CategorySettingsView()
                .environmentObject(store.categories)
        }

        .commands {
            CommandGroup(after: .newItem) {
                Button("Quick Capture") { QuickCaptureCoordinator.shared.show() }
                    .keyboardShortcut("t", modifiers: [.control, .option, .command])
            }
        }
    }
}

private struct Editor: Identifiable {
    let id = UUID()
    let column: String
    let task: BoardTask?
}

private enum ActiveSheet: Identifiable {
    case editor(Editor)
    case dueDate(BoardTask)

    var id: String {
        switch self {
        case .editor(let editor): "editor-\(editor.id)"
        case .dueDate(let task): "date-\(task.id)"
        }
    }
}

struct BoardView: View {
    let appDelegate: TaskBoardAppDelegate
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var categories: CategorySettings
    @EnvironmentObject private var publisher: BoardPublisher
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(BoardPublisher.showButtonKey) private var showPublishButton = false
    @State private var activeSheet: ActiveSheet?
    @State private var showingFilter = false
    @State private var selectedCategoryIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let logoURL = Bundle.main.url(forResource: "TaskBoard-logo", withExtension: "png"),
                   let logo = NSImage(contentsOf: logoURL) {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 102, height: 30, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Task Board")
                } else {
                    Text("Task Board").font(.headline)
                }
                if let status = publisher.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(status)
                } else {
                    Spacer()
                }
                if store.isLoading {
                    ProgressView().controlSize(.small)
                    Text(store.loadPhase).font(.caption).foregroundStyle(.secondary)
                }
                if publisher.isPublishing { ProgressView().controlSize(.small) }
                if showPublishButton {
                    Button("Publish to display", systemImage: "paperplane") {
                        Task { await publisher.publish() }
                    }
                    .disabled(publisher.isPublishing)
                }
                Button(selectedCategoryIDs.isEmpty ? "Filter" : "Filter (\(selectedCategoryIDs.count))",
                       systemImage: "line.3.horizontal.decrease") {
                    showingFilter.toggle()
                }
                .popover(isPresented: $showingFilter, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Show categories").font(.headline)
                        ForEach(categories.categories) { category in
                            Toggle(category.name, isOn: Binding(
                                get: { selectedCategoryIDs.contains(category.id) },
                                set: { selected in
                                    if selected { selectedCategoryIDs.insert(category.id) }
                                    else { selectedCategoryIDs.remove(category.id) }
                                }
                            ))
                        }
                        Divider()
                        Button("Show all") { selectedCategoryIDs.removeAll() }
                            .disabled(selectedCategoryIDs.isEmpty)
                    }
                    .padding(16)
                    .frame(minWidth: 220)
                }
                Button("Categories", systemImage: "gearshape") { openSettings() }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 6)

            HStack(alignment: .top, spacing: 14) {
                ForEach(ReminderStore.columns, id: \.self) { column in
                    columnView(column)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appDelegate.configureMenuBar(store: store, publisher: publisher) {
                openWindow(id: "board")
            }
        }
        .onChange(of: categories.categories.map(\.id)) { _, activeIDs in
            selectedCategoryIDs.formIntersection(activeIDs)
            Task { await store.refresh() }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editor(let value):
                TaskEditorView(column: value.column, task: value.task)
                    .environmentObject(store)
                    .environmentObject(categories)
            case .dueDate(let task):
                DueDateEditorView(task: task)
                    .environmentObject(store)
            }
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

    private func columnView(_ name: String) -> some View {
        let tasks = visibleTasks(in: name)
        return VStack(spacing: 0) {
            HStack {
                Text(name.uppercased()).font(.headline)
                Text("\(tasks.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    activeSheet = .editor(Editor(column: name, task: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add reminder to \(name)")
            }
            .padding(14)

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(tasks) { task in
                        taskCard(task)
                            .contextMenu { cardMenu(for: task) }
                    }
                    if tasks.isEmpty {
                        Text(selectedCategoryIDs.isEmpty
                             ? "Drop a reminder here or add one"
                             : "No cards match the selected categories")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 90)
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let id = object as? String else { return }
                    Task { @MainActor in await store.move(id, to: name) }
                }
                return true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func visibleTasks(in column: String) -> [BoardTask] {
        let tasks = store.tasks[column] ?? []
        guard !selectedCategoryIDs.isEmpty else { return tasks }
        return tasks.filter { $0.categoryID.map(selectedCategoryIDs.contains) ?? false }
    }

    private func taskCard(_ task: BoardTask) -> some View {
        let tint = categories.color(for: task.categoryID)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await store.complete(task.id) }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Complete reminder")

            Button {
                activeSheet = .editor(Editor(column: task.column, task: task))
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title).font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                    if let name = categories.name(for: task.categoryID) {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let due = task.dueDate {
                        Text(due, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Edit reminder")

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
                .onDrag { NSItemProvider(object: task.id as NSString) }
                .help("Drag to another list")

            if task.priority > 0 {
                Image(systemName: "exclamationmark")
                    .foregroundStyle(task.priority <= 4 ? .orange : .secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint?.opacity(0.17) ?? Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
        .overlay(alignment: .leading) {
            if let tint {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 4)
                    .padding(.vertical, 7)
            }
        }
    }

    @ViewBuilder
    private func cardMenu(for task: BoardTask) -> some View {
        Menu("Category") {
            Button("None") { Task { await store.setCategory(nil, for: task.id) } }
            ForEach(categories.categories) { category in
                Button(category.name) {
                    Task { await store.setCategory(category.id, for: task.id) }
                }
            }
        }
        Menu("Priority") {
            Button("None") { Task { await store.setPriority(0, for: task.id) } }
            Button("High") { Task { await store.setPriority(1, for: task.id) } }
            Button("Medium") { Task { await store.setPriority(5, for: task.id) } }
            Button("Low") { Task { await store.setPriority(9, for: task.id) } }
        }
        Menu("Due date") {
            Button("Today") { setDueDate(for: task, daysFromToday: 0) }
            Button("Tomorrow") { setDueDate(for: task, daysFromToday: 1) }
            Button("Next week") { setDueDate(for: task, daysFromToday: 7) }
            Button("Choose date…") {
                Task { @MainActor in
                    await Task.yield()
                    activeSheet = .dueDate(task)
                }
            }
            if task.dueDate != nil {
                Divider()
                Button("Remove due date") {
                    Task { await store.setDueDate(nil, for: task.id) }
                }
            }
        }
        Divider()
        Button("Edit reminder…") {
            activeSheet = .editor(Editor(column: task.column, task: task))
        }
    }

    private func setDueDate(for task: BoardTask, daysFromToday days: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) else { return }
        Task { await store.setDueDate(date, for: task.id) }
    }
}

struct TaskEditorView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var categories: CategorySettings
    @Environment(\.dismiss) private var dismiss
    let column: String
    let task: BoardTask?
    @State private var draft: TaskDraft
    @State private var saving = false

    init(column: String, task: BoardTask?) {
        self.column = column
        self.task = task
        _draft = State(initialValue: task.map(TaskDraft.init) ?? TaskDraft())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(task == nil ? "Add to \(column)" : "Edit reminder")
                .font(.title2.bold())
            Form {
                TextField("Title", text: $draft.title)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Category", selection: $draft.categoryID) {
                    Text("None").tag(nil as String?)
                    ForEach(categories.categories) { category in
                        Text(category.name).tag(category.id as String?)
                    }
                }
                Text("In Reminders, add \(draft.categoryID.map { "#board-\($0)" } ?? "#board-family") on its own line in Notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Priority", selection: $draft.priority) {
                    Text("None").tag(0)
                    Text("High").tag(1)
                    Text("Medium").tag(5)
                    Text("Low").tag(9)
                }
                Toggle("Due date", isOn: $draft.hasDueDate)
                if draft.hasDueDate {
                    DatePicker("Date", selection: $draft.dueDate, displayedComponents: .date)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saving = true
                    Task {
                        if await store.save(draft, id: task?.id, in: column) { dismiss() }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .padding(24)
        .frame(width: 470)
    }
}

private struct DueDateEditorView: View {
    @EnvironmentObject private var store: ReminderStore
    @Environment(\.dismiss) private var dismiss
    let task: BoardTask
    @State private var date: Date

    init(task: BoardTask) {
        self.task = task
        _date = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Due date").font(.title2.bold())
            Text(task.title).lineLimit(2).foregroundStyle(.secondary)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    Task {
                        await store.setDueDate(date, for: task.id)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}
