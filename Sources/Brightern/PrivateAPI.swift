import CoreGraphics
import Foundation
import IOKit

/// Private Apple functions, looked up at runtime. If a macOS update removes one,
/// Brightern reports itself as unavailable instead of crashing.
enum PrivateAPI {
    typealias IOAVServiceCreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias IOAVServiceI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias DisplayServicesGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias DisplayServicesRegisterForBrightnessChangeNotifications =
        @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32

    static let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    static let displayServices = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    static let avServiceCreate: IOAVServiceCreateWithService? = symbol(ioKit, "IOAVServiceCreateWithService")
    static let avServiceReadI2C: IOAVServiceI2C? = symbol(ioKit, "IOAVServiceReadI2C")
    static let avServiceWriteI2C: IOAVServiceI2C? = symbol(ioKit, "IOAVServiceWriteI2C")
    static let getBrightness: DisplayServicesGetBrightness? = symbol(displayServices, "DisplayServicesGetBrightness")
    static let registerForBrightnessChanges: DisplayServicesRegisterForBrightnessChangeNotifications? =
        symbol(displayServices, "DisplayServicesRegisterForBrightnessChangeNotifications")

    static var isAvailable: Bool {
        avServiceCreate != nil && avServiceReadI2C != nil && avServiceWriteI2C != nil
            && getBrightness != nil && registerForBrightnessChanges != nil
    }

    static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
