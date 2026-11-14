import Foundation
import IOKit
import IOKit.hid

/// Neigung des MacBooks aus dem eingebauten Beschleunigungssensor.
///
/// Apple-Silicon-MacBooks haben einen Beschleunigungssensor im "Sensor Processing Unit" (SPU).
/// Eine offizielle Schnittstelle gibt es nicht: Der Treiber `AppleSPUHIDDriver` mit dem Produkt
/// "accel" wird eingeschaltet, danach liefert das HID-Gerät (Usage Page 0xFF00, Usage 3) Berichte
/// mit x, y, z als Int32 in 1/65536 g ab Byte 6. Fehlt der Sensor (iMac, Mac mini, ältere Macs)
/// oder ändert Apple etwas, bleibt `isAvailable` false und Clawd merkt einfach nichts.
final class TiltSensor {
    /// Querneigung in g (≈ Sinus des Winkels), geglättet: > 0 = rechte Seite tiefer.
    private(set) var lateral: Double = 0
    private(set) var isAvailable = false
    private(set) var isRunning = false

    /// Welche Sensorachse quer zum Bildschirm liegt und in welche Richtung sie zeigt
    /// (gemessen am MacBook Pro 14", M2 Max).
    static let axisOffset = 6
    static let axisSign: Double = 1

    private var manager: IOHIDManager?
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private static let reportSize = 64
    /// 25 Berichte pro Sekunde reichen für eine ruhige Neigung.
    private static let reportInterval = 40_000 // µs

    init() {
        isAvailable = Self.accelDriver() != nil
    }

    func start() {
        guard isAvailable, !isRunning else { return }
        guard Self.setDriver(on: true) else { isAvailable = false; return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 3] as CFDictionary)
        guard IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>, !devices.isEmpty else {
            Self.setDriver(on: false)
            isAvailable = false
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for device in devices {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportSize)
            buffers.append(buffer)
            IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.reportSize, { context, _, _, _, _, report, length in
                guard let context else { return }
                let sensor = Unmanaged<TiltSensor>.fromOpaque(context).takeUnretainedValue()
                sensor.receive(UnsafeBufferPointer(start: report, count: length))
            }, context)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        manager = m
        isRunning = true
        DebugLog.log("Neigungssensor an (\(devices.count) Gerät(e))")
    }

    func stop() {
        guard isRunning, let m = manager else { return }
        if let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> {
            for device in devices {
                IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            }
        }
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        Self.setDriver(on: false)
        buffers.forEach { $0.deallocate() }
        buffers = []
        isRunning = false
        lateral = 0
    }

    deinit { stop() }

    private func receive(_ report: UnsafeBufferPointer<UInt8>) {
        guard let g = Self.lateral(from: report) else { return }
        // Glätten: Ruckler beim Tippen sollen Clawd nicht umwerfen.
        lateral += (g - lateral) * 0.15
    }

    /// Querbeschleunigung in g aus einem Sensorbericht.
    static func lateral(from report: UnsafeBufferPointer<UInt8>) -> Double? {
        let o = axisOffset
        guard report.count >= o + 4 else { return nil }
        let raw = UInt32(report[o]) | UInt32(report[o + 1]) << 8 | UInt32(report[o + 2]) << 16 | UInt32(report[o + 3]) << 24
        return axisSign * Double(Int32(bitPattern: raw)) / 65536
    }

    // MARK: - Treiber

    private static func accelDriver() -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let product = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if product == "accel" { return service }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Nur den Beschleunigungssensor ein- oder ausschalten – die anderen Sensoren (Umgebungslicht
    /// usw.) bleiben unberührt.
    @discardableResult
    private static func setDriver(on: Bool) -> Bool {
        guard let driver = accelDriver() else { return false }
        defer { IOObjectRelease(driver) }
        let values: [(String, Int)] = on
            ? [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", reportInterval)]
            : [("SensorPropertyReportingState", 0), ("SensorPropertyPowerState", 0)]
        return values.allSatisfy { key, value in
            IORegistryEntrySetCFProperty(driver, key as CFString, value as CFNumber) == KERN_SUCCESS
        }
    }
}
