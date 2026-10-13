import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var entryFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            ShortcutGrid()
            EntryBar(entryFocused: $entryFocused)
            Divider()
            NotesList()
            Divider()
            StatusBar()
        }
        .background(WindowAccessor { model.mainWindow = $0 })
        .toolbar {
            ToolbarItem {
                Button("Export XML", systemImage: "square.and.arrow.up") { model.exportPremiereXML() }
                    .disabled(model.notes.isEmpty)
                    .help("Export markers as Premiere Pro XML")
            }
            ToolbarItem {
                Button("New Session", systemImage: "trash") { model.confirmingNewSession = true }
                    .help("Clear all notes and start a new session")
            }
            ToolbarItem {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
        .confirmationDialog("Start a new session?", isPresented: $model.confirmingNewSession) {
            Button("Delete \(model.notes.count) Notes", role: .destructive) { model.newSession() }
        } message: {
            Text("This removes every note in the current session. Export first if you need them.")
        }
        .defaultFocus($entryFocused, true)
        .onAppear { DispatchQueue.main.async { focusEntry() } }
        .onChange(of: model.focusRequest) { focusEntry() }
    }

    /// Focuses the note field with the cursor at the end, rather than AppKit's default select-all.
    private func focusEntry() {
        entryFocused = true
        DispatchQueue.main.async {
            guard let editor = model.mainWindow?.firstResponder as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        }
    }
}

private struct HeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 10) {
            HStack {
                TextField("Project name", text: $model.projectName)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .disabled(model.atemFollowsProjectName && model.atemProjectName != nil)
                Spacer()
                Picker("Source", selection: $model.source) {
                    Text("NTP").tag(TimecodeSource.ntp)
                    Text("ATEM").tag(TimecodeSource.atem)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Picker("Frame rate", selection: $model.frameRate) {
                    ForEach(FrameRate.allCases) { Text("\($0.label) fps").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                Text(model.currentTimecode().string)
                    .font(.system(size: 72, weight: .medium, design: .monospaced))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }

            Text(sourceCaption)
                .font(.caption)
                .foregroundStyle(sourceIsFallback ? .orange : .secondary)
        }
        .padding()
    }

    private var sourceIsFallback: Bool { model.source == .atem && !model.isUsingATEMTimecode }

    private var sourceCaption: String {
        if model.isUsingATEMTimecode { return "ATEM switcher timecode" }
        let zone = model.useLocalTimeZone ? (TimeZone.current.abbreviation() ?? "local time") : "GMT"
        return sourceIsFallback ? "ATEM not connected — showing time of day (\(zone))" : "Time of day (\(zone))"
    }
}

private struct ShortcutGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.shortcuts.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(model.shortcuts) { shortcut in
                    Button {
                        model.trigger(shortcut)
                        model.requestEntryFocus()
                    } label: {
                        VStack(spacing: 2) {
                            Text(shortcut.label.isEmpty ? "—" : shortcut.label)
                                .font(.headline)
                                .lineLimit(1)
                            Text(shortcut.hotkey?.display ?? " ")
                                .font(.caption2)
                                .opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(shortcut.color == .white || shortcut.color == .yellow ? .black : .white)
                        .background(shortcut.color.color, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(shortcut.text.isEmpty ? "Add a \(shortcut.label) marker" : shortcut.text)
                }
            }
            .padding([.horizontal, .bottom])
        }
    }
}

private struct EntryBar: View {
    @Environment(AppModel.self) private var model
    var entryFocused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            ColorMenu(selection: $model.noteColor)
            TextField("Type a note — the timecode is held from your first keystroke", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused(entryFocused)
                .onSubmit {
                    model.commitDraft()
                    entryFocused.wrappedValue = true
                }
                .onExitCommand { model.draft = "" }
            if let latched = model.latchedTimecode {
                Label(latched.string, systemImage: "pin.fill")
                    .font(.body.monospaced())
                    .foregroundStyle(.orange)
                    .help("This note will be saved at the timecode where you started typing")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
    }
}

private struct NotesList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.notes.isEmpty {
            ContentUnavailableView("No notes yet", systemImage: "note.text",
                                   description: Text("Start typing, or press a shortcut to drop a marker."))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.notes.reversed()) { note in
                        NoteRow(note: binding(for: note))
                        Divider()
                    }
                }
            }
        }
    }

    private func binding(for note: Note) -> Binding<Note> {
        Binding {
            model.notes.first { $0.id == note.id } ?? note
        } set: { updated in
            if let index = model.notes.firstIndex(where: { $0.id == note.id }) { model.notes[index] = updated }
        }
    }
}

private struct NoteRow: View {
    @Environment(AppModel.self) private var model
    @Binding var note: Note

    var body: some View {
        HStack(spacing: 10) {
            ColorMenu(selection: $note.color)
            Text(note.timecode.string)
                .font(.body.monospaced())
                .textSelection(.enabled)
            TextField("Name", text: $note.name, prompt: Text(""))
                .textFieldStyle(.plain)
                .fontWeight(.semibold)
                .frame(width: 90)
            TextField("Note", text: $note.text, prompt: Text(""))
                .textFieldStyle(.plain)
            Button("Delete", systemImage: "xmark.circle.fill") { model.delete(note) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Delete this note")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            Label(model.ntpStatus, systemImage: "clock")
                .foregroundStyle(model.ntpOffset == nil ? .orange : .secondary)
            Spacer()
            Label("OSC: \(model.oscStatus)", systemImage: "dot.radiowaves.left.and.right")
            Label("ATEM: \(atemText)", systemImage: "rectangle.3.group")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var atemText: String {
        switch model.atemState {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected(let name): name
        case .failed(let message): message
        }
    }
}

struct ColorMenu: View {
    @Binding var selection: MarkerColor

    var body: some View {
        Menu {
            ForEach(MarkerColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Label(color.name, systemImage: selection == color ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "circle.fill")
                .foregroundStyle(selection.color)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Marker colour: \(selection.name)")
    }
}

/// Reports the hosting NSWindow so key handling can tell the main window from Settings.
private struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}
