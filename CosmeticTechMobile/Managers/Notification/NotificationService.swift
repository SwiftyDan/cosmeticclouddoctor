//
//  NotificationService.swift
//  CosmeticTechMobile
//
//  Created by Assistant on 8/14/25.
//

import Foundation
import UserNotifications
import UIKit

final class NotificationService {
    static let shared = NotificationService()

    private init() {}
    private var recentNotifications: [String: Date] = [:]

    // MARK: - Permissions
    func ensurePermissionsOrPromptSettings(showSettingsAlertIfDenied: Bool = true,
                                           requestIfNotDetermined: Bool = true,
                                           completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion?()
            case .notDetermined:
                if requestIfNotDetermined {
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        DispatchQueue.main.async {
                            if granted { completion?() }
                            else if showSettingsAlertIfDenied { self.presentEnablePushAlert() }
                        }
                    }
                } else {
                    // Do nothing; caller chose to avoid prompting on first launch
                }
            case .denied:
                if showSettingsAlertIfDenied {
                    DispatchQueue.main.async { self.presentEnablePushAlert() }
                }
            @unknown default:
                if showSettingsAlertIfDenied {
                    DispatchQueue.main.async { self.presentEnablePushAlert() }
                }
            }
        }
    }

    private func presentEnablePushAlert() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let alert = UIAlertController(
            title: "Enable Notifications",
            message: "To get important updates, please allow push notifications in Settings.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        root.present(alert, animated: true)
    }

    func scheduleMissedCallNotification(callerName: String?, phoneNumber: String?) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        
        let message = "Incoming Call Request Added to Queue"
        content.title = "Consultation queued"
        content.body = message
        content.sound = .default
        content.threadIdentifier = "calls"
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        // Deliver shortly after call ends to avoid being swallowed by CallKit teardown
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.6, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        center.getNotificationSettings { settings in
            // Only schedule if authorized; otherwise do nothing
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                print("⚠️ Notifications not authorized; missed call notification suppressed")
                return
            }
            center.add(request) { error in
                if let error = error {
                    print("❌ Failed to schedule missed call notification: \(error)")
                } else {
                    print("🔔 Missed call notification scheduled")
                }
            }
        }
    }

    // MARK: - Queue Notifications
    func scheduleQueueAddedNotification(patientName: String?, id: String) {
        let message = "Incoming Call Request Added to Queue"
        scheduleQueueChange(id: "queue.add.\(id)", title: message, body: message)
    }

    func scheduleQueueRemovedNotification(patientName: String?, id: String) {
        let message = "Incoming call was cancelled. They've been removed from your queue"
        scheduleQueueChange(id: "queue.remove.\(id)", title: "Call Cancelled", body: message)
    }

    private func scheduleQueueChange(id: String, title: String, body: String) {
        // Debounce identical notifications within 1.5 seconds
        let now = Date()
        if let last = recentNotifications[id], now.timeIntervalSince(last) < 1.5 {
            return
        }
        recentNotifications[id] = now
        
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "queue"
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        // Use deterministic identifier so newer replaces pending duplicates
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            center.add(request, withCompletionHandler: nil)
        }
    }
}


