//
//  ActivityService.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import Foundation
import SwiftUI

// MARK: - Activity Service Protocol
protocol ActivityServiceProtocol {
    func getRecentActivities() -> [ActivityItem]
    func addActivity(_ activity: ActivityItem)
    func clearActivities()
}

// MARK: - Activity Service Implementation
class ActivityService: ActivityServiceProtocol {
    private var activities: [ActivityItem] = []
    
    init() {
        loadDefaultActivities()
    }
    
    func getRecentActivities() -> [ActivityItem] {
        return activities
    }
    
    func addActivity(_ activity: ActivityItem) {
        activities.insert(activity, at: 0)
        
        // Keep only the last 10 activities
        if activities.count > 10 {
            activities = Array(activities.prefix(10))
        }
    }
    
    func clearActivities() {
        activities.removeAll()
    }
    
    private func loadDefaultActivities() {
        activities = [
            ActivityItem(
                title: "VoIP Token Updated",
                subtitle: "Push notifications configured",
                icon: "checkmark.circle.fill",
                color: .green,
                timestamp: "Now"
            ),
            ActivityItem(
                title: "Login Successful",
                subtitle: "Welcome to Cosmetic Cloud VC",
                icon: "person.badge.plus",
                color: .blue,
                timestamp: "2 min ago"
            )
        ]
    }
} 
