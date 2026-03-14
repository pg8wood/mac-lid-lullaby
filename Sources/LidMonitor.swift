import Foundation

final class LidMonitor {
    private let player: SleepSoundPlayer
    private let selectionProvider: () -> AudioSelection
    private let sensor = LidAngleSensor()
    private let triggerThreshold: Double
    private let resetThreshold: Double
    private let wakeResetThreshold: Double
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
    private var awaitingWakeReset = false

    init(
        player: SleepSoundPlayer,
        selectionProvider: @escaping () -> AudioSelection,
        triggerThreshold: Double = 18.0,
        resetThreshold: Double = 28.0,
        wakeResetThreshold: Double = 60.0,
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
        self.wakeResetThreshold = wakeResetThreshold
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

    func handleWake() {
        awaitingWakeReset = true
        armed = false
        logMessage(String(format: "Observed wake; waiting to reopen past %.1f degrees before re-arming", wakeResetThreshold))
    }

    private func poll() {
        guard let angle = sensor.lidAngle() else {
            logObservedState("unknown")
            logCapabilityIfNeeded("No HID lid telemetry found")
            return
        }

        logObservedState(String(format: "angle %.1f", angle))
        logCapabilityIfNeeded("Using HID lid angle telemetry")

        if awaitingWakeReset, angle >= wakeResetThreshold, (lastDelta ?? 0) >= 0 {
            awaitingWakeReset = false
            armed = true
            lastAngle = angle
            lastAngleTimestamp = Date()
            lastDelta = nil
            logMessage(String(format: "Wake reset cleared at lid angle %.1f", angle))
        }

        let evaluation = evaluateTrigger(for: angle)
        if let protectionReason = evaluation.protectionReason {
            player.beginCloseProtection(for: selectionProvider(), triggerReason: protectionReason)
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
    }

    private func logObservedState(_ description: String) {
        guard description != lastReadingDescription else { return }
        logMessage("Observed lid state: \(description)")
        lastReadingDescription = description
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
                   !awaitingWakeReset,
                   !player.hasCloseProtection,
                   !player.isPlaying {
                    protectionReason = String(
                        format: "downward close at %.1f degrees (%.1f deg/s)",
                        angle,
                        abs(velocity)
                    )
                }

                if !awaitingWakeReset,
                   previousAngle > triggerThreshold,
                   angle <= triggerThreshold,
                   delta < 0 {
                    triggerReason = String(format: "lid angle %.1f", angle)
                } else if !awaitingWakeReset,
                          delta < 0,
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

private struct TriggerEvaluation {
    let triggerReason: String?
    let protectionReason: String?
}
