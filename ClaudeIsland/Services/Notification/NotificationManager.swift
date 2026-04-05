//
//  NotificationManager.swift
//  ClaudeIsland
//
//  macOS native notification support via UNUserNotificationCenter.
//  Sends system notifications for permission requests, task completion,
//  and Claude questions when the app is not focused.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private var isAuthorized = false

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task { @MainActor [weak self] in
                self?.isAuthorized = granted
                if let error {
                    print("[NotificationManager] Authorization error: \(error)")
                }
            }
        }
    }

    // MARK: - Send Notifications

    /// Notify user that a tool is waiting for permission approval
    func sendPermissionNotification(sessionId: String, toolName: String, projectName: String?) {
        guard isAuthorized, AppSettings.enableSystemNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Permission Request")
        content.body = String(localized: "\(toolName) needs approval in \(projectName ?? "session")")
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"
        content.userInfo = ["sessionId": sessionId, "type": "permission"]

        let request = UNNotificationRequest(
            identifier: "permission-\(sessionId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    /// Notify user that a session has finished and is waiting for input
    func sendTaskCompleteNotification(sessionId: String, projectName: String?) {
        guard isAuthorized, AppSettings.enableSystemNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Task Complete")
        content.body = String(localized: "Claude is ready for input in \(projectName ?? "session")")
        content.sound = .default
        content.categoryIdentifier = "TASK_COMPLETE"
        content.userInfo = ["sessionId": sessionId, "type": "taskComplete"]

        let request = UNNotificationRequest(
            identifier: "complete-\(sessionId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    /// Notify user that Claude is asking a question
    func sendQuestionNotification(sessionId: String, question: String?, projectName: String?) {
        guard isAuthorized, AppSettings.enableSystemNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Claude's Question")
        content.body = question ?? String(localized: "Claude is waiting for an answer")
        content.sound = .default
        content.categoryIdentifier = "QUESTION"
        content.userInfo = ["sessionId": sessionId, "type": "question"]

        let request = UNNotificationRequest(
            identifier: "question-\(sessionId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    /// Remove all pending notifications for a session
    func clearNotifications(for sessionId: String) {
        center.getDeliveredNotifications { notifications in
            let idsToRemove = notifications
                .filter { ($0.request.content.userInfo["sessionId"] as? String) == sessionId }
                .map { $0.request.identifier }
            Task { @MainActor in
                NotificationManager.shared.center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground (since we're an LSUIElement app)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification click — open notch panel and focus the session
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let sessionId = userInfo["sessionId"] as? String

        Task { @MainActor in
            if let windowController = AppDelegate.shared?.windowController {
                windowController.openNotchForSession(sessionId: sessionId)
            }
        }

        completionHandler()
    }
}
