import EventKit
import Foundation

struct BoardTask: Identifiable {
    let id: String
    let title: String
    let notes: String
    let categoryID: String?
    let priority: Int
    let dueDate: Date?
    let column: String
}

struct TaskDraft {
    var title = ""
    var notes = ""
    var categoryID: String?
    var priority = 0
    var hasDueDate = false
    var dueDate = Date()

    init() {}

    init(task: BoardTask) {
        title = task.title
        notes = task.notes
        categoryID = task.categoryID
        priority = task.priority
        hasDueDate = task.dueDate != nil
        dueDate = task.dueDate ?? Date()
    }
}

enum BoardError: LocalizedError {
    case accessDenied
    case missingList(String)
    case duplicateList(String)
    case missingReminder

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Allow Task Board to access Reminders in System Settings → Privacy & Security → Reminders."
        case .missingList(let name):
            return "Create a Reminders list named \(name) in iCloud, then refresh."
        case .duplicateList(let name):
            return "There is more than one list named \(name). Give the extra list a different name, then refresh."
        case .missingReminder:
            return "This reminder is no longer available. Refresh the board."
        }
    }
}

@MainActor
final class ReminderStore: ObservableObject {
    static let columns = ["ToDo", "Doing", "Waiting"]

    @Published private(set) var tasks: [String: [BoardTask]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadPhase = ""
    @Published var errorMessage: String?
    let categories = CategorySettings()

    private let eventStore = EKEventStore()
    private var calendars: [String: EKCalendar] = [:]

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        loadPhase = "Checking Reminders access"
        defer {
            isLoading = false
            loadPhase = ""
        }
        do {
            let authorization = EKEventStore.authorizationStatus(for: .reminder)
            loadPhase = "Reminders access: \(authorization.rawValue)"
            switch authorization {
            case .fullAccess:
                break
            case .notDetermined:
                loadPhase = "Waiting for Reminders permission"
                guard try await eventStore.requestFullAccessToReminders() else {
                    throw BoardError.accessDenied
                }
            default:
                throw BoardError.accessDenied
            }
            loadPhase = "Loading reminders"
            try resolveCalendars()
            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: Self.columns.compactMap { calendars[$0] }
            )
            let reminders = await withCheckedContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { found in
                    continuation.resume(returning: found ?? [])
                }
            }
            loadPhase = "Updating board"
            var result = Dictionary(uniqueKeysWithValues: Self.columns.map { ($0, [BoardTask]()) })
            for reminder in reminders {
                guard let name = calendars.first(where: { $0.value.calendarIdentifier == reminder.calendar.calendarIdentifier })?.key else { continue }
                let id = reminder.calendarItemIdentifier
                let classifiedNotes = BoardCategory.read(from: reminder.notes ?? "", categories: categories.categories)
                result[name, default: []].append(BoardTask(
                    id: id,
                    title: reminder.title ?? "Untitled reminder",
                    notes: classifiedNotes.notes,
                    categoryID: classifiedNotes.categoryID,
                    priority: reminder.priority,
                    dueDate: reminder.dueDateComponents?.date,
                    column: name
                ))
            }
            for name in Self.columns {
                result[name]?.sort {
                    let left = $0.priority == 0 ? 10 : $0.priority
                    let right = $1.priority == 0 ? 10 : $1.priority
                    return left == right
                        ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                        : left < right
                }
            }
            tasks = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ draft: TaskDraft, id: String?, in column: String) async -> Bool {
        do {
            guard let calendar = calendars[column] else { throw BoardError.missingList(column) }
            let reminder: EKReminder
            if let id {
                guard let existing = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
                    throw BoardError.missingReminder
                }
                reminder = existing
            } else {
                reminder = EKReminder(eventStore: eventStore)
                reminder.calendar = calendar
            }
            reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.notes = BoardCategory.write(draft.categoryID, to: draft.notes, categories: categories.categories)
            reminder.priority = draft.priority
            reminder.dueDateComponents = draft.hasDueDate
                ? Calendar.current.dateComponents([.year, .month, .day], from: draft.dueDate)
                : nil
            try eventStore.save(reminder, commit: true)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func move(_ id: String, to column: String) async {
        do {
            guard let calendar = calendars[column] else { throw BoardError.missingList(column) }
            guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
                throw BoardError.missingReminder
            }
            guard reminder.calendar.calendarIdentifier != calendar.calendarIdentifier else { return }
            reminder.calendar = calendar
            try eventStore.save(reminder, commit: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCategory(_ categoryID: String?, for id: String) async {
        await edit(id) { reminder in
            reminder.notes = BoardCategory.write(categoryID, to: reminder.notes ?? "", categories: categories.categories)
        }
    }

    func setPriority(_ priority: Int, for id: String) async {
        await edit(id) { $0.priority = priority }
    }

    func setDueDate(_ date: Date?, for id: String) async {
        await edit(id) { reminder in
            reminder.dueDateComponents = date.map {
                Calendar.current.dateComponents([.year, .month, .day], from: $0)
            }
        }
    }

    private func edit(_ id: String, change: (EKReminder) -> Void) async {
        do {
            guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
                throw BoardError.missingReminder
            }
            change(reminder)
            try eventStore.save(reminder, commit: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func complete(_ id: String) async {
        do {
            guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
                throw BoardError.missingReminder
            }
            reminder.isCompleted = true
            try eventStore.save(reminder, commit: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveCalendars() throws {
        let all = eventStore.calendars(for: .reminder)
        for name in Self.columns {
            let matches = all.filter { $0.title == name }
            let iCloud = matches.filter { $0.source.title == "iCloud" }
            let candidates = iCloud.isEmpty ? matches : iCloud
            guard !candidates.isEmpty else { throw BoardError.missingList(name) }
            guard candidates.count == 1 else { throw BoardError.duplicateList(name) }
            calendars[name] = candidates[0]
        }
    }
}
