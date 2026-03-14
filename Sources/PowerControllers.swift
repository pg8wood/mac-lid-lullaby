import Foundation
import IOKit.pwr_mgt

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

    func endHold() {
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

        endHold()
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
