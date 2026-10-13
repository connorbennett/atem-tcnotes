import SwiftUI

@main
struct EditNotesApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("EditNotes", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 620, minHeight: 480)
        }
        .defaultSize(width: 820, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { model.confirmingNewSession = true }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .importExport) {
                Button("Export Premiere Pro XML…") { model.exportPremiereXML() }
                    .keyboardShortcut("e")
                    .disabled(model.notes.isEmpty)
            }
            CommandGroup(after: .undoRedo) {
                Button("Remove Last Note") { model.deleteMostRecentNote() }
                    .disabled(model.notes.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
