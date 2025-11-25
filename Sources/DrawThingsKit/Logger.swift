import Foundation
import os.log

/// Logging configuration for DrawThingsKit
public struct DrawThingsKitLogger {
    /// Log levels for DrawThingsKit
    public enum Level: Int, Comparable {
        case debug = 0
        case info = 1
        case notice = 2
        case error = 3
        case fault = 4
        case none = 5

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .notice: return .default
            case .error: return .error
            case .fault: return .fault
            case .none: return .default
            }
        }
    }

    /// Current minimum log level. Messages below this level will not be logged.
    /// Default is .none (no logging) for production use.
    public static var minimumLevel: Level = .none

    /// Whether to use emoji prefixes in log messages
    public static var useEmoji: Bool = true

    private static let logger = os.Logger(subsystem: "com.drawthings.kit", category: "DrawThingsKit")

    /// Log a debug message
    static func debug(_ message: String) {
        log(message, level: .debug, emoji: "🔍")
    }

    /// Log an info message
    static func info(_ message: String) {
        log(message, level: .info, emoji: "ℹ️")
    }

    /// Log a notice message
    static func notice(_ message: String) {
        log(message, level: .notice, emoji: "📢")
    }

    /// Log an error message
    static func error(_ message: String) {
        log(message, level: .error, emoji: "❌")
    }

    /// Log a fault message
    static func fault(_ message: String) {
        log(message, level: .fault, emoji: "🔥")
    }

    /// Internal logging function
    private static func log(_ message: String, level: Level, emoji: String) {
        guard level >= minimumLevel else { return }

        let prefix = useEmoji ? "\(emoji) " : ""
        let formattedMessage = "\(prefix)\(message)"

        logger.log(level: level.osLogType, "\(formattedMessage)")
    }
}
