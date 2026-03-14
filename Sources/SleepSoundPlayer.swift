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
        finishPlayback()
    }

    func resetAfterWake() {
        resetRuntimeState()
    }

    func prepare(selection: AudioSelection) {
        finishPlayback()
        preparedSelectionDescription = selection.displayName
        preparedAudioPlayer?.stop()
        preparedAudioPlayer = nil

        do {
            let player = try AVAudioPlayer(contentsOf: selection.url)
            player.delegate = self
            player.prepareToPlay()
            preparedAudioPlayer = player
        } catch {}
    }

    func beginCloseProtection(for selection: AudioSelection) {
        guard !isPlaying else { return }

        if preparedSelectionDescription != selection.displayName {
            prepare(selection: selection)
        }

        closeProtectionWorkItem?.cancel()

        if !closeProtectionActive {
            assertionController.beginForCloseGesture(reason: selection.displayName)
            clamshellSleepController.beginOverride()
            closeProtectionActive = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.endCloseProtection()
        }
        closeProtectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    func endCloseProtection() {
        cancelCloseProtection()

        guard closeProtectionActive, !isPlaying else { return }

        closeProtectionActive = false
        assertionController.endHold()
        clamshellSleepController.endOverride()
    }

    func play(selection: AudioSelection, origin: PlaybackOrigin) {
        guard !isPlaying else { return }

        finishPlayback()

        if preparedSelectionDescription != selection.displayName {
            prepare(selection: selection)
        }

        guard let player = preparedAudioPlayer else { return }

        if origin == .lidTrigger {
            closeProtectionWorkItem?.cancel()
            closeProtectionWorkItem = nil
            closeProtectionActive = false
            clamshellSleepController.beginOverride()
        }

        assertionController.beginForPlayback(reason: selection.displayName)
        scheduleWatchdog(for: player.duration)
        player.currentTime = 0
        isPlaying = true

        if !player.play() {
            finishPlayback()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        _ = flag
        finishPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        _ = error
        finishPlayback()
    }

    private func scheduleWatchdog(for duration: TimeInterval) {
        cancelWatchdog()

        let timeout = max(duration, 0.25) + 0.35
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishPlayback()
        }

        watchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func finishPlayback() {
        resetRuntimeState()
    }

    private func resetRuntimeState() {
        cancelWatchdog()
        cancelCloseProtection()

        isPlaying = false
        closeProtectionActive = false
        preparedAudioPlayer?.stop()
        assertionController.endHold()
        clamshellSleepController.endOverride()
    }

    private func cancelWatchdog() {
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
    }

    private func cancelCloseProtection() {
        closeProtectionWorkItem?.cancel()
        closeProtectionWorkItem = nil
    }
}
