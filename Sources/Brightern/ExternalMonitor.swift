import Foundation
import IOKit

/// An external monitor controlled over DDC/CI: the first connected one that answers a brightness read.
/// Displays that don't speak DDC/CI (such as Apple's own, which macOS controls itself) are left alone.
/// Not thread-safe: use each instance from one queue.
final class ExternalMonitor {
    /// The product name from the monitor's EDID, e.g. "LG ULTRAGEAR+".
    let name: String

    private static let brightnessCode: UInt8 = 0x10

    private let service: CFTypeRef
    /// Raw DDC value that means 100%, as the monitor reports it (usually 100).
    private var maxValue = 100

    private init(service: CFTypeRef, name: String) {
        self.service = service
        self.name = name
    }

    /// Walks the I/O Registry in order. Each external `DCPAVServiceProxy` (the DDC channel)
    /// comes after the `IOMobileFramebufferShim` that describes the display attached to it.
    static func find() -> ExternalMonitor? {
        guard let create = PrivateAPI.avServiceCreate else { return nil }
        var iterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
            == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var previousDisplayName: String?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if IOObjectConformsTo(entry, "IOMobileFramebufferShim") != 0 {
                previousDisplayName = name(of: entry)
            } else if IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0, let name = previousDisplayName,
                property(entry, "Location") as? String == "External",
                let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue()
            {
                let monitor = ExternalMonitor(service: service, name: name)
                // Only a monitor that answers speaks DDC/CI; otherwise try the next display.
                guard let reading = monitor.read(brightnessCode), reading.max > 0 else { continue }
                monitor.maxValue = reading.max
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

    /// Nil if the framebuffer has no display attached.
    private static func name(of framebuffer: io_registry_entry_t) -> String? {
        guard let attributes = property(framebuffer, "DisplayAttributes") as? [String: Any],
            let product = attributes["ProductAttributes"] as? [String: Any]
        else { return nil }
        return product["ProductName"] as? String ?? "External monitor"
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
