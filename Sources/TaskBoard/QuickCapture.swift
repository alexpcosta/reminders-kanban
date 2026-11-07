import AppKit
import AVFoundation
import Carbon
import Speech
import SwiftUI

final class TaskBoardAppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var statusItem: NSStatusItem?
    private var boardPopover: NSPopover?
    private var openBoard: (() -> Void)?

    func configureMenuBar(store: ReminderStore, publisher: BoardPublisher, openBoard: @escaping () -> Void) {
        self.openBoard = openBoard
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Task Board")
        item.button?.toolTip = "Task Board: click for quick board, Option-click for full board"
        item.button?.action = #selector(statusItemClicked)
        item.button?.target = self

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 720, height: 500)
        popover.contentViewController = NSHostingController(rootView: MenuBarBoardView { [weak self] in
            self?.openBoard?()
        }
            .environmentObject(store)
            .environmentObject(store.categories)
            .environmentObject(publisher))
        boardPopover = popover
        statusItem = item
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            boardPopover?.performClose(nil)
            openBoard?()
            NSApp.activate(ignoringOtherApps: true)
        } else if let button = statusItem?.button, let boardPopover {
            if boardPopover.isShown {
                boardPopover.performClose(nil)
            } else {
                boardPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async { QuickCaptureCoordinator.shared.show() }
            return noErr
        }
        let installation = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)
        let shortcut = EventHotKeyID(signature: OSType(0x54424F44), id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey | cmdKey),
                                        shortcut, GetApplicationEventTarget(), 0, &hotKey)
        if installation != noErr || result != noErr {
            NSLog("Task Board shortcut install: %d registration: %d", installation, result)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

final class QuickCaptureCoordinator: NSObject, NSWindowDelegate {
    static let shared = QuickCaptureCoordinator()
    var store: ReminderStore?
    private var panel: NSPanel?
    private let dictation = ReminderDictation()

    func show() {
        guard let store else { return }
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        dictation.transcript = ""
        dictation.errorMessage = nil
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Add to ToDo"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickCaptureView(
            store: store,
            dictation: dictation,
            close: { [weak self] in self?.panel?.close() }
        ))
        panel.center()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        dictation.stop()
        panel = nil
    }
}

private final class ReminderDictation: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInputTap = false

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        let speechAccess = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechAccess == .authorized else {
            errorMessage = "Allow speech recognition for Task Board in System Settings."
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            errorMessage = "Allow microphone access for Task Board in System Settings."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable for the current language."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInputTap = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if let error {
                    if self.isRecording {
                        self.errorMessage = error.localizedDescription
                        self.stop()
                    }
                } else if result?.isFinal == true {
                    self.stop()
                }
            }
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}

private struct QuickCaptureView: View {
    let store: ReminderStore
    @ObservedObject var dictation: ReminderDictation
    let close: () -> Void
    @FocusState private var titleFocused: Bool
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to ToDo").font(.title2.bold())
            TextField("Speak or type a reminder title", text: $dictation.transcript)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
            if let message = dictation.errorMessage ?? saveError {
                Text(message).font(.caption).foregroundStyle(.red)
            } else {
                Text(dictation.isRecording ? "Listening…" : "Review the title, then press Return to save.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(dictation.isRecording ? "Stop dictation" : "Dictate",
                       systemImage: dictation.isRecording ? "stop.fill" : "mic.fill") {
                    if dictation.isRecording { dictation.stop() }
                    else { Task { await dictation.start() } }
                }
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Add to ToDo") {
                    dictation.stop()
                    saving = true
                    Task {
                        await store.refresh()
                        var draft = TaskDraft()
                        draft.title = dictation.transcript
                        if await store.save(draft, id: nil, in: "ToDo") { close() }
                        else { saveError = store.errorMessage }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            titleFocused = true
            Task { await dictation.start() }
        }
    }
}
