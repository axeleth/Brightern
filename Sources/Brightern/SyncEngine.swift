import AppKit
import Observation
import ServiceManagement

/// Copies the MacBook's brightness to the Tern monitor whenever macOS changes it:
/// brightness keys, the Control Center slider, or auto-brightness. Main thread only.
@Observable
final class SyncEngine {
    private(set) var laptopLevel: Double?
    private(set) var monitorLevel: Int?
    private(set) var monitorConnected = false
    private(set) var isPaused: Bool
    private(set) var opensAtLogin: Bool
    private(set) var curve: BrightnessCurve
    private(set) var isCalibrating = false
    /// The monitor level picked with the calibration slider.
    private(set) var calibrationLevel = 50
    let isSupported = PrivateAPI.isAvailable

    @ObservationIgnored private let link = MonitorLink()
    @ObservationIgnored private var observedDisplays = Set<CGDirectDisplayID>()
    @ObservationIgnored private var pendingResync: DispatchWorkItem?

    /// For the C callbacks, which can't capture context.
    private static weak var instance: SyncEngine?
    private static let pausedKey = "paused"

    init() {
        curve = BrightnessCurve.load()
        isPaused = UserDefaults.standard.bool(forKey: Self.pausedKey)
        opensAtLogin = SMAppService.mainApp.status == .enabled
        guard isSupported else { return }

        Self.instance = self
        link.onWrite = { [weak self] level in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                monitorConnected = level != nil
                if let level { monitorLevel = level }
            }
        }
        registerForSystemEvents()
        resync()
    }

    var statusText: String {
        guard isSupported else { return "Not available on this version of macOS" }
        guard monitorConnected else { return "Tern monitor not connected" }
        let monitor = monitorLevel.map { "\($0)%" } ?? "…"
        guard let laptopLevel else { return "Lid closed · Monitor \(monitor)" }
        if isPaused { return "Paused · Monitor \(monitor)" }
        return "MacBook \(Int((laptopLevel * 100).rounded()))% → Monitor \(monitor)"
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        UserDefaults.standard.set(paused, forKey: Self.pausedKey)
        if let target { link.send(target, force: true) }
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
            DispatchQueue.main.async { SyncEngine.instance?.scheduleResync() }
        }, nil)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleResync() }
        }
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
        laptopLevel = BuiltInDisplay.id.flatMap(BuiltInDisplay.brightness)
        let target = target
        link.reconnect(applying: target) { [weak self] connected, reported in
            guard let self else { return }
            monitorConnected = connected
            if let reported { monitorLevel = reported }
            let settled = connected && reported != nil && (target == nil || abs(reported! - target!) <= 1)
            if !settled && attempt < 5 { scheduleResync(after: 1.5, attempt: attempt + 1) }
        }
    }
}
