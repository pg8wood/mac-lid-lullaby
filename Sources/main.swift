import AppKit
import AVFoundation
import Foundation
import IOKit.hid
import IOKit.pwr_mgt
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "MacBookLidByeBye", category: "App")
private let launchTime = Date()

private func logMessage(_ message: String) {
    let elapsed = String(format: "%.3f", Date().timeIntervalSince(launchTime))
    let formatted = "t+\(elapsed)s \(message)"
    logger.log("\(formatted, privacy: .public)")
    print("[Bye-bye] \(formatted)")
}

enum AudioSelection {
    case custom(URL)
    case bundled(URL)
    case systemSound(String)

    var displayName: String {
        switch self {
        case .custom(let url), .bundled(let url):
            return url.lastPathComponent
        case .systemSound(let name):
            return "\(name).aiff"
        }
    }
}

final class AudioLibrary {
    private let defaults = UserDefaults.standard
    private let customAudioFilenameKey = "customAudioFilename"

    func currentSelection() -> AudioSelection {
        if let url = customAudioURL() {
            return .custom(url)
        }

        if let bundledURL = Bundle.module.url(forResource: "mario-64-bye-bye", withExtension: "mp3") {
            return .bundled(bundledURL)
        }

        return .systemSound("Hero")
    }

    func importAudioFile(from sourceURL: URL) throws -> AudioSelection {
        let appSupportDirectory = try self.appSupportDirectory()
        let destinationURL = appSupportDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        if let existingURL = customAudioURL(), FileManager.default.fileExists(atPath: existingURL.path) {
            try FileManager.default.removeItem(at: existingURL)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        defaults.set(destinationURL.lastPathComponent, forKey: customAudioFilenameKey)
        return .custom(destinationURL)
    }

    func resetToBundledDefault() throws {
        if let existingURL = customAudioURL(), FileManager.default.fileExists(atPath: existingURL.path) {
            try FileManager.default.removeItem(at: existingURL)
        }

        defaults.removeObject(forKey: customAudioFilenameKey)
    }

    private func customAudioURL() -> URL? {
        guard let filename = defaults.string(forKey: customAudioFilenameKey) else {
            return nil
        }

        guard let appSupportDirectory = try? appSupportDirectory() else {
            return nil
        }

        let fileURL = appSupportDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            defaults.removeObject(forKey: customAudioFilenameKey)
            return nil
        }

        return fileURL
    }

    private func appSupportDirectory() throws -> URL {
        let baseDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseDirectory.appendingPathComponent("MacBookLidByeBye", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

final class PlaybackPowerAssertionController {
    private var displaySleepAssertionID: IOPMAssertionID?
    private var systemSleepAssertionID: IOPMAssertionID?
    private var userActivityAssertionID: IOPMAssertionID?
    private var currentReason: String?

    func beginForPlayback(reason: String) {
        beginHold(reason: reason, source: "playback")
    }

    func beginForCloseGesture(reason: String) {
        beginHold(reason: reason, source: "close gesture")
    }

    func endPlaybackHold() {
        currentReason = nil
        releaseAssertion(&displaySleepAssertionID, label: "PreventUserIdleDisplaySleep")
        releaseAssertion(&systemSleepAssertionID, label: "PreventUserIdleSystemSleep")
        releaseAssertion(&userActivityAssertionID, label: "UserIsActive")
    }

    private func beginHold(reason: String, source: String) {
        if currentReason == reason,
           displaySleepAssertionID != nil || systemSleepAssertionID != nil || userActivityAssertionID != nil {
            logMessage("Power assertions already active for \(reason) during \(source)")
            return
        }

        endPlaybackHold()
        currentReason = reason

        let assertionName = "MacBookLidByeBye: \(reason)" as CFString
        logMessage("Attempting \(source) power assertions for \(reason)")

        displaySleepAssertionID = acquireAssertion(
            type: kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            name: assertionName,
            label: "PreventUserIdleDisplaySleep"
        )
        systemSleepAssertionID = acquireAssertion(
            type: kIOPMAssertPreventUserIdleSystemSleep as CFString,
            name: assertionName,
            label: "PreventUserIdleSystemSleep"
        )
        declareUserActivity(name: assertionName)
    }

    private func acquireAssertion(type: CFString, name: CFString, label: String) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), name, &assertionID)

        if result == kIOReturnSuccess {
            logMessage("Acquired \(label) assertion id \(assertionID)")
            return assertionID
        }

        logMessage("Failed to acquire \(label) assertion: 0x\(String(result, radix: 16))")
        return nil
    }

