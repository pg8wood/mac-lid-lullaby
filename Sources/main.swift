import AppKit
import AVFoundation
import Foundation

final class LidMonitor {
    private let triggerThreshold: Double
    private let resetThreshold: Double
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var armed = true
    private var lastAngle: Double?
    private let speaker = ByeByeSpeaker()

    init(triggerThreshold: Double = 4.0, resetThreshold: Double = 12.0, pollInterval: TimeInterval = 0.4) {
        self.triggerThreshold = triggerThreshold
        self.resetThreshold = resetThreshold
        self.pollInterval = pollInterval
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer?.tolerance = 0.1
        poll()
    }

    private func poll() {
        let reading = LidAngleReader.reading()

        switch reading {
        case .angle(let angle):
            lastAngle = angle
            if armed, angle <= triggerThreshold {
                armed = false
                speaker.playByeBye()
            } else if !armed, angle >= resetThreshold {
                armed = true
            }
        case .closed:
            if armed {
                armed = false
                speaker.playByeBye()
            }
        case .unknown:
            break
        }
    }

    func debugText() -> String {
        if let lastAngle {
            return String(format: "Lid: %.1f°", lastAngle)
        }
        return "Lid: unknown"
    }
}

enum LidReading {
    case angle(Double)
    case closed
    case unknown
}

enum LidAngleReader {
    static func reading() -> LidReading {
        if let output = run(cmd: "/usr/sbin/ioreg", args: ["-r", "-l", "-w0"]),
           let angle = parseDouble(from: output, key: "LidAngle") {
            return .angle(angle)
        }

        if let output = run(cmd: "/usr/sbin/ioreg", args: ["-r", "-k", "AppleClamshellState", "-d", "1", "-w0"]),
           let clamshell = parseBool(from: output, key: "AppleClamshellState") {
            return clamshell ? .closed : .unknown
        }

        return .unknown
    }

    private static func parseDouble(from text: String, key: String) -> Double? {
        let pattern = "\\\"\(NSRegularExpression.escapedPattern(for: key))\\\"\\s*=\\s*([0-9]+(?:\\\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[valueRange])
    }

    private static func parseBool(from text: String, key: String) -> Bool? {
        let pattern = "\\\"\(NSRegularExpression.escapedPattern(for: key))\\\"\\s*=\\s*(Yes|No|true|false|1|0)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        switch text[valueRange].lowercased() {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }

    private static func run(cmd: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

final class ByeByeSpeaker: NSObject, NSSpeechSynthesizerDelegate {
    private var player: AVAudioPlayer?
    private lazy var synth: NSSpeechSynthesizer = {
        let s = NSSpeechSynthesizer()
        s.delegate = self
        return s
    }()

    func playByeBye() {
        if let clipURL = bundledClipURL(),
           let audioPlayer = try? AVAudioPlayer(contentsOf: clipURL) {
            player = audioPlayer
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            return
        }

        synth.startSpeaking("Bye-bye!")
    }

    private func bundledClipURL() -> URL? {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [
            execDir.appendingPathComponent("mario-bye-bye.wav"),
            execDir.appendingPathComponent("../Resources/mario-bye-bye.wav").standardizedFileURL
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = LidMonitor()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "👋 Lid"

        let menu = NSMenu()
        let stateItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            stateItem.title = self?.monitor.debugText() ?? "Lid: unknown"
        }

        monitor.start()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
