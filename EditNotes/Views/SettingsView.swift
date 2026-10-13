import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Timecode", systemImage: "clock") { TimecodeSettings() }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutSettings() }
            Tab("OSC", systemImage: "dot.radiowaves.left.and.right") { OSCSettings() }
            Tab("ATEM", systemImage: "rectangle.3.group") { ATEMSettings() }
        }
        .frame(width: 680, height: 460)
    }
}

private struct TimecodeSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Clock") {
                Picker("Timecode source", selection: $model.source) {
                    ForEach(TimecodeSource.allCases) { Text($0.label).tag($0) }
                }
                Picker("Frame rate", selection: $model.frameRate) {
                    ForEach(FrameRate.allCases) { Text("\($0.label) fps").tag($0) }
                }
                Picker("Time zone", selection: $model.useLocalTimeZone) {
                    Text("GMT").tag(false)
                    Text("This Mac's time zone").tag(true)
                }
            }
            Section("NTP") {
                TextField("Server", text: $model.ntpServer)
                    .onSubmit { model.startNTPSync() }
                LabeledContent("Status") {
                    HStack {
                        Text(model.ntpStatus).foregroundStyle(.secondary)
                        Button("Sync Now") { model.startNTPSync() }
                    }
                }
            }
            Section("Premiere Pro export") {
                TextField("Sequence start timecode", text: $model.sequenceStart)
                Text("Markers are placed relative to this start. Leave at 00:00:00:00 unless your sequence starts elsewhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($model.shortcuts) { $shortcut in
                    HStack(spacing: 10) {
                        Text("\((model.shortcuts.firstIndex { $0.id == shortcut.id } ?? 0) + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        ColorMenu(selection: $shortcut.color)
                        TextField("Label", text: $shortcut.label)
                            .frame(width: 90)
                        TextField("Comment (optional)", text: $shortcut.text)
                        HotkeyRecorder(shortcut: shortcut)
                        Text(model.oscAddress(for: shortcut))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(width: 170, alignment: .leading)
                            .lineLimit(1)
                        Button("Remove", systemImage: "minus.circle") {
                            model.shortcuts.removeAll { $0.id == shortcut.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                    }
                    .textFieldStyle(.roundedBorder)
                }
                .onMove { model.shortcuts.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack {
                Button("Add Shortcut", systemImage: "plus") {
                    model.shortcuts.append(Shortcut(label: "NEW", color: .blue))
                }
                Spacer()
                Text("Hotkeys need ⌘, ⌃ or ⌥ (or an F-key). Drag rows to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }
}

private struct HotkeyRecorder: View {
    @Environment(AppModel.self) private var model
    let shortcut: Shortcut

    private var isRecording: Bool { model.recordingHotkeyFor == shortcut.id }

    var body: some View {
        Button {
            model.recordingHotkeyFor = isRecording ? nil : shortcut.id
        } label: {
            Text(isRecording ? "Press keys…" : shortcut.hotkey?.display ?? "Set Hotkey")
                .frame(width: 84)
        }
        .tint(isRecording ? .orange : nil)
        .help("Click, then press a key combination. Delete clears it, Escape cancels.")
    }
}

private struct OSCSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Listener") {
                Toggle("Receive OSC", isOn: $model.oscEnabled)
                TextField("UDP port", value: $model.oscPort, format: .number.grouping(.never))
                LabeledContent("Status", value: model.oscStatus)
                if !model.oscLastMessage.isEmpty {
                    LabeledContent("Last message", value: model.oscLastMessage)
                }
            }
            Section("Addresses") {
                AddressRow("/editnotes/shortcut/<label>", "Add a shortcut's marker, e.g. /editnotes/shortcut/GFX")
                AddressRow("/editnotes/shortcut/<number>", "Add a shortcut's marker by its position in the list")
                AddressRow("/editnotes/shortcut  <label or number>", "Same, with the label or number as an argument")
                AddressRow("/editnotes/note  <text> [name] [colour]", "Add a free-text marker")
                AddressRow("/editnotes/undo", "Remove the most recently added marker")
            }
            Section("Bitfocus Companion") {
                Text("Install the module in this project's Companion folder, or use Companion's built-in Generic OSC connection pointed at this Mac on the port above and send the addresses listed here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AddressRow: View {
    let address: String
    let detail: String

    init(_ address: String, _ detail: String) {
        self.address = address
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(address).font(.body.monospaced()).textSelection(.enabled)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ATEMSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            if !model.atemSDKInstalled {
                Section {
                    Label("ATEM Software Control isn't installed on this Mac. Install it from Blackmagic Design to connect to a switcher.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("Switcher") {
                TextField("IP address", text: $model.atemAddress, prompt: Text("192.168.10.240"))
                    .onSubmit { model.connectATEM() }
                LabeledContent("Status") {
                    HStack {
                        Text(statusText).foregroundStyle(.secondary)
                        if model.atemState.isConnected || model.atemState == .connecting {
                            Button("Disconnect") { model.disconnectATEM() }
                        } else {
                            Button("Connect") { model.connectATEM() }
                                .disabled(model.atemAddress.isEmpty || !model.atemSDKInstalled)
                        }
                    }
                }
                Toggle("Connect when EditNotes opens", isOn: $model.atemAutoConnect)
            }
            Section("Use from the switcher") {
                Picker("Timecode source", selection: $model.source) {
                    ForEach(TimecodeSource.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Match the switcher's frame rate", isOn: $model.atemFollowsFrameRate)
                Toggle("Use the switcher's recording name as the project name", isOn: $model.atemFollowsProjectName)
                LabeledContent("Recording name", value: model.atemProjectName ?? "—")
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch model.atemState {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected(let name): "Connected to \(name)"
        case .failed(let message): message
        }
    }
}
