import Foundation

enum AudioSelection {
    case custom(URL)
    case bundled(URL)

    var url: URL {
        switch self {
        case .custom(let url), .bundled(let url):
            return url
        }
    }

    var displayName: String {
        url.lastPathComponent
    }
}

final class AudioLibrary {
    private let defaults = UserDefaults.standard
    private let customAudioFilenameKey = "customAudioFilename"
    private let appSupportDirectoryName = "Mac Lid Lullaby"

    func currentSelection() -> AudioSelection {
        if let url = customAudioURL() {
            return .custom(url)
        }

        guard let bundledURL = Bundle.module.url(forResource: "sm64ds-bye", withExtension: "wav") else {
            preconditionFailure("Missing bundled audio resource sm64ds-bye.wav")
        }

        return .bundled(bundledURL)
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
        let directory = baseDirectory.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
