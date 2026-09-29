import SwiftUI

struct BrighternApp: App {
    @State private var engine = SyncEngine()

    var body: some Scene {
        MenuBarExtra {
            BrighternMenu(engine: engine)
        } label: {
            Image(systemName: engine.isPaused ? "sun.min" : "sun.max")
        }
        .menuBarExtraStyle(.menu)

        Window("Calibrate Brightern", id: CalibrationView.windowID) {
            CalibrationView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct BrighternMenu: View {
    let engine: SyncEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(engine.statusText)
        Divider()
        Toggle("Pause Syncing", isOn: Binding(get: { engine.isPaused }, set: engine.setPaused))
            .disabled(!engine.isSupported)
        Button("Calibrate…") {
            openWindow(id: CalibrationView.windowID)
            NSApp.activate()
        }
        .disabled(!engine.isSupported)
        Toggle("Open at Login", isOn: Binding(get: { engine.opensAtLogin }, set: engine.setOpensAtLogin))
        Divider()
        Button("Quit Brightern") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
