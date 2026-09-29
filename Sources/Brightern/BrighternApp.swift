import SwiftUI

struct BrighternApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        let engine = delegate.engine
        MenuBarExtra(isInserted: Binding(get: { engine.showsMenuBarIcon }, set: engine.setShowsMenuBarIcon)) {
            BrighternMenu(engine: engine, openSettings: delegate.showSettings)
        } label: {
            Image(systemName: engine.isPaused ? "sun.min" : "sun.max")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Brightern mostly lives in the menu bar. Opening it from Applications, Launchpad or Spotlight
/// shows the settings window, and it appears in the Dock only while that window is open.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = SyncEngine()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !launchedAsLoginItem { showSettings() }
    }

    /// Opening the app again while it's already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(engine: engine)))
            window.title = "Brightern"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 720, height: 500))
            window.center()
            window.setFrameAutosaveName("Settings")
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

struct BrighternMenu: View {
    let engine: SyncEngine
    let openSettings: () -> Void

    var body: some View {
        Text(engine.statusText)
        Divider()
        Toggle("Pause Syncing", isOn: Binding(get: { engine.isPaused }, set: engine.setPaused))
            .disabled(!engine.isSupported)
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Divider()
        Button("Quit Brightern") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
