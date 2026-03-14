import Foundation
import OSLog

private let logger = Logger(subsystem: "MacBookLidByeBye", category: "App")
private let launchTime = Date()

func logMessage(_ message: String) {
    let elapsed = String(format: "%.3f", Date().timeIntervalSince(launchTime))
    let formatted = "t+\(elapsed)s \(message)"
    logger.log("\(formatted, privacy: .public)")
    print("[Bye-bye] \(formatted)")
}
