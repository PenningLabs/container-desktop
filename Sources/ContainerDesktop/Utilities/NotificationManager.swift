import AppKit
import Foundation
import os
import UserNotifications

/// Manages macOS notifications for container lifecycle events.
/// Sends notifications when containers stop unexpectedly, builds complete, etc.
final class NotificationManager: NSObject, Sendable {

    static let shared = NotificationManager()

    override init() {
        super.init()
        // UNUserNotificationCenter crashes if there's no app bundle
        // (e.g., during `swift test` or when run as a raw SPM executable).
        // Only request permission when running inside a proper .app bundle.
        if Bundle.main.bundleIdentifier != nil {
            requestPermission()
        } else {
            notificationsDisabled.withLock { $0 = true }
        }
    }

    /// Tracks whether notification permission is known-unavailable.
    /// Set when `requestPermission` fails, used to silence per-notification warnings.
    private let notificationsDisabled = OSAllocatedUnfairLock(initialState: false)

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { [weak self] granted, error in
            // UNErrorDomain Code=1 is expected when running as an SPM executable
            // from Xcode (no app bundle). Notifications work when running as a
            // proper .app bundle built with build-app.sh.
            if let error = error {
                self?.notificationsDisabled.withLock { $0 = true }
                AppEventLog.shared.info(
                    "Notifications unavailable: \(error.localizedDescription). This is normal when running from Xcode.",
                    source: "Notifications"
                )
            } else if !granted {
                self?.notificationsDisabled.withLock { $0 = true }
            }
        }
    }

    func notifyContainerStopped(name: String) {
        send(
            title: "Container stopped",
            body: "'\(name)' has stopped running.",
            identifier: "container-stopped-\(name)"
        )
    }

    func notifyContainerStarted(name: String) {
        send(
            title: "Container started",
            body: "'\(name)' is now running.",
            identifier: "container-started-\(name)"
        )
    }

    func notifyBuildComplete(tag: String, success: Bool) {
        if success {
            send(
                title: "Build succeeded",
                body: "Image '\(tag)' built successfully.",
                identifier: "build-complete-\(tag)"
            )
        } else {
            send(
                title: "Build failed",
                body: "Image '\(tag)' failed to build.",
                identifier: "build-failed-\(tag)"
            )
        }
    }

    func notifyPullComplete(reference: String) {
        send(
            title: "Image pulled",
            body: "'\(reference)' is ready to use.",
            identifier: "pull-complete-\(reference)"
        )
    }

    func notifySystemStopped() {
        send(
            title: "Container system stopped",
            body: "The container system service has stopped.",
            identifier: "system-stopped"
        )
    }

    /// Send a notification with an auto-generated identifier.
    func send(title: String, body: String) {
        send(title: title, body: body, identifier: UUID().uuidString)
    }

    private func send(title: String, body: String, identifier: String) {
        // If we already know notifications are unavailable (e.g., running as SPM
        // executable from Xcode), skip posting to avoid log spam.
        if notificationsDisabled.withLock({ $0 }) {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                // First failure: mark disabled and log at info level.
                // Subsequent failures are silent.
                let wasAlreadyDisabled = self?.notificationsDisabled.withLock { state -> Bool in
                    let was = state
                    state = true
                    return was
                } ?? false

                if !wasAlreadyDisabled {
                    AppEventLog.shared.info(
                        "Notification delivery disabled: \(error.localizedDescription)",
                        source: "Notifications"
                    )
                }
            }
        }
    }
}

// Also log permission denial
extension NotificationManager {
    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
                AppEventLog.shared.warning(
                    "Notification permission denied. Enable in System Settings → Notifications.",
                    source: "Notifications"
                )
            }
        }
    }
}
