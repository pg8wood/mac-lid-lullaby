import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let audioLibrary = AudioLibrary()
    private let player = SleepSoundPlayer()
    private lazy var lidMonitor = LidMonitor(
        player: player,
        selectionProvider: { [audioLibrary] in
            audioLibrary.currentSelection()
        }
    )

    private var statusItem: NSStatusItem?
    private let soundItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

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
        player.prepare(selection: currentSelection())
        lidMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        lidMonitor.stop()
        player.shutdown()
    }

    @objc private func handleWakeNotification() {
        player.resetAfterWake()
        lidMonitor.handleWake()
    }

    @objc private func chooseAudio() {
        let panel = NSOpenPanel()
        panel.title = "Choose an audio file"
        panel.message = "This clip will play when the lid gets near closed."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            let selection = try audioLibrary.importAudioFile(from: sourceURL)
            player.prepare(selection: selection)
            refreshSoundItem()
        } catch {}
    }

    @objc private func playPreview() {
        player.play(selection: currentSelection(), origin: .preview)
    }

    @objc private func useBundledMario() {
        do {
            try audioLibrary.resetToBundledDefault()
            let selection = currentSelection()
            player.prepare(selection: selection)
            refreshSoundItem()
        } catch {}
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshSoundItem() {
        soundItem.title = "Sound: \(currentSelection().displayName)"
    }

    private func currentSelection() -> AudioSelection {
        audioLibrary.currentSelection()
    }
}
