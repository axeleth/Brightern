import Foundation

/// Talks to the monitor on a background queue. DDC is slow (~30 ms per write), so requests
/// that arrive faster than that — e.g. during macOS's brightness animation — are merged,
/// and the monitor always ends on the newest level.
final class MonitorLink {
    /// Called on the DDC queue after each write: the level written, or nil if the monitor didn't respond.
    var onWrite: ((Int?) -> Void)?

    private let queue = DispatchQueue(label: "com.axelehrnrooth.brightern.ddc", qos: .userInitiated)

    private let lock = NSLock()
    private var pending: (level: Int, force: Bool)?  // guarded by lock
    private var draining = false  // guarded by lock

    private var monitor: TernMonitor?  // DDC queue only
    private var lastWritten: Int?  // DDC queue only

    /// Queues a level for the monitor. Unless `force` is set, it's skipped if the monitor is already there.
    func send(_ level: Int, force: Bool = false) {
        lock.lock()
        pending = (level, force || pending?.force == true)
        let startDraining = !draining
        draining = true
        lock.unlock()
        if startDraining { queue.async { self.drain() } }
    }

    /// Finds the monitor again (after waking or being plugged in) and applies `level` if given.
    /// Calls back on the main queue with whether it's connected and the level it reports.
    func reconnect(applying level: Int?, completion: @escaping (_ connected: Bool, _ level: Int?) -> Void) {
        queue.async {
            self.monitor = TernMonitor.find()
            self.lastWritten = nil
            var reported: Int?
            if let monitor = self.monitor {
                if let level, monitor.setBrightness(level) {
                    self.lastWritten = level
                    usleep(50_000)
                }
                reported = monitor.brightness()
            }
            let connected = self.monitor != nil
            DispatchQueue.main.async { completion(connected, reported) }
        }
    }

    private func drain() {
        while let next = takePending() {
            guard next.force || next.level != lastWritten else { continue }
            if write(next.level), !hasPending { confirm(next.level) }
        }
    }

    /// The monitor silently drops commands that arrive while it's still busy with the previous one,
    /// so once a burst of changes is over, read the level back and resend it if it didn't stick.
    private func confirm(_ level: Int) {
        for _ in 0..<2 {
            guard let monitor, let actual = monitor.brightness(), actual != level, !hasPending else { return }
            _ = write(level)
        }
    }

    /// Returns false, and forgets the monitor so it's looked up again next time, if it didn't respond.
    private func write(_ level: Int) -> Bool {
        if monitor == nil { monitor = TernMonitor.find() }
        guard let monitor, monitor.setBrightness(level) else {
            self.monitor = nil
            lastWritten = nil
            onWrite?(nil)
            return false
        }
        lastWritten = level
        onWrite?(level)
        usleep(50_000)  // DDC/CI asks hosts to wait 50 ms after a write before sending the next command
        return true
    }

    private var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending != nil
    }

    private func takePending() -> (level: Int, force: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard let next = pending else {
            draining = false
            return nil
        }
        pending = nil
        return next
    }
}