    private func releaseAssertion(_ assertionID: inout IOPMAssertionID?, label: String) {
        guard let currentAssertionID = assertionID else { return }

        let result = IOPMAssertionRelease(currentAssertionID)
        if result == kIOReturnSuccess {
            logMessage("Released \(label) assertion id \(currentAssertionID)")
        } else {
            logMessage("Failed to release \(label) assertion id \(currentAssertionID): 0x\(String(result, radix: 16))")
        }

        assertionID = nil
    }

    private func declareUserActivity(name: CFString) {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity(name, kIOPMUserActiveLocal, &assertionID)

        if result == kIOReturnSuccess {
            userActivityAssertionID = assertionID
            logMessage("Declared user activity assertion id \(assertionID)")
        } else {
            logMessage("Failed to declare user activity: 0x\(String(result, radix: 16))")
        }
    }
}

final class ClamshellSleepController {
    private var overrideActive = false

    var isActive: Bool {
        overrideActive
    }

    func repairStateOnLaunch() {
        logMessage("Resetting clamshell sleep override on launch")
        _ = setOverrideEnabled(false, reason: "launch repair", shouldUpdateState: false)
    }

    func beginOverride(reason: String) {
        guard !overrideActive else {
            logMessage("Clamshell sleep override already active for \(reason)")
            return
        }

        if setOverrideEnabled(true, reason: reason, shouldUpdateState: true) {
            overrideActive = true
        }
    }

    func endOverride(reason: String) {
        guard overrideActive else { return }

        if setOverrideEnabled(false, reason: reason, shouldUpdateState: true) {
            overrideActive = false
        }
    }

    private func setOverrideEnabled(_ enabled: Bool, reason: String, shouldUpdateState: Bool) -> Bool {
        let action = enabled ? "enable" : "disable"
        logMessage("Attempting to \(action) clamshell sleep override for \(reason)")

        let pmRootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard pmRootDomain != IO_OBJECT_NULL else {
            logMessage("Failed to find IOPMrootDomain")
            return false
        }
        defer { IOObjectRelease(pmRootDomain) }

        var connection = io_connect_t()
        let openResult = IOServiceOpen(pmRootDomain, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else {
            logMessage("IOServiceOpen for IOPMrootDomain failed: 0x\(String(openResult, radix: 16))")
            return false
        }
        defer { IOServiceClose(connection) }

        var input: [UInt64] = [enabled ? 1 : 0]
        var outputCount: UInt32 = 0
        let result = IOConnectCallScalarMethod(
            connection,
            UInt32(kPMSetClamshellSleepState),
            &input,
            UInt32(input.count),
            nil,
            &outputCount
        )

        if result == kIOReturnSuccess {
            logMessage("\(enabled ? "Enabled" : "Disabled") clamshell sleep override")
            return true
        }

        if shouldUpdateState {
            logMessage("Failed to \(action) clamshell sleep override: 0x\(String(result, radix: 16))")
        } else {
            logMessage("Launch repair could not reset clamshell sleep override: 0x\(String(result, radix: 16))")
        }
        return false
    }
}

enum PlaybackOrigin {
    case preview
    case lidTrigger
}

final class SleepSoundPlayer: NSObject, AVAudioPlayerDelegate, NSSoundDelegate {
    private let assertionController = PlaybackPowerAssertionController()
    private let clamshellSleepController = ClamshellSleepController()
    private var preparedAudioPlayer: AVAudioPlayer?
    private var activeSystemSound: NSSound?
    private var preparedSelectionDescription: String?
    private var watchdogWorkItem: DispatchWorkItem?
    private var closeProtectionWorkItem: DispatchWorkItem?
    private var closeProtectionActive = false
    private(set) var isPlaying = false

