import AVFoundation
import Foundation

enum PlaybackOrigin {
    case preview
    case lidTrigger
}

final class SleepSoundPlayer: NSObject, AVAudioPlayerDelegate {
    private let assertionController = PlaybackPowerAssertionController()
    private let clamshellSleepController = ClamshellSleepController()
    private var preparedAudioPlayer: AVAudioPlayer?
    private var preparedSelectionDescription: String?
    private var watchdogWorkItem: DispatchWorkItem?
    private var closeProtectionWorkItem: DispatchWorkItem?
    private var closeProtectionActive = false
    private(set) var isPlaying = false

    var hasCloseProtection: Bool {
        closeProtectionActive
    }

    func repairStateOnLaunch() {
        clamshellSleepController.repairStateOnLaunch()
    }

    func shutdown() {
        finishPlayback(reason: "application shutdown", shouldLog: false)
        clamshellSleepController.endOverride(reason: "application shutdown")
    }

    func resetAfterWake() {
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
        closeProtectionWorkItem?.cancel()
        closeProtectionWorkItem = nil

        isPlaying = false
        closeProtectionActive = false
        preparedAudioPlayer?.stop()
        assertionController.endHold()
        clamshellSleepController.endOverride(reason: "wake reset")
        logMessage("Reset playback and sleep override state after wake")
    }

    func prepare(selection: AudioSelection) {
        finishPlayback(reason: "preparing audio", shouldLog: false)
        preparedSelectionDescription = selection.displayName
        preparedAudioPlayer?.stop()
        preparedAudioPlayer = nil

        do {
            let player = try AVAudioPlayer(contentsOf: selection.url)
            player.delegate = self
            player.prepareToPlay()
            preparedAudioPlayer = player
            logMessage("Prepared audio for \(selection.displayName)")
        } catch {
            logMessage("Failed to prepare \(selection.displayName): \(error.localizedDescription)")
        }
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
        assertionController.endHold()
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
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logMessage("Playback finished with success=\(flag)")
        finishPlayback(reason: "playback finished")
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        logMessage("Decode error: \(error?.localizedDescription ?? "unknown")")
        finishPlayback(reason: "decode error")
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
        assertionController.endHold()
        clamshellSleepController.endOverride(reason: reason)

        if shouldLog {
            logMessage("Playback cleanup completed: \(reason)")
        }
    }
}
