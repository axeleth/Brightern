import CoreGraphics
import Foundation

/// The MacBook's own screen. Brightern only ever reads its brightness, never sets it.
enum BuiltInDisplay {
    /// Nil while the lid is closed.
    static var id: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Brightness from 0 to 1, as shown by the macOS brightness slider.
    static func brightness(of display: CGDirectDisplayID) -> Double? {
        guard let get = PrivateAPI.getBrightness else { return nil }
        var value: Float = 0
        return get(display, &value) == 0 ? Double(value) : nil
    }
}
