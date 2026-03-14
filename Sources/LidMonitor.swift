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
    private var lastAngle: Double?
    private var lastAngleTimestamp: Date?
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
    }

    private func poll() {
        guard let angle = sensor.lidAngle() else { return }

        if awaitingWakeReset, angle >= wakeResetThreshold, (lastDelta ?? 0) >= 0 {
            awaitingWakeReset = false
            armed = true
            lastAngle = angle
            lastAngleTimestamp = Date()
            lastDelta = nil
        }

        let evaluation = evaluateTrigger(for: angle)
        if evaluation.shouldStartProtection {
            player.beginCloseProtection(for: selectionProvider())
        } else if !player.isPlaying,
                  player.hasCloseProtection,
                  angle >= resetThreshold,
                  (lastDelta ?? 0) > 0 {
            player.endCloseProtection()
        }

        if armed, evaluation.shouldTrigger {
            armed = false
            triggerPlayback()
        } else if !awaitingWakeReset, !armed, angle >= resetThreshold, (lastDelta ?? 0) > 0 {
            armed = true
        }
    }

    private func triggerPlayback() {
        let selection = selectionProvider()
        guard !player.isPlaying else { return }
        player.play(selection: selection, origin: .lidTrigger)
    }

    private func evaluateTrigger(for angle: Double) -> TriggerEvaluation {
        let now = Date()
        var shouldTrigger = false
        var shouldStartProtection = false

        if let previousAngle = lastAngle, let previousTimestamp = lastAngleTimestamp {
            let delta = angle - previousAngle
            let elapsed = now.timeIntervalSince(previousTimestamp)
            lastDelta = delta

            if elapsed > 0, abs(delta) >= 1.0 {
                let velocity = delta / elapsed

                if delta < 0,
                   angle <= preTriggerProtectionAngleThreshold,
                   abs(velocity) >= preTriggerProtectionVelocityThreshold,
                   armed,
                   !awaitingWakeReset,
                   !player.hasCloseProtection,
                   !player.isPlaying {
                    shouldStartProtection = true
                }

                if !awaitingWakeReset,
                   previousAngle > triggerThreshold,
                   angle <= triggerThreshold,
                   delta < 0 {
                    shouldTrigger = true
                } else if !awaitingWakeReset,
                          delta < 0,
                          angle <= fastCloseAngleThreshold,
                          abs(velocity) >= fastCloseVelocityThreshold {
                    shouldTrigger = true
                }
            }
        } else {
            lastDelta = nil
        }

        lastAngle = angle
        lastAngleTimestamp = now
        return TriggerEvaluation(
            shouldTrigger: shouldTrigger,
            shouldStartProtection: shouldStartProtection
        )
    }
}

private struct TriggerEvaluation {
    let shouldTrigger: Bool
    let shouldStartProtection: Bool
}
