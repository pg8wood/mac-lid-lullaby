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
        if hidDevice != nil {
            logMessage("Initialized HID lid angle sensor")
        } else {
            logMessage("Failed to find HID lid angle sensor")
        }
    }

    deinit {
        stop()
    }

    func start() {
        if hidDevice == nil {
            hidDevice = findDevice()
        }

        guard let hidDevice else { return }
        let result = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        logMessage("IOHIDDeviceOpen returned 0x\(String(result, radix: 16))")
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

        logMessage("Found \(devices.count) matching HID lid sensor device(s)")

        for (index, device) in devices.enumerated() {
            let openDeviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openDeviceResult == kIOReturnSuccess else {
                logMessage("Failed to open HID device \(index)")
                continue
            }

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
                logMessage("Using HID lid sensor device \(index)")
                return device
            }

            logMessage("HID device \(index) probe failed with 0x\(String(result, radix: 16)) and length \(reportLength)")
        }

        return nil
    }
}
