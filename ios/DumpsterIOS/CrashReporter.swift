import Foundation
import os.log

/// Crash + error reporting abstraction.
///
/// Currently a no-op + os.Logger fallback. To enable Sentry:
/// 1. In Xcode: File → Add Package Dependencies… → enter `https://github.com/getsentry/sentry-cocoa`
/// 2. Add Sentry to the DumpsterIOS target
/// 3. In `start()` below, uncomment the SentrySDK.start block
/// 4. Replace the `your-dsn-here` placeholder with the DSN from your Sentry project
///
/// Once Sentry is wired, every `capture(...)` call here flows to your dashboard
/// without changing call sites scattered through the app.
final class CrashReporter {

    // MARK: - Singleton
    static let shared = CrashReporter()
    private let log = Logger(subsystem: "com.leescott.dumpster.ios", category: "CrashReporter")

    private init() {}

    // MARK: - Lifecycle

    /// Call once on app launch. Safe to call multiple times.
    func start() {
        log.info("CrashReporter started (Sentry disabled)")

        // ─── Sentry wire-up — uncomment when SPM package is added ───
        /*
        import Sentry

        SentrySDK.start { options in
            options.dsn = "https://your-dsn-here@o0.ingest.sentry.io/0"
            options.debug = false
            options.tracesSampleRate = 0.2          // 20% perf sampling
            options.profilesSampleRate = 0.2
            options.attachScreenshot = false        // ⚠️ user photos may be visible
            options.sendDefaultPii = false          // never send IP / email
            options.enableAutoBreadcrumbTracking = true
            options.enableAutoPerformanceTracing = true
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "release"
            #endif
        }
        */
    }

    // MARK: - Capture

    /// Capture a non-fatal error. Add tags to slice in dashboard.
    func capture(_ error: Error, tags: [String: String] = [:], context: String? = nil) {
        if let context {
            log.error("\(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            log.error("\(error.localizedDescription, privacy: .public)")
        }

        // ─── Sentry: SentrySDK.capture(error: error) { scope in scope.setTags(tags) } ───
    }

    /// Capture a free-form message (warning, recoverable issue).
    func captureMessage(_ message: String, level: Severity = .warning, tags: [String: String] = [:]) {
        switch level {
        case .info:    log.info("\(message, privacy: .public)")
        case .warning: log.warning("\(message, privacy: .public)")
        case .error:   log.error("\(message, privacy: .public)")
        case .fatal:   log.fault("\(message, privacy: .public)")
        }

        // ─── Sentry: SentrySDK.capture(message: message) { scope in scope.setLevel(level.sentryLevel); scope.setTags(tags) } ───
    }

    /// Drop a breadcrumb so we know what the user was doing right before a crash/error.
    func breadcrumb(_ message: String, category: String = "ui") {
        log.debug("[\(category, privacy: .public)] \(message, privacy: .public)")

        // ─── Sentry:
        // let crumb = Breadcrumb(level: .info, category: category)
        // crumb.message = message
        // SentrySDK.addBreadcrumb(crumb)
        // ───
    }

    // MARK: - User context (for grouping crashes by user once Sign-in lands)

    func setUser(id: String?) {
        // ─── Sentry:
        // if let id = id {
        //     SentrySDK.setUser(User(userId: id))
        // } else {
        //     SentrySDK.setUser(nil)
        // }
        // ───
    }

    // MARK: - Severity

    enum Severity {
        case info, warning, error, fatal
    }
}
