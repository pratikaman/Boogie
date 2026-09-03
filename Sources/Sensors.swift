import Foundation
import IOKit
import IOKit.hid

// The three MacBook sensors Boogie reacts to. Each is optional: on a desktop
// Mac (or if a private API moves) the class fails to init and the matching
// crossover just stays off. Test hooks: BOOGIE_FAKE_TILT="x[,y,z]" (g),
// BOOGIE_FAKE_LID=<degrees>, BOOGIE_FAKE_LUX=<lux> feed fixed readings.

struct Vec3 {
    var x = 0.0, y = 0.0, z = 0.0
    subscript(i: Int) -> Double { i == 0 ? x : (i == 1 ? y : z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
}

/// Built-in accelerometer, streamed through the private event system client
/// (see Private.h). Values in g, low-passed for a steady tilt vector.
final class Accelerometer {
    private let lock = NSLock()
    private var smooth = Vec3()
    private var primed = false
    private var client: CFTypeRef?
    private var thread: Thread?
    private var fake: Vec3?
    private var fakeFrom: TimeInterval = 0

    init?() {
        // BOOGIE_FAKE_TILT="x[,y,z]" reports flat until BOOGIE_FAKE_TILT_AFTER seconds
        // have passed (so zeroing sees level), then the given vector.
        if let f = ProcessInfo.processInfo.environment["BOOGIE_FAKE_TILT"] {
            let p = f.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            fake = Vec3(x: p.first ?? 0, y: p.count > 1 ? p[1] : -0.03, z: p.count > 2 ? p[2] : -0.98)
            let after = ProcessInfo.processInfo.environment["BOOGIE_FAKE_TILT_AFTER"].flatMap(Double.init) ?? 0
            fakeFrom = Date().timeIntervalSinceReferenceDate + after
            smooth = Vec3(x: 0, y: -0.03, z: -0.98)
            primed = true
            return
        }
        guard let clientU = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, 3, nil) else { return nil }
        let client = clientU.takeRetainedValue()
        _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 3] as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject],
              !services.isEmpty else { return nil }
        for service in services {
            _ = IOHIDServiceClientSetProperty(service, "ReportInterval" as CFString, 10000 as CFNumber)  // ~100 Hz
        }
        self.client = client
        let target = Unmanaged.passUnretained(self).toOpaque()
        let thread = Thread {
            IOHIDEventSystemClientRegisterEventCallback(client, accelerometerCallback, target, nil)
            IOHIDEventSystemClientScheduleWithRunLoop(client, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopRun()
        }
        thread.name = "boogie.accel"
        thread.start()
        self.thread = thread
    }

    fileprivate func ingest(x: Double, y: Double, z: Double) {
        lock.lock(); defer { lock.unlock() }
        if !primed { smooth = Vec3(x: x, y: y, z: z); primed = true; return }
        smooth.x += (x - smooth.x) * 0.2
        smooth.y += (y - smooth.y) * 0.2
        smooth.z += (z - smooth.z) * 0.2
    }

    func read() -> Vec3? {
        lock.lock(); defer { lock.unlock() }
        if let fake, Date().timeIntervalSinceReferenceDate >= fakeFrom { return fake }
        return primed ? smooth : nil
    }
}

private let accelerometerEventType = 13

private let accelerometerCallback: BoogieHIDCallback = { target, _, _, event in
    guard let target, let event, IOHIDEventGetType(event) == Int32(accelerometerEventType) else { return }
    let base = Int32(accelerometerEventType << 16)
    Unmanaged<Accelerometer>.fromOpaque(target).takeUnretainedValue().ingest(
        x: IOHIDEventGetFloatValue(event, base | 0),
        y: IOHIDEventGetFloatValue(event, base | 1),
        z: IOHIDEventGetFloatValue(event, base | 2))
}

/// Hinge angle from the lid sensor ("las"), a HID device on the Sensor usage
/// page (0x20), usage 0x8A. Feature report 1, bytes 1-2 = degrees, 0 = closed.
final class LidAngleSensor {
    private let manager: IOHIDManager?
    private let device: IOHIDDevice?
    private let fake: Double?

    init?() {
        if let f = ProcessInfo.processInfo.environment["BOOGIE_FAKE_LID"].flatMap(Double.init) {
            fake = f; manager = nil; device = nil
            return
        }
        fake = nil
        let matching: [String: Any] = [kIOHIDPrimaryUsagePageKey as String: 0x0020,
                                       kIOHIDPrimaryUsageKey as String: 0x008A]
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first,
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else { return nil }
        self.manager = manager
        self.device = device
    }

