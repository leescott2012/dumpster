import Foundation
import os.log
#if canImport(Sentry)
import Sentry
#endif

/// Crash + error reporting. Always logs via os.Logger; also reports to Sentry
/// when the DSN is set. The DSN comes from the `SENTRY_DSN` Info.plist key,
/// which reads the `SENTRY_DSN` build setting. Leave it empty to disable Sentry
/// (set it in the target's build settings or an xcconfig).
final class CrashReporter {

    // MARK: - Singleton
    static let shared = CrashReporter()
    private let log = Logger(subsystem: "com.leescott.dumpster.ios", category: "CrashReporter")
    private var sentryOn = false

    private init() {}

    // MARK: - Lifecycle

    /// Call once on app launch. Safe to call multiple times.
    func start() {
        let dsn = (Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !dsn.isEmpty, !dsn.hasPrefix("$(") else {
            log.info("CrashReporter started (Sentry disabled: SENTRY_DSN empty)")
            return
        }
        #if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.tracesSampleRate = 0.2
            options.attachScreenshot = false        // user photos may be visible
            options.sendDefaultPii = false          // never send IP / email
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "release"
            #endif
        }
        sentryOn = true
        log.info("CrashReporter started (Sentry enabled)")
        #endif
    }

    // MARK: - Capture

    /// Capture a non-fatal error. Add tags to slice in dashboard.
    func capture(_ error: Error, tags: [String: String] = [:], context: String? = nil) {
        if let context {
            log.error("\(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            log.error("\(error.localizedDescription, privacy: .public)")
        }
        #if canImport(Sentry)
        if sentryOn { SentrySDK.capture(error: error) { scope in scope.setTags(tags) } }
        #endif
    }

    /// Capture a free-form message (warning, recoverable issue).
    func captureMessage(_ message: String, level: Severity = .warning, tags: [String: String] = [:]) {
        switch level {
        case .info:    log.info("\(message, privacy: .public)")
        case .warning: log.warning("\(message, privacy: .public)")
        case .error:   log.error("\(message, privacy: .public)")
        case .fatal:   log.fault("\(message, privacy: .public)")
        }
        #if canImport(Sentry)
        if sentryOn {
            SentrySDK.capture(message: message) { scope in
                scope.setLevel(level.sentryLevel)
                scope.setTags(tags)
            }
        }
        #endif
    }

    /// Drop a breadcrumb so we know what the user was doing right before a crash/error.
    func breadcrumb(_ message: String, category: String = "ui") {
        log.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        #if canImport(Sentry)
        if sentryOn {
            let crumb = Breadcrumb(level: .info, category: category)
            crumb.message = message
            SentrySDK.addBreadcrumb(crumb)
        }
        #endif
    }

    // MARK: - User context (for grouping crashes by user)

    func setUser(id: String?) {
        #if canImport(Sentry)
        guard sentryOn else { return }
        SentrySDK.setUser(id.map { User(userId: $0) })
        #endif
    }

    // MARK: - Severity

    enum Severity {
        case info, warning, error, fatal

        #if canImport(Sentry)
        var sentryLevel: SentryLevel {
            switch self {
            case .info: return .info
            case .warning: return .warning
            case .error: return .error
            case .fatal: return .fatal
            }
        }
        #endif
    }
}
