import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let audioLibrary = AudioLibrary()
    private let launchAtLoginController = LaunchAtLoginController()
    private let player = SleepSoundPlayer()
    private lazy var lidMonitor = LidMonitor(
        player: player,
        selectionProvider: { [audioLibrary] in
            audioLibrary.currentSelection()
        }
    )

    private var statusItem: NSStatusItem?
    private let descriptionItem = NSMenuItem(
        title: "Plays a sound right before your MacBook lid closes.",
        action: nil,
        keyEquivalent: ""
    )
    private let soundItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerObservers()
        setupStatusItem()
        setupMenu()
        launchAtLoginController.configureOnLaunch()
        refreshMenuItems()
        player.repairStateOnLaunch()
        player.prepare(selection: currentSelection())
        lidMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterObservers()
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

    @objc private func toggleLaunchAtLogin() {
        launchAtLoginController.toggle()
        refreshLaunchAtLoginItem()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func registerObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func unregisterObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        let image = NSImage(named: "status-bar-icon")!
        image.size = NSSize(width: 22, height: 15)
        button.image = image
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Mac Lid Lullaby"
    }

    private func setupMenu() {
        descriptionItem.isEnabled = false
        soundItem.isEnabled = false
        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(descriptionItem)
        menu.addItem(soundItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Choose Audio…", action: #selector(chooseAudio)))
        menu.addItem(makeMenuItem(title: "Play Preview", action: #selector(playPreview)))
        menu.addItem(makeMenuItem(title: "Use Default Sound", action: #selector(useBundledMario)))
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshSoundItem() {
        soundItem.title = "Sound: \(currentSelection().displayName)"
    }

    private func refreshLaunchAtLoginItem() {
        launchAtLoginItem.state = launchAtLoginController.menuState
        launchAtLoginItem.isEnabled = launchAtLoginController.canManage
    }

    private func refreshMenuItems() {
        refreshSoundItem()
        refreshLaunchAtLoginItem()
    }

    private func currentSelection() -> AudioSelection {
        audioLibrary.currentSelection()
    }

    func menuWillOpen(_ menu: NSMenu) {
        _ = menu
        refreshMenuItems()
    }
}
