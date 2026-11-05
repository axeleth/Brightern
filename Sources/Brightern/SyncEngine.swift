import AppKit
import Observation
import ServiceManagement

/// Sets the external monitor's brightness. With the lid open it copies the MacBook's brightness whenever
/// macOS changes it: brightness keys, the Control Center slider, or auto-brightness. With the lid closed
/// there's nothing to copy, so the brightness keys set the monitor directly. Main thread only.
@Observable
final class SyncEngine {
    private(set) var laptopLevel: Double?
    private(set) var monitorLevel: Int?
    private(set) var monitorConnected = false
    /// The monitor last found. Kept after it's unplugged, so settings can still name it.
    private(set) var monitorName: String?
    /// No built-in screen is online, so the brightness keys have nothing else to control.
    private(set) var lidClosed = false
    private(set) var isPaused: Bool
    private(set) var opensAtLogin: Bool
    private(set) var showsMenuBarIcon: Bool
    private(set) var curve: BrightnessCurve
    private(set) var isCalibrating = false
    /// The monitor level picked with the calibration slider.
    private(set) var calibrationLevel = 50
    let isSupported = PrivateAPI.isAvailable

    @ObservationIgnored private let link = MonitorLink()
    @ObservationIgnored private let keys = BrightnessKeys()
    @ObservationIgnored private var observedDisplays = Set<CGDirectDisplayID>()
    @ObservationIgnored private var pendingResync: DispatchWorkItem?

    /// For the C callbacks, which can't capture context.
    private static weak var instance: SyncEngine?
    private static let pausedKey = "paused"
    private static let hidesMenuBarIconKey = "hidesMenuBarIcon"

