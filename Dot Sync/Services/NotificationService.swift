//
//  NotificationService.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation
import UserNotifications

/// Service for sending native macOS notifications
class NotificationService {
    static let shared = NotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Setup

    init() {
        requestAuthorization()
    }

    /// Request notification permissions
    private func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("[Notifications] Permission granted")
            } else if let error = error {
                print("[Notifications] Permission denied: \(error)")
            }
        }
    }

    // MARK: - Notifications

    /// Send notification
    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("[Notifications] Error sending: \(error)")
            }
        }
    }

    /// Notify sync completed
    func notifySyncCompleted(fileCount: Int) {
        notify(
            title: "Sync Completed",
            body: "Successfully synced \(fileCount) config files"
        )
    }

    /// Notify conflicts detected
    func notifyConflictsDetected(count: Int) {
        notify(
            title: "Conflicts Detected",
            body: "\(count) files need manual resolution"
        )
    }

    /// Notify sync failed
    func notifySyncFailed(error: String) {
        notify(
            title: "Sync Failed",
            body: error
        )
    }

    /// Notify files changed on another machine
    func notifyRemoteChanges(fileCount: Int, machine: String? = nil) {
        let machineText = machine ?? "another machine"
        notify(
            title: "Remote Changes Detected",
            body: "\(fileCount) files changed on \(machineText)"
        )
    }

    /// Notify new machine detected
    func notifyNewMachine(name: String) {
        notify(
            title: "New Machine Detected",
            body: "\(name) has joined your sync network"
        )
    }
}
