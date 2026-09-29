import AppKit
import CoreGraphics

var failures = 0

func expect(_ condition: Bool, _ message: String) {
    print(condition ? "  ok    \(message)" : "  FAIL  \(message)")
    if !condition { failures += 1 }
}

// MARK: Brightness curve

print("Brightness curve")
let identity = BrightnessCurve.identity
expect(identity.monitorLevel(forLaptop: 0) == 0, "1:1 maps 0% to 0%")
expect(identity.monitorLevel(forLaptop: 0.5) == 50, "1:1 maps 50% to 50%")
expect(identity.monitorLevel(forLaptop: 1) == 100, "1:1 maps 100% to 100%")
expect(identity.monitorLevel(forLaptop: 1.4) == 100 && identity.monitorLevel(forLaptop: -1) == 0, "out-of-range input is clamped")

var curve = BrightnessCurve()
curve.add(laptop: 0.5, monitor: 30)
expect(curve.monitorLevel(forLaptop: 0.5) == 30, "a saved point is hit exactly")
expect(curve.monitorLevel(forLaptop: 0.25) == 15, "below a point it interpolates towards 0%")
expect(curve.monitorLevel(forLaptop: 0.75) == 65, "above a point it interpolates towards 100%")
curve.add(laptop: 0.51, monitor: 40)
expect(curve.points == [.init(laptop: 0.51, monitor: 40)], "saving at nearly the same level replaces the point")
curve.add(laptop: 0.3, monitor: 60)
expect(curve.points == [.init(laptop: 0.3, monitor: 60)], "a point that would make the curve go backwards is dropped")
curve.add(laptop: 0, monitor: 10)
expect(curve.monitorLevel(forLaptop: 0) == 10, "a point at 0% replaces the fixed end")
let levels = stride(from: 0.0, through: 1.0, by: 0.01).map(curve.monitorLevel(forLaptop:))
expect(zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 }, "the curve never goes down")

// MARK: Live sync with the running app

if CommandLine.arguments.contains("--live") {
    print("Live sync")
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    let setBrightness: SetBrightness? = PrivateAPI.symbol(PrivateAPI.displayServices, "DisplayServicesSetBrightness")
    let settings = UserDefaults(suiteName: "com.axelehrnrooth.brightern")!

    guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.axelehrnrooth.brightern").isEmpty else {
        print("  Brightern isn't running."); exit(1)
    }
    guard !settings.bool(forKey: "paused") else { print("  Brightern is paused."); exit(1) }
    guard let display = BuiltInDisplay.id, let original = BuiltInDisplay.brightness(of: display),
        let setBrightness
    else { print("  Can't read the MacBook's brightness (is the lid closed?)"); exit(1) }
    guard let monitor = TernMonitor.find() else { print("  Tern monitor not found."); exit(1) }

    let appCurve = BrightnessCurve.load(from: settings)
    func verify(_ label: String) {
        let laptop = BuiltInDisplay.brightness(of: display) ?? -1
        let expected = appCurve.monitorLevel(forLaptop: laptop)
        let actual = monitor.brightness()
        expect(actual.map { abs($0 - expected) <= 1 } ?? false,
               "\(label): MacBook \(Int((laptop * 100).rounded()))% → monitor \(actual.map(String.init) ?? "?")% (expected \(expected)%)")
    }

    for level: Float in [0.3, 0.7] {
        _ = setBrightness(display, level)
        Thread.sleep(forTimeInterval: 1.2)
        verify("set to \(Int(level * 100))%")
    }
    _ = setBrightness(display, Float(original))
    Thread.sleep(forTimeInterval: 1.2)
    verify("restored")
}

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
