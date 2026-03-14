import IOKit.hid

final class LidAngleSensor {
    private let vendorID = 0x05AC
    private let productID = 0x8104
    private let usagePage = 0x0020
    private let usage = 0x008A
    private let reportID: CFIndex = 1
    private let reportBufferSize = 8

    private var hidDevice: IOHIDDevice?

    init() {
        hidDevice = findDevice()
    }

    deinit {
        stop()
    }

    func start() {
        if hidDevice == nil {
            hidDevice = findDevice()
        }

        guard let hidDevice else { return }
        _ = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        guard let hidDevice else { return }
        IOHIDDeviceClose(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func lidAngle() -> Double? {
        guard let hidDevice else { return nil }

        var report = [UInt8](repeating: 0, count: reportBufferSize)
        var reportLength = report.count

        let result = IOHIDDeviceGetReport(
            hidDevice,
            kIOHIDReportTypeFeature,
            CFIndex(reportID),
            &report,
            &reportLength
        )

        guard result == kIOReturnSuccess, reportLength >= 3 else {
            return nil
        }

        let rawValue = UInt16(report[2]) << 8 | UInt16(report[1])
        return Double(rawValue)
    }

    private func findDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDDeviceUsagePageKey as String: usagePage,
            kIOHIDDeviceUsageKey as String: usage
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            return nil
        }

        for device in devices {
            let openDeviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openDeviceResult == kIOReturnSuccess else { continue }

            var report = [UInt8](repeating: 0, count: reportBufferSize)
            var reportLength = report.count
            let result = IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                &report,
                &reportLength
            )
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))

            if result == kIOReturnSuccess, reportLength >= 3 {
                return device
            }
        }

        return nil
    }
}
