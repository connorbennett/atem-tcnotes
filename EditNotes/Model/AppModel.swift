import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
final class AppModel: NSObject, ATEMBridgeDelegate {
    // MARK: Session

    var projectName = "Untitled" { didSet { scheduleSessionSave() } }
    var notes: [Note] = [] { didSet { scheduleSessionSave() } }

    // MARK: Settings

    var shortcuts: [Shortcut] = Shortcut.defaults { didSet { saveSettings() } }
    var frameRate: FrameRate = .fps25 { didSet { saveSettings() } }
    var source: TimecodeSource = .ntp { didSet { saveSettings() } }
    var ntpServer = "time.apple.com" { didSet { saveSettings() } }
    var useLocalTimeZone = false { didSet { saveSettings() } }
    var noteColor: MarkerColor = .blue { didSet { saveSettings() } }
    var sequenceStart = "00:00:00:00" { didSet { saveSettings() } }
    var oscEnabled = true { didSet { saveSettings(); restartOSC() } }
    var oscPort = 9300 { didSet { saveSettings(); restartOSC() } }
    var apiEnabled = true { didSet { saveSettings(); restartAPI() } }
    var apiPort = 9301 { didSet { saveSettings(); restartAPI() } }
    var atemAddress = "" { didSet { saveSettings() } }
    var atemAutoConnect = false { didSet { saveSettings() } }
    var atemFollowsProjectName = true { didSet { saveSettings() } }
    var atemFollowsFrameRate = true { didSet { saveSettings() } }

    // MARK: Live state

    /// The note being typed, and the timecode captured when its first character arrived.
    var draft = "" {
        didSet {
            if draft.isEmpty {
                latchedTimecode = nil
            } else if latchedTimecode == nil {
                latchedTimecode = currentTimecode()
            }
        }
    }
    private(set) var latchedTimecode: Timecode?
    /// Bumped to ask the main window to put the cursor back in the note field.
    private(set) var focusRequest = 0

    private(set) var ntpOffset: TimeInterval?
    private(set) var ntpStatus = "Not synced — using this Mac's clock"
    private(set) var oscStatus = "Off"
    private(set) var oscLastMessage = ""
    private(set) var apiStatus = "Off"
    private(set) var atemState: ATEMState = .disconnected
    private(set) var atemProjectName: String?
    var recordingHotkeyFor: Shortcut.ID?
    var confirmingNewSession = false
    /// A new project name reported by the ATEM while notes from the current project are still in the list.
    /// The main window asks whether to export and start over before switching to it.
    var pendingATEMProjectName: String?

    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored private var isLoading = true
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let oscServer = OSCServer()
    @ObservationIgnored private let apiServer = APIServer()
    @ObservationIgnored private let atem = ATEMBridge()
    @ObservationIgnored private var atemReference: (timecode: Timecode, uptime: TimeInterval)?
    @ObservationIgnored private var atemVideoMode: (timebase: Int, ntsc: Bool)?
    @ObservationIgnored private var atemWanted = false
    @ObservationIgnored private var atemPollTimer: Timer?
    @ObservationIgnored private var atemProjectNameWork: DispatchWorkItem?
    @ObservationIgnored private var ntpTask: Task<Void, Never>?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var keyMonitor: Any?