    init() {
        curve = BrightnessCurve.load()
        isPaused = UserDefaults.standard.bool(forKey: Self.pausedKey)
        opensAtLogin = SMAppService.mainApp.status == .enabled
        showsMenuBarIcon = !UserDefaults.standard.bool(forKey: Self.hidesMenuBarIconKey)
        guard isSupported else { return }

        Self.instance = self
        link.onWrite = { [weak self] level in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                monitorConnected = level != nil
                if let level { monitorLevel = level }
                updateKeys()
            }
        }
        keys.onStep = { [weak self] up, fine in self?.brightnessKeyPressed(up: up, fine: fine) }
        registerForSystemEvents()
        resync()
    }

    var statusText: String {
        guard isSupported else { return "Not available on this version of macOS" }
        guard monitorConnected else { return "Monitor not connected" }
        let monitor = monitorLevel.map { "\($0)%" } ?? "…"
        if isPaused { return "Paused · Monitor \(monitor)" }
        if lidClosed { return "Brightness keys → Monitor \(monitor)" }
        guard let laptopLevel else { return "Monitor \(monitor)" }
        return "MacBook \(Int((laptopLevel * 100).rounded()))% → Monitor \(monitor)"
    }

    /// Whether the brightness keys set the monitor. Only with the lid closed, so they never take over
    /// from the MacBook's screen, and only when there's a monitor for them to set.
    var keysControlMonitor: Bool {
        isSupported && !isPaused && lidClosed && monitorConnected
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        UserDefaults.standard.set(paused, forKey: Self.pausedKey)
        if let target { link.send(target, force: true) }
        updateKeys()
    }

    func setShowsMenuBarIcon(_ shows: Bool) {
        showsMenuBarIcon = shows
        UserDefaults.standard.set(!shows, forKey: Self.hidesMenuBarIconKey)
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Brightern: couldn't change the login item: \(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Calibration

    func beginCalibration() {
        isCalibrating = true
        calibrationLevel = laptopLevel.map(curve.monitorLevel(forLaptop:)) ?? monitorLevel ?? 50
        link.send(calibrationLevel, force: true)
    }

    func previewCalibrationLevel(_ level: Int) {
        calibrationLevel = level
        link.send(level)
    }

    func saveCalibrationLevel() {
        guard let laptopLevel else { return }
        curve.add(laptop: laptopLevel, monitor: calibrationLevel)
        curve.save()
    }

    func removeCalibrationPoint(_ point: BrightnessCurve.Point) {
        curve.remove(point)
        curve.save()
    }

    func resetCalibration() {
        curve = .identity
        curve.save()
        if let laptopLevel { previewCalibrationLevel(curve.monitorLevel(forLaptop: laptopLevel)) }
    }

    func endCalibration() {
        isCalibrating = false
        if let target { link.send(target) }
    }

    // MARK: Syncing

    /// The level the monitor should be at right now, or nil if Brightern should leave it alone.
    private var target: Int? {
        if isCalibrating { return calibrationLevel }
        guard !isPaused, let laptopLevel else { return nil }
        return curve.monitorLevel(forLaptop: laptopLevel)
    }

    private func laptopBrightnessChanged(to level: Double) {
        laptopLevel = level
        if isCalibrating { calibrationLevel = curve.monitorLevel(forLaptop: level) }
        if let target { link.send(target) }
    }

    // MARK: Brightness keys (lid closed)

    private func updateKeys() {
        keys.isEnabled = keysControlMonitor
    }

    /// Steps the monitor like macOS steps the MacBook's screen: 16 steps, or 64 with Option-Shift.
    /// There's no on-screen indicator: macOS 26's own one only shows levels of screens macOS controls,
    /// so for this monitor its bar would always be empty.
    private func brightnessKeyPressed(up: Bool, fine: Bool) {
        guard keysControlMonitor, let current = monitorLevel else { return }
        let level = BrightnessKeys.step(from: current, up: up, steps: fine ? 64 : 16)
        monitorLevel = level  // right away, so quick presses add up before the monitor confirms each one
        if isCalibrating { calibrationLevel = level }
        link.send(level)
    }

    private func observeBuiltInDisplay() {
        guard let display = BuiltInDisplay.id, !observedDisplays.contains(display),
            let register = PrivateAPI.registerForBrightnessChanges
        else { return }
        let result = register(display, nil) { _, _, _, _, userInfo in
            let value = (userInfo as NSDictionary?)?["value"]
            let level = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap { Double($0) }
            DispatchQueue.main.async {
                guard let engine = SyncEngine.instance,
                    let level = level ?? BuiltInDisplay.id.flatMap(BuiltInDisplay.brightness)
                else { return }
                engine.laptopBrightnessChanged(to: level)
            }
        }
        if result == 0 { observedDisplays.insert(display) }
    }

    private func registerForSystemEvents() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.async { SyncEngine.instance?.displaysChanged() }
        }, nil)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleResync() }
        }
    }

    /// A display was added, removed or reconfigured, e.g. the lid opened or closed. When the lid opens,
    /// the brightness keys go back to macOS straight away; the rest waits for the displays to settle.
    private func displaysChanged() {
        lidClosed = BuiltInDisplay.id == nil
        updateKeys()
        scheduleResync()
    }

    /// Displays need a moment after waking, opening the lid or being plugged in, so wait before talking to them.
    private func scheduleResync(after delay: TimeInterval = 2, attempt: Int = 1) {
        pendingResync?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.resync(attempt: attempt) }
        pendingResync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resync(attempt: Int = 1) {
        observeBuiltInDisplay()
        let builtIn = BuiltInDisplay.id
        lidClosed = builtIn == nil
        updateKeys()
        laptopLevel = builtIn.flatMap(BuiltInDisplay.brightness)
        let target = target
        link.reconnect(applying: target) { [weak self] found, reported in
            guard let self else { return }
            monitorConnected = found != nil
            if let found { monitorName = found }
            if let reported { monitorLevel = reported }
            updateKeys()
            let settled = found != nil && reported != nil && (target == nil || abs(reported! - target!) <= 1)
            if !settled && attempt < 5 { scheduleResync(after: 1.5, attempt: attempt + 1) }
        }
    }
}
