import Foundation

/// Maps the MacBook's brightness (0–1) to a monitor brightness (0–100%).
/// Without calibration it's 1:1; each saved calibration point bends the line through it.
struct BrightnessCurve: Codable, Equatable {
    struct Point: Codable, Hashable {
        var laptop: Double
        var monitor: Int
    }

    static let identity = BrightnessCurve()

    /// Two points closer than this count as the same level.
    private static let sameLevel = 0.02
    private static let defaultsKey = "curve"

    /// Saved calibration points, sorted by laptop level.
    private(set) var points: [Point] = []

    func monitorLevel(forLaptop laptop: Double) -> Int {
        let x = min(max(laptop, 0), 1)
        let anchors = anchors
        guard let upperIndex = anchors.firstIndex(where: { $0.laptop >= x }) else { return anchors[anchors.count - 1].monitor }
        let upper = anchors[upperIndex]
        guard upperIndex > 0 else { return upper.monitor }
        let lower = anchors[upperIndex - 1]
        let t = (x - lower.laptop) / (upper.laptop - lower.laptop)
        return Int((Double(lower.monitor) + t * Double(upper.monitor - lower.monitor)).rounded())
    }

    /// Adds a point, replacing any at nearly the same laptop level and any that would make
    /// the curve go backwards (a brighter MacBook must never mean a dimmer monitor).
    mutating func add(laptop: Double, monitor: Int) {
        let new = Point(laptop: min(max(laptop, 0), 1), monitor: min(max(monitor, 0), 100))
        points.removeAll {
            abs($0.laptop - new.laptop) < Self.sameLevel
                || ($0.laptop < new.laptop && $0.monitor > new.monitor)
                || ($0.laptop > new.laptop && $0.monitor < new.monitor)
        }
        points.append(new)
        points.sort { $0.laptop < $1.laptop }
    }

    mutating func remove(_ point: Point) {
        points.removeAll { $0 == point }
    }

    /// Saved points plus fixed ends at 0 → 0% and 1 → 100%, unless a saved point sits there.
    private var anchors: [Point] {
        var result = points
        if result.first.map({ $0.laptop > Self.sameLevel }) ?? true {
            result.insert(Point(laptop: 0, monitor: 0), at: 0)
        }
        if result.last.map({ $0.laptop < 1 - Self.sameLevel }) ?? true {
            result.append(Point(laptop: 1, monitor: 100))
        }
        return result
    }

    static func load(from defaults: UserDefaults = .standard) -> BrightnessCurve {
        guard let data = defaults.data(forKey: defaultsKey),
            let curve = try? JSONDecoder().decode(BrightnessCurve.self, from: data)
        else { return .identity }
        return curve
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
