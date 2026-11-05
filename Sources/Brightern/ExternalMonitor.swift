import Foundation
import IOKit

/// The Tern Setups OLED monitor, controlled over DDC/CI.
/// Only this monitor is ever sent commands; any other external display is left alone.
/// Not thread-safe: use each instance from one queue.
final class TernMonitor {
    /// EDID IDs the monitor reports (manufacturer "RTK", product name "M series Mac").
    static let vendorID = 19083
    static let productID = 159

    private static let brightnessCode: UInt8 = 0x10

    private let service: CFTypeRef
    /// Raw DDC value that means 100%. The monitor reports it; it's 100 on this model.
    private var maxValue = 100

    private init(service: CFTypeRef) {
        self.service = service
    }

    /// Walks the I/O Registry in order. Each external `DCPAVServiceProxy` (the DDC channel)
    /// comes after the `IOMobileFramebufferShim` that describes the display attached to it.
    static func find() -> TernMonitor? {
        guard let create = PrivateAPI.avServiceCreate else { return nil }
        var iterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
            == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var previousDisplayIsTern = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if IOObjectConformsTo(entry, "IOMobileFramebufferShim") != 0 {
                previousDisplayIsTern = isTern(entry)
            } else if IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0, previousDisplayIsTern,
                property(entry, "Location") as? String == "External",
                let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue()
            {
                let monitor = TernMonitor(service: service)
                if let reading = monitor.read(brightnessCode), reading.max > 0 {
                    monitor.maxValue = reading.max
                }
                return monitor
            }
        }
        return nil
    }

    /// Current brightness in percent, or nil if the monitor didn't answer.
    func brightness() -> Int? {
        guard let reading = read(Self.brightnessCode), reading.max > 0 else { return nil }
        return Int((Double(reading.current) * 100 / Double(reading.max)).rounded())
    }

    /// Sets brightness in percent (0–100). Returns false if the monitor couldn't be reached.
    func setBrightness(_ percent: Int) -> Bool {
        let clamped = min(max(percent, 0), 100)
        return write(Self.brightnessCode, UInt16((Double(clamped) * Double(maxValue) / 100).rounded()))
    }

    // MARK: DDC/CI over the display's I2C bus: device 0x37, host sub-address 0x51.

    private func write(_ code: UInt8, _ value: UInt16) -> Bool {
        guard let writeI2C = PrivateAPI.avServiceWriteI2C else { return false }
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = checksum(0x6E ^ 0x51, packet[0...4])
        for _ in 0..<3 {
            var sent = false
            // Monitors commonly need the packet twice before they act on it.
            for _ in 0..<2 {
                usleep(10_000)
                if writeI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == kIOReturnSuccess { sent = true }
            }
            if sent { return true }
            usleep(20_000)
        }
        return false
    }

    private func read(_ code: UInt8) -> (current: Int, max: Int)? {
        guard let writeI2C = PrivateAPI.avServiceWriteI2C, let readI2C = PrivateAPI.avServiceReadI2C else {
            return nil
        }
        var request: [UInt8] = [0x82, 0x01, code, 0]
        request[3] = checksum(0x6E, request[0...2])
        for _ in 0..<3 {
            for _ in 0..<2 {
                usleep(10_000)
                _ = writeI2C(service, 0x37, 0x51, &request, UInt32(request.count))
            }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            if readI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess,
                checksum(0x50, reply[0...9]) == reply[10],
                reply[2] == 0x02, reply[3] == 0x00, reply[4] == code
            {
                return (Int(reply[8]) << 8 | Int(reply[9]), Int(reply[6]) << 8 | Int(reply[7]))
            }
            usleep(20_000)
        }
        return nil
    }

    private func checksum(_ seed: UInt8, _ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    private static func isTern(_ framebuffer: io_registry_entry_t) -> Bool {
        guard let attributes = property(framebuffer, "DisplayAttributes") as? [String: Any],
            let product = attributes["ProductAttributes"] as? [String: Any]
        else { return false }
        return product["LegacyManufacturerID"] as? Int == vendorID && product["ProductID"] as? Int == productID
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
