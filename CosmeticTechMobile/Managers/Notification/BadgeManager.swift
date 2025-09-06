//
//  BadgeManager.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import UIKit

/// Centralized manager for app icon badge count
/// Ensures badge count stays synchronized with queue count
@MainActor
class BadgeManager: ObservableObject {
    static let shared = BadgeManager()
    
    @Published private(set) var currentBadgeCount: Int = 0
    
    private init() {
        // Load current badge count from UserDefaults on init
        currentBadgeCount = UserDefaults.standard.integer(forKey: "app_badge_count")
        updateAppBadge()
    }
    
    /// Updates the badge count to match the queue count
    /// - Parameter queueCount: The current number of items in the queue
    func updateBadgeCount(to queueCount: Int) {
        let newCount = max(0, queueCount) // Ensure non-negative
        
        guard newCount != currentBadgeCount else {
            print("📱 BadgeManager: Count unchanged (\(newCount)), skipping update")
            return
        }
        
        print("📱 BadgeManager: Updating badge count from \(currentBadgeCount) to \(newCount)")
        
        currentBadgeCount = newCount
        updateAppBadge()
        saveBadgeCount()
    }
    
    /// Clears the badge count (sets to 0)
    func clearBadge() {
        updateBadgeCount(to: 0)
    }
    
    /// Increments the badge count by 1
    func incrementBadge() {
        updateBadgeCount(to: currentBadgeCount + 1)
    }
    
    /// Decrements the badge count by 1 (minimum 0)
    func decrementBadge() {
        updateBadgeCount(to: max(0, currentBadgeCount - 1))
    }
    
    /// Updates the actual app icon badge
    private func updateAppBadge() {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = self.currentBadgeCount
            print("📱 BadgeManager: App badge updated to \(self.currentBadgeCount)")
        }
    }
    
    /// Saves the badge count to UserDefaults for persistence
    private func saveBadgeCount() {
        UserDefaults.standard.set(currentBadgeCount, forKey: "app_badge_count")
        UserDefaults.standard.synchronize()
    }
    
    /// Resets badge count and clears UserDefaults
    func resetBadge() {
        currentBadgeCount = 0
        updateAppBadge()
        UserDefaults.standard.removeObject(forKey: "app_badge_count")
        UserDefaults.standard.synchronize()
        print("📱 BadgeManager: Badge reset to 0")
    }
}