    func repairStateOnLaunch() {
        clamshellSleepController.repairStateOnLaunch()
    }

    func shutdown() {
        finishPlayback(reason: "application shutdown", shouldLog: false)
        clamshellSleepController.endOverride(reason: "application shutdown")
    }

    func prepare(selection: AudioSelection) {
        finishPlayback(reason: "preparing audio", shouldLog: false)
        preparedSelectionDescription = selection.displayName
        preparedAudioPlayer?.stop()
        preparedAudioPlayer = nil
        activeSystemSound?.stop()
        activeSystemSound = nil

        switch selection {
        case .custom(let url), .bundled(let url):
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.prepareToPlay()
                preparedAudioPlayer = player
                logMessage("Prepared audio for \(selection.displayName)")
            } catch {
                logMessage("Failed to prepare \(selection.displayName): \(error.localizedDescription)")
            }
        case .systemSound(let name):
            logMessage("Using system sound \(name)")
        }
    }

    var hasCloseProtection: Bool {
        closeProtectionActive
    }

    func beginCloseProtection(for selection: AudioSelection, triggerReason: String) {
        guard !isPlaying else { return }

        if preparedSelectionDescription != selection.displayName {
            prepare(selection: selection)
        }

        closeProtectionWorkItem?.cancel()

        if !closeProtectionActive {
            logMessage("Starting early close protection for \(selection.displayName) because \(triggerReason)")
            assertionController.beginForCloseGesture(reason: selection.displayName)
            clamshellSleepController.beginOverride(reason: selection.displayName)
            closeProtectionActive = true
        } else {
            logMessage("Refreshing early close protection for \(selection.displayName)")
        }

        let timeout = 2.0
        let workItem = DispatchWorkItem { [weak self] in
            self?.endCloseProtection(reason: "close protection timed out")
        }
        closeProtectionWorkItem = workItem
        logMessage("Scheduled close protection timeout for \(selection.displayName) at \(String(format: "%.2f", timeout))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    func endCloseProtection(reason: String) {
        closeProtectionWorkItem?.cancel()
        closeProtectionWorkItem = nil

        guard closeProtectionActive, !isPlaying else { return }

        closeProtectionActive = false
        assertionController.endPlaybackHold()
        clamshellSleepController.endOverride(reason: reason)
        logMessage("Ended early close protection: \(reason)")
    }

    func play(selection: AudioSelection, origin: PlaybackOrigin) {
        guard !isPlaying else {
            logMessage("Ignoring playback request for \(selection.displayName) because audio is already playing")
            return
        }

        finishPlayback(reason: "starting new playback", shouldLog: false)

        if preparedSelectionDescription != selection.displayName {
            prepare(selection: selection)
        }

        switch selection {
        case .custom, .bundled:
            guard let player = preparedAudioPlayer else {
                logMessage("No prepared audio player for \(selection.displayName)")
                return
            }

            if origin == .lidTrigger {
                closeProtectionWorkItem?.cancel()
                closeProtectionWorkItem = nil
                closeProtectionActive = false
                clamshellSleepController.beginOverride(reason: selection.displayName)
            }
            assertionController.beginForPlayback(reason: selection.displayName)
            scheduleWatchdog(for: player.duration, selection: selection)
            player.currentTime = 0
            isPlaying = true
            logMessage("Starting playback for \(selection.displayName)")
            if !player.play() {
                logMessage("Playback failed to start for \(selection.displayName)")
                finishPlayback(reason: "playback failed to start")
            }
        case .systemSound(let name):
            guard let sound = NSSound(named: .init(name)) else {
                logMessage("System sound \(name) is unavailable")
                return
            }

            if origin == .lidTrigger {
                closeProtectionWorkItem?.cancel()
                closeProtectionWorkItem = nil
                closeProtectionActive = false
                clamshellSleepController.beginOverride(reason: selection.displayName)
            }
            assertionController.beginForPlayback(reason: selection.displayName)
            scheduleWatchdog(for: sound.duration, selection: selection)
            activeSystemSound = sound
            sound.delegate = self
            isPlaying = true
            logMessage("Starting playback for \(selection.displayName)")
            if !sound.play() {
                logMessage("Playback failed to start for \(selection.displayName)")
                finishPlayback(reason: "playback failed to start")
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logMessage("Playback finished with success=\(flag)")
        finishPlayback(reason: "playback finished")
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        logMessage("Decode error: \(error?.localizedDescription ?? "unknown")")
        finishPlayback(reason: "decode error")
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        logMessage("Playback finished with success=\(flag)")
        finishPlayback(reason: "playback finished")
    }

    private func scheduleWatchdog(for duration: TimeInterval, selection: AudioSelection) {
        watchdogWorkItem?.cancel()

        let timeout = max(duration, 0.25) + 0.35
        let workItem = DispatchWorkItem { [weak self] in
            logMessage("Playback watchdog timed out for \(selection.displayName) after \(String(format: "%.2f", timeout))s")
            self?.finishPlayback(reason: "watchdog timeout")
        }

        watchdogWorkItem = workItem
        logMessage("Scheduled playback watchdog for \(selection.displayName) at \(String(format: "%.2f", timeout))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func finishPlayback(reason: String, shouldLog: Bool = true) {
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
        closeProtectionWorkItem?.cancel()
        closeProtectionWorkItem = nil

        isPlaying = false
        closeProtectionActive = false
        preparedAudioPlayer?.stop()
        activeSystemSound?.delegate = nil
        activeSystemSound?.stop()
        activeSystemSound = nil
        assertionController.endPlaybackHold()
        clamshellSleepController.endOverride(reason: reason)

        if shouldLog {
            logMessage("Playback cleanup completed: \(reason)")
        }
    }
}

enum LidReading: Equatable {
    case angle(Double)
    case open
    case closed
    case unknown

    var debugDescription: String {
        switch self {
        case .angle(let angle):
            return String(format: "angle %.1f", angle)
        case .open:
            return "open"
        case .closed:
            return "closed"
        case .unknown:
            return "unknown"
        }
    }
}

final class LidAngleSensor {
    private let vendorID = 0x05AC
    private let productID = 0x8104
    private let usagePage = 0x0020
    private let usage = 0x008A
    private let reportID: CFIndex = 1
    private let reportBufferSize = 8

    private var hidDevice: IOHIDDevice?

    var isAvailable: Bool {
        hidDevice != nil
    }

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

final class LidMonitor {
    private let player: SleepSoundPlayer
    private let selectionProvider: () -> AudioSelection
    private let sensor = LidAngleSensor()
    private let triggerThreshold: Double
    private let resetThreshold: Double
    private let preTriggerProtectionAngleThreshold: Double
    private let preTriggerProtectionVelocityThreshold: Double
    private let fastCloseVelocityThreshold: Double
    private let fastCloseAngleThreshold: Double
    private let pollInterval: TimeInterval

    private var timer: Timer?
    private var armed = true
    private var lastReadingDescription = ""
    private var lastAngle: Double?
    private var lastAngleTimestamp: Date?
    private var capabilityLogged = false
    private var lastDelta: Double?

    init(
        player: SleepSoundPlayer,
        selectionProvider: @escaping () -> AudioSelection,
        triggerThreshold: Double = 18.0,
        resetThreshold: Double = 28.0,
        preTriggerProtectionAngleThreshold: Double = 55.0,
        preTriggerProtectionVelocityThreshold: Double = 25.0,
        fastCloseVelocityThreshold: Double = 220.0,
        fastCloseAngleThreshold: Double = 40.0,
        pollInterval: TimeInterval = 0.05
    ) {
        self.player = player
        self.selectionProvider = selectionProvider
        self.triggerThreshold = triggerThreshold
        self.resetThreshold = resetThreshold
        self.preTriggerProtectionAngleThreshold = preTriggerProtectionAngleThreshold
        self.preTriggerProtectionVelocityThreshold = preTriggerProtectionVelocityThreshold
        self.fastCloseVelocityThreshold = fastCloseVelocityThreshold
        self.fastCloseAngleThreshold = fastCloseAngleThreshold
        self.pollInterval = pollInterval
    }

    func start() {
        guard timer == nil else { return }

        sensor.start()
        logMessage(
            String(
                format: "Starting lid monitor (poll every %.2fs, protect below %.1f degrees at %.1f deg/s, trigger at %.1f degrees, re-arm at %.1f degrees, fast-close at %.1f deg/s below %.1f degrees)",
                pollInterval,
                preTriggerProtectionAngleThreshold,
                preTriggerProtectionVelocityThreshold,
                triggerThreshold,
                resetThreshold,
                fastCloseVelocityThreshold,
                fastCloseAngleThreshold
            )
        )
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer?.tolerance = 0.01
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sensor.stop()
    }

    private func poll() {
        let reading: LidReading
        if let angle = sensor.lidAngle() {
            reading = .angle(angle)
        } else {
            reading = .unknown
        }
        let readingDescription = reading.debugDescription

        if readingDescription != lastReadingDescription {
            logMessage("Observed lid state: \(readingDescription)")
            lastReadingDescription = readingDescription
        }

        switch reading {
        case .angle(let angle):
            logCapabilityIfNeeded("Using HID lid angle telemetry")
            let evaluation = evaluateTrigger(for: angle)
            if let protectionReason = evaluation.protectionReason {
                let selection = selectionProvider()
                player.beginCloseProtection(for: selection, triggerReason: protectionReason)
            } else if !player.isPlaying,
                      player.hasCloseProtection,
                      angle >= resetThreshold,
                      (lastDelta ?? 0) > 0 {
                player.endCloseProtection(reason: String(format: "lid reopened to %.1f degrees", angle))
            }
            if armed, let triggerReason = evaluation.triggerReason {
                armed = false
                triggerPlayback(reason: triggerReason)
            } else if !armed, angle >= resetThreshold, (lastDelta ?? 0) > 0 {
                armed = true
                logMessage(String(format: "Re-armed at lid angle %.1f", angle))
            }
        case .unknown:
            logCapabilityIfNeeded("No HID lid telemetry found")
            break
        case .open, .closed:
            break
        }
    }

    private func triggerPlayback(reason: String) {
        let selection = selectionProvider()
        guard !player.isPlaying else {
            logMessage("Skipping trigger for \(selection.displayName) because playback is already active")
            return
        }
        logMessage("Triggering \(selection.displayName) because \(reason)")
        player.play(selection: selection, origin: .lidTrigger)
    }

    private struct TriggerEvaluation {
        let triggerReason: String?
        let protectionReason: String?
    }

    private func evaluateTrigger(for angle: Double) -> TriggerEvaluation {
        let now = Date()
        var triggerReason: String?
        var protectionReason: String?

        if let previousAngle = lastAngle, let previousTimestamp = lastAngleTimestamp {
            let delta = angle - previousAngle
            let elapsed = now.timeIntervalSince(previousTimestamp)
            lastDelta = delta

            if elapsed > 0, abs(delta) >= 1.0 {
                let velocity = delta / elapsed
                logMessage(
                    String(
                        format: "Angle %.1f degrees (delta %.1f over %.3fs, %.1f deg/s)",
                        angle,
                        delta,
                        elapsed,
                        velocity
                    )
                )

                if delta < 0,
                   angle <= preTriggerProtectionAngleThreshold,
                   abs(velocity) >= preTriggerProtectionVelocityThreshold,
                   armed,
                   !player.hasCloseProtection,
                   !player.isPlaying {
                    protectionReason = String(
                        format: "downward close at %.1f degrees (%.1f deg/s)",
                        angle,
                        abs(velocity)
                    )
                }

                if previousAngle > triggerThreshold, angle <= triggerThreshold, delta < 0 {
                    triggerReason = String(format: "lid angle %.1f", angle)
                } else if delta < 0,
                          angle <= fastCloseAngleThreshold,
                          abs(velocity) >= fastCloseVelocityThreshold {
                    triggerReason = String(
                        format: "fast close at %.1f degrees (%.1f deg/s)",
                        angle,
                        abs(velocity)
                    )
                }
            }
        } else {
            logMessage(String(format: "Angle %.1f degrees", angle))
            lastDelta = nil
        }

        lastAngle = angle
        lastAngleTimestamp = now
        return TriggerEvaluation(triggerReason: triggerReason, protectionReason: protectionReason)
    }

    private func logCapabilityIfNeeded(_ message: String) {
        guard !capabilityLogged else { return }
        capabilityLogged = true
        logMessage(message)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let audioLibrary = AudioLibrary()
    private let player = SleepSoundPlayer()
    private lazy var lidMonitor = LidMonitor(
        player: player,
        selectionProvider: { [weak self] in
            self?.audioLibrary.currentSelection() ?? .systemSound("Hero")
        }
    )

    private var statusItem: NSStatusItem?
    private let soundItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logMessage("Application did finish launching")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "hand.wave.fill", accessibilityDescription: "Bye-bye")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Bye-bye"
        }

        soundItem.isEnabled = false

        let menu = NSMenu()
        menu.addItem(soundItem)
        menu.addItem(NSMenuItem.separator())

        let chooseAudioItem = NSMenuItem(title: "Choose Audio…", action: #selector(chooseAudio), keyEquivalent: "")
        chooseAudioItem.target = self
        menu.addItem(chooseAudioItem)

        let previewItem = NSMenuItem(title: "Play Preview", action: #selector(playPreview), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)

        let defaultItem = NSMenuItem(title: "Use Bundled Mario", action: #selector(useBundledMario), keyEquivalent: "")
        defaultItem.target = self
        menu.addItem(defaultItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        refreshSoundItem()
        player.repairStateOnLaunch()
        player.prepare(selection: audioLibrary.currentSelection())
        lidMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lidMonitor.stop()
        player.shutdown()
    }

    @objc private func chooseAudio() {
        let panel = NSOpenPanel()
        panel.title = "Choose an audio file"
        panel.message = "This clip will play when the lid gets near closed."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            logMessage("Choose audio canceled")
            return
        }

        do {
            let selection = try audioLibrary.importAudioFile(from: sourceURL)
            logMessage("Imported custom audio \(selection.displayName)")
            player.prepare(selection: selection)
            refreshSoundItem()
        } catch {
            logMessage("Failed to import custom audio: \(error.localizedDescription)")
        }
    }

    @objc private func playPreview() {
        let selection = audioLibrary.currentSelection()
        logMessage("Preview requested for \(selection.displayName)")
        player.play(selection: selection, origin: .preview)
    }

    @objc private func useBundledMario() {
        do {
            try audioLibrary.resetToBundledDefault()
            let selection = audioLibrary.currentSelection()
            logMessage("Reverted to bundled audio \(selection.displayName)")
            player.prepare(selection: selection)
            refreshSoundItem()
        } catch {
            logMessage("Failed to reset audio: \(error.localizedDescription)")
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshSoundItem() {
        let selection = audioLibrary.currentSelection()
        soundItem.title = "Sound: \(selection.displayName)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