    func angle() -> Double? {
        if let fake { return fake }
        guard let device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess,
              length >= 3 else { return nil }
        return Double(UInt16(report[1]) | (UInt16(report[2]) << 8))
    }
}

/// Ambient light sensor on Apple Silicon ("als", usage page 0xFF00, usage 4).
/// Holds the client and the services array alongside the service: the service
/// is owned by them, and dropping either is a use-after-free (see Firefly).
final class AmbientLight {
    private let client: CFTypeRef?
    private let services: [AnyObject]
    private let service: AnyObject?
    private let fake: Double?

    private static let eventType: Int64 = 12
    private static let fieldBase = Int32(12 << 16)

    init?() {
        if let f = ProcessInfo.processInfo.environment["BOOGIE_FAKE_LUX"].flatMap(Double.init) {
            fake = f; client = nil; services = []; service = nil
            return
        }
        fake = nil
        guard let clientU = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
        let client = clientU.takeRetainedValue()
        _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject],
              let first = services.first else { return nil }
        self.client = client
        self.services = services
        self.service = first
    }

    /// Best-effort lux. The driver's own figure when it resolves, otherwise the
    /// raw channels scaled with the factor Firefly measured on this hardware.
    func lux() -> Double? {
        if let fake { return fake }
        guard let service, let eventU = IOHIDServiceClientCopyEvent(service, Self.eventType, 0, 0) else { return nil }
        let event = eventU.takeRetainedValue()
        let driverLux = IOHIDEventGetFloatValue(event, Self.fieldBase)
        if driverLux >= 2 { return driverLux }
        let raw = (1...3).map { IOHIDEventGetFloatValue(event, Self.fieldBase + Int32($0)) }
        return max(0, raw.reduce(0, +) * 0.0366)
    }
}

struct SensorReadout {
    var tilt: Double?      // lateral tilt in g after zeroing, + = right edge down
    var lid: Double?       // hinge angle in degrees
    var lux: Double?
}

/// Owns the three sensors and turns the raw gravity vector into a zeroed,
/// calibrated lateral tilt.
final class Sensors {
    let accel = Accelerometer()
    let lid = LidAngleSensor()
    let als = AmbientLight()

    var hasAccel: Bool { accel != nil }
    var hasLid: Bool { lid != nil }
    var hasLight: Bool { als != nil }

    /// Which accelerometer axis is left/right and which way is "right edge down".
    var axis = 0
    var sign = 1.0

    private var zero: Vec3?
    private var zeroAt: TimeInterval
    private var cachedLid: Double?
    private var lidTime: TimeInterval = 0
    private var cachedLux: Double?
    private var luxTime: TimeInterval = 0

    init() {
        zeroAt = Date().timeIntervalSinceReferenceDate + 1.0
    }

    /// Raw smoothed vector and zero, for debugging.
    var rawDescription: String {
        guard let a = accel?.read() else { return "no-accel" }
        let z = zero.map { String(format: "zero(%.2f,%.2f,%.2f)", $0.x, $0.y, $0.z) } ?? "unzeroed"
        return String(format: "(%.2f,%.2f,%.2f) axis=%d sign=%.0f ", a.x, a.y, a.z, axis, sign) + z
    }

    /// Take the current resting orientation as level.
    func rezero() {
        zero = nil
        zeroAt = Date().timeIntervalSinceReferenceDate + 0.3
    }

    /// Raw vector minus the zero, for calibration.
    func delta() -> Vec3? {
        guard let a = accel?.read(), let z = zero else { return nil }
        return a - z
    }

    func read(now: TimeInterval) -> SensorReadout {
        var r = SensorReadout()
        if let a = accel?.read() {
            if zero == nil, now >= zeroAt { zero = a }
            if var z = zero {
                let d = a - z
                // Absorb slow drift, but never a real tilt.
                if abs(d[axis]) < 0.03 {
                    z.x += d.x * 0.01; z.y += d.y * 0.01; z.z += d.z * 0.01
                    zero = z
                }
                r.tilt = sign * d[axis]
            }
        }
        if now - lidTime > 0.1 { cachedLid = lid?.angle(); lidTime = now }
        r.lid = cachedLid
        if now - luxTime > 0.5 { cachedLux = als?.lux(); luxTime = now }
        r.lux = cachedLux
        return r
    }
}