    override init() {
        super.init()
        loadSettings()
        loadSession()
        isLoading = false
        // Default shortcuts get fresh IDs each time they're generated; save them once so the IDs
        // Companion buttons refer to stay stable across launches.
        if defaults.data(forKey: "shortcuts") == nil { saveSettings() }

        atem.delegate = self
        restartOSC()
        restartAPI()
        startNTPSync()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSession() }
        }
        if atemAutoConnect, !atemAddress.isEmpty { connectATEM() }
    }

    // MARK: Timecode

    /// True when the displayed timecode is coming from the switcher rather than the NTP clock.
    var isUsingATEMTimecode: Bool { source == .atem && atemState.isConnected && atemReference != nil }

    func currentTimecode() -> Timecode {
        if source == .atem, atemState.isConnected, let reference = atemReference {
            let elapsed = ProcessInfo.processInfo.systemUptime - reference.uptime
            let frames = reference.timecode.frameCount(rate: frameRate) + Int(elapsed * frameRate.fps)
            return Timecode(frameCount: frames, rate: frameRate)
        }
        let now = Date().addingTimeInterval(ntpOffset ?? 0)
        var seconds = now.timeIntervalSince1970
        if useLocalTimeZone { seconds += Double(TimeZone.current.secondsFromGMT(for: now)) }
        seconds = seconds.truncatingRemainder(dividingBy: 86400)
        return Timecode(secondsSinceMidnight: seconds, rate: frameRate)
    }

    func startNTPSync() {
        ntpTask?.cancel()
        let host = ntpServer.trimmingCharacters(in: .whitespaces)
        ntpTask = Task { [weak self] in
            while !Task.isCancelled {
                var synced = false
                do {
                    let sample = try await NTPClient.measure(host: host)
                    guard !Task.isCancelled, let self else { return }
                    self.ntpOffset = sample.offset
                    self.ntpStatus = String(format: "%@ · offset %+.0f ms", host, sample.offset * 1000)
                    synced = true
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    let fallback = self.ntpOffset == nil ? "using this Mac's clock" : "holding last offset"
                    self.ntpStatus = "\(host) unreachable (\(error.localizedDescription)) — \(fallback)"
                }
                try? await Task.sleep(for: .seconds(synced ? 300 : 15))
            }
        }
    }

    // MARK: Notes

    func commitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            draft = ""
            return
        }
        addNote(name: "", text: text, color: noteColor, timecode: latchedTimecode ?? currentTimecode())
        draft = ""
    }

    func addNote(name: String, text: String, color: MarkerColor, timecode: Timecode) {
        let note = Note(timecode: timecode, name: name, text: text, color: color)
        let index = notes.firstIndex { $0.timecode > timecode } ?? notes.endIndex
        notes.insert(note, at: index)
    }

    func trigger(_ shortcut: Shortcut) {
        addNote(name: shortcut.label, text: shortcut.text, color: shortcut.color, timecode: currentTimecode())
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
    }

    func deleteMostRecentNote() {
        guard let latest = notes.max(by: { $0.created < $1.created }) else { return }
        delete(latest)
    }

    func newSession() {
        notes = []
        draft = ""
        if !(atemFollowsProjectName && atemProjectName != nil) { projectName = "Untitled" }
    }

    /// Returns false if the user cancelled the save panel or the file couldn't be written.
    @discardableResult
    func exportPremiereXML() -> Bool {
        let start = Timecode(string: sequenceStart, rate: frameRate) ?? Timecode(frameCount: 0, rate: frameRate)
        let xml = PremiereXML.make(projectName: projectName, notes: notes, rate: frameRate, sequenceStart: start)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(projectName) Markers.xml"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Exports the current notes under the old project name, then clears them and switches to the ATEM's
    /// new project. If the export is cancelled or fails, the notes are kept.
    func exportAndStartATEMProject() {
        guard let name = pendingATEMProjectName else { return }
        pendingATEMProjectName = nil
        if exportPremiereXML() {
            notes = []
            draft = ""
        }
        projectName = name
    }

    /// Keeps the current notes and carries on under the ATEM's new project name.
    func keepNotesForATEMProject() {
        guard let name = pendingATEMProjectName else { return }
        pendingATEMProjectName = nil
        projectName = name
    }

    // MARK: Keyboard

    func requestEntryFocus() { focusRequest += 1 }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if let id = recordingHotkeyFor {
            recordingHotkeyFor = nil
            guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return nil }
            switch event.keyCode {
            case 53: break // Escape cancels
            case 51, 117: shortcuts[index].hotkey = nil // Delete clears
            default:
                if let hotkey = Hotkey(event: event) {
                    // A combination can only belong to one shortcut.
                    for other in shortcuts.indices where shortcuts[other].hotkey == hotkey {
                        shortcuts[other].hotkey = nil
                    }
                    shortcuts[index].hotkey = hotkey
                } else {
                    NSSound.beep()
                    recordingHotkeyFor = id
                }
            }
            return nil
        }

        if let shortcut = shortcuts.first(where: { $0.hotkey?.matches(event) == true }) {
            trigger(shortcut)
            return nil
        }

        // Typing anywhere in the main window lands in the note field, so a note can always be started.
        guard let window = event.window, window === mainWindow,
              !(window.firstResponder is NSTextView),
              event.modifierFlags.isDisjoint(with: [.command, .control]),
              let characters = event.characters,
              let scalar = characters.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F, !(0xF700...0xF8FF).contains(scalar.value)
        else { return event }
        draft += characters
        requestEntryFocus()
        return nil
    }

    // MARK: OSC

    private func restartOSC() {
        guard !isLoading else { return }
        oscServer.stop()
        guard oscEnabled else {
            oscStatus = "Off"
            return
        }
        guard let port = UInt16(exactly: oscPort), port > 0 else {
            oscStatus = "Invalid port \(oscPort)"
            return
        }
        do {
            try oscServer.start(port: port) { [weak self] message in
                Task { @MainActor [weak self] in self?.handleOSC(message) }
            }
            oscStatus = "Listening on UDP \(port)"
        } catch {
            oscStatus = error.localizedDescription
        }
    }

    /// Addresses:
    ///   /editnotes/shortcut/<index or label>   (or the index/label as the first argument)
    ///   /editnotes/note  <text> [name] [colour]
    ///   /editnotes/undo
    func handleOSC(_ message: OSCMessage) {
        let parts = message.address.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        guard parts.count >= 2, parts[0].lowercased() == "editnotes" else { return }
        var outcome = "ignored"

        switch parts[1].lowercased() {
        case "shortcut", "marker":
            let key = parts.count > 2
                ? parts[2...].joined(separator: "/")
                : message.arguments.first.flatMap { $0.stringValue ?? $0.intValue.map(String.init) }
            if let key, let shortcut = shortcut(matching: key) {
                trigger(shortcut)
                outcome = shortcut.label
            } else {
                outcome = "no shortcut matches “\(key ?? "")”"
            }
        case "note":
            let strings = message.arguments.compactMap(\.stringValue)
            if let text = strings.first, !text.isEmpty {
                let color = strings.count > 2 ? MarkerColor(rawValue: strings[2].lowercased()) : nil
                addNote(name: strings.count > 1 ? strings[1] : "", text: text,
                        color: color ?? noteColor, timecode: currentTimecode())
                outcome = "note added"
            } else {
                outcome = "note needs a text argument"
            }
        case "undo":
            deleteMostRecentNote()
            outcome = "removed last note"
        default:
            break
        }
        oscLastMessage = "\(message.address) → \(outcome)"
    }

    /// Matches a shortcut's ID, then a 1-based position, then a label (case-insensitive).
    private func shortcut(matching key: String) -> Shortcut? {
        if let id = UUID(uuidString: key), let shortcut = shortcuts.first(where: { $0.id == id }) { return shortcut }
        if let index = Int(key), shortcuts.indices.contains(index - 1) { return shortcuts[index - 1] }
        return shortcuts.first { $0.label.caseInsensitiveCompare(key) == .orderedSame }
    }

    func oscAddress(for shortcut: Shortcut) -> String {
        let label = shortcut.label.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? shortcut.label
        return "/editnotes/shortcut/\(label)"
    }

    // MARK: Companion API

    private func restartAPI() {
        guard !isLoading else { return }
        apiServer.stop()
        guard apiEnabled else {
            apiStatus = "Off"
            return
        }
        guard let port = UInt16(exactly: apiPort), port > 0 else {
            apiStatus = "Invalid port \(apiPort)"
            return
        }
        do {
            try apiServer.start(port: port) { [weak self] in
                await self?.apiStateJSON() ?? Data("{}".utf8)
            } onFailure: { [weak self] message in
                Task { @MainActor [weak self] in self?.apiStatus = "Can't listen on TCP \(port): \(message)" }
            }
            apiStatus = "Listening on TCP \(port)"
        } catch {
            apiStatus = "Can't listen on TCP \(port): \(error.localizedDescription)"
        }
    }

    /// What the Companion module needs to build its buttons and send triggers back over OSC.
    private func apiStateJSON() -> Data {
        let state: [String: Any] = [
            "app": "EditNotes",
            "projectName": projectName,
            "oscPort": oscEnabled ? oscPort : 0,
            "shortcuts": shortcuts.enumerated().map { index, shortcut in
                [
                    "id": shortcut.id.uuidString,
                    "index": index + 1,
                    "label": shortcut.label,
                    "text": shortcut.text,
                    "color": shortcut.color.rawValue,
                    "rgb": [shortcut.color.rgb.r, shortcut.color.rgb.g, shortcut.color.rgb.b],
                ] as [String: Any]
            },
        ]
        return (try? JSONSerialization.data(withJSONObject: state)) ?? Data("{}".utf8)
    }

    // MARK: ATEM

    @ObservationIgnored let atemSDKInstalled = ATEMBridge.sdkInstalled

    func connectATEM() {
        let address = atemAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        atemWanted = true
        atemState = .connecting
        atem.connect(toAddress: address) { [weak self] productName, error in
            guard let self else { return }
            if let productName {
                self.atemState = .connected(productName)
                self.atemPollTimer?.invalidate()
                self.atemPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.atem.requestTimecode() }
                }
            } else {
                self.atemState = .failed(error ?? "Couldn't connect")
                self.scheduleATEMReconnect()
            }
        }
    }

    func disconnectATEM() {
        atemWanted = false
        atem.disconnect()
        atemDidDrop(state: .disconnected)
    }

    private func atemDidDrop(state: ATEMState) {
        atemPollTimer?.invalidate()
        atemPollTimer = nil
        atemReference = nil
        atemVideoMode = nil
        atemProjectName = nil
        atemState = state
    }

    private func scheduleATEMReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.atemWanted, !self.atemState.isConnected, self.atemState != .connecting else { return }
            self.connectATEM()
        }
    }

    func atemBridgeDidDisconnect() {
        atemDidDrop(state: .failed("Connection lost"))
        if atemWanted { scheduleATEMReconnect() }
    }

    func atemBridgeDidReceiveTimecode(withHours hours: Int, minutes: Int, seconds: Int, frames: Int,
                                      dropFrame: Bool, uptime: TimeInterval) {
        if atemFollowsFrameRate, source == .atem, let mode = atemVideoMode,
           let rate = FrameRate.matching(timebase: mode.timebase, ntsc: mode.ntsc, dropFrame: dropFrame),
           rate != frameRate {
            frameRate = rate
        }
        atemReference = (Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames,
                                  dropFrame: frameRate.isDropFrame), uptime)
    }

    func atemBridgeProjectNameDidChange(_ name: String?) {
        atemProjectName = name
        // Wait for the name to settle so a rename in progress on the switcher doesn't prompt per keystroke.
        atemProjectNameWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyATEMProjectName(name) }
        atemProjectNameWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func applyATEMProjectName(_ name: String?) {
        guard atemFollowsProjectName, let name, name != projectName else {
            // Changed back to the current project while the prompt was up: nothing to ask any more.
            if name == projectName { pendingATEMProjectName = nil }
            return
        }
        if notes.isEmpty {
            projectName = name
        } else {
            pendingATEMProjectName = name
            NSApp.requestUserAttention(.criticalRequest)
        }
    }

    func atemBridgeVideoModeDidChange(withTimebase timebase: Int, ntsc: Bool) {
        atemVideoMode = (timebase, ntsc)
    }

    // MARK: Persistence

    private var sessionURL: URL {
        let folder = URL.applicationSupportDirectory.appending(path: "EditNotes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "session.json")
    }

    private struct Session: Codable {
        var projectName: String
        var notes: [Note]
    }

    private func loadSession() {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(Session.self, from: data) else { return }
        projectName = session.projectName
        notes = session.notes
    }

    private func scheduleSessionSave() {
        guard !isLoading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSession() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func saveSession() {
        saveWork?.cancel()
        guard let data = try? JSONEncoder().encode(Session(projectName: projectName, notes: notes)) else { return }
        try? data.write(to: sessionURL, options: .atomic)
    }

    private func loadSettings() {
        if let data = defaults.data(forKey: "shortcuts"),
           let saved = try? JSONDecoder().decode([Shortcut].self, from: data) {
            shortcuts = saved
        }
        frameRate = defaults.string(forKey: "frameRate").flatMap(FrameRate.init) ?? frameRate
        source = defaults.string(forKey: "source").flatMap(TimecodeSource.init) ?? source
        ntpServer = defaults.string(forKey: "ntpServer") ?? ntpServer
        useLocalTimeZone = defaults.bool(forKey: "useLocalTimeZone")
        noteColor = defaults.string(forKey: "noteColor").flatMap(MarkerColor.init) ?? noteColor
        sequenceStart = defaults.string(forKey: "sequenceStart") ?? sequenceStart
        oscEnabled = defaults.object(forKey: "oscEnabled") as? Bool ?? oscEnabled
        oscPort = defaults.object(forKey: "oscPort") as? Int ?? oscPort
        apiEnabled = defaults.object(forKey: "apiEnabled") as? Bool ?? apiEnabled
        apiPort = defaults.object(forKey: "apiPort") as? Int ?? apiPort
        atemAddress = defaults.string(forKey: "atemAddress") ?? atemAddress
        atemAutoConnect = defaults.bool(forKey: "atemAutoConnect")
        atemFollowsProjectName = defaults.object(forKey: "atemFollowsProjectName") as? Bool ?? atemFollowsProjectName
        atemFollowsFrameRate = defaults.object(forKey: "atemFollowsFrameRate") as? Bool ?? atemFollowsFrameRate
    }

    private func saveSettings() {
        guard !isLoading else { return }
        defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts")
        defaults.set(frameRate.rawValue, forKey: "frameRate")
        defaults.set(source.rawValue, forKey: "source")
        defaults.set(ntpServer, forKey: "ntpServer")
        defaults.set(useLocalTimeZone, forKey: "useLocalTimeZone")
        defaults.set(noteColor.rawValue, forKey: "noteColor")
        defaults.set(sequenceStart, forKey: "sequenceStart")
        defaults.set(oscEnabled, forKey: "oscEnabled")
        defaults.set(oscPort, forKey: "oscPort")
        defaults.set(apiEnabled, forKey: "apiEnabled")
        defaults.set(apiPort, forKey: "apiPort")
        defaults.set(atemAddress, forKey: "atemAddress")
        defaults.set(atemAutoConnect, forKey: "atemAutoConnect")
        defaults.set(atemFollowsProjectName, forKey: "atemFollowsProjectName")
        defaults.set(atemFollowsFrameRate, forKey: "atemFollowsFrameRate")
    }
}
