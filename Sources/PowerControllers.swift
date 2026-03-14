import Foundation
import IOKit.pwr_mgt

final class PlaybackPowerAssertionController {
    private var displaySleepAssertionID: IOPMAssertionID?
    private var systemSleepAssertionID: IOPMAssertionID?
    private var userActivityAssertionID: IOPMAssertionID?
    private var currentReason: String?

    func beginForPlayback(reason: String) {
        beginHold(reason: reason)
    }

    func beginForCloseGesture(reason: String) {
        beginHold(reason: reason)
    }

    func endHold() {
        currentReason = nil
        releaseAssertion(&displaySleepAssertionID)
        releaseAssertion(&systemSleepAssertionID)
        releaseAssertion(&userActivityAssertionID)
    }

    private func beginHold(reason: String) {
        if currentReason == reason,
           displaySleepAssertionID != nil || systemSleepAssertionID != nil || userActivityAssertionID != nil {
            return
        }

        endHold()
        currentReason = reason

        let assertionName = "Mac Lid Lullaby: \(reason)" as CFString
        displaySleepAssertionID = acquireAssertion(
            type: kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            name: assertionName
        )
        systemSleepAssertionID = acquireAssertion(
            type: kIOPMAssertPreventUserIdleSystemSleep as CFString,
            name: assertionName
        )
        declareUserActivity(name: assertionName)
    }

    private func acquireAssertion(type: CFString, name: CFString) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), name, &assertionID)
        return result == kIOReturnSuccess ? assertionID : nil
    }

    private func releaseAssertion(_ assertionID: inout IOPMAssertionID?) {
        guard let currentAssertionID = assertionID else { return }
        _ = IOPMAssertionRelease(currentAssertionID)
        assertionID = nil
    }

    private func declareUserActivity(name: CFString) {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity(name, kIOPMUserActiveLocal, &assertionID)
        userActivityAssertionID = result == kIOReturnSuccess ? assertionID : nil
    }
}

final class ClamshellSleepController {
    private var overrideActive = false

    func repairStateOnLaunch() {
        _ = setOverrideEnabled(false)
    }

    func beginOverride() {
        guard !overrideActive else { return }

        if setOverrideEnabled(true) {
            overrideActive = true
        }
    }

    func endOverride() {
        guard overrideActive else { return }

        if setOverrideEnabled(false) {
            overrideActive = false
        }
    }

    private func setOverrideEnabled(_ enabled: Bool) -> Bool {
        let pmRootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard pmRootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(pmRootDomain) }

        var connection = io_connect_t()
        let openResult = IOServiceOpen(pmRootDomain, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else { return false }
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

        return result == kIOReturnSuccess
    }
}
