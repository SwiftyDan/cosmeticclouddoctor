//
//  BackgroundCallTrigger.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import UIKit
import CallKit

class BackgroundCallTrigger: NSObject, ObservableObject {
    static let shared = BackgroundCallTrigger()
    
    private let callKitManager = CallKitManager.shared
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var timer: Timer?
    
    @Published var isMonitoring = false
    @Published var lastLockTime: Date?
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        print("App entered background")
        startBackgroundTask()
    }
    
    @objc private func appWillEnterForeground() {
        print("App will enter foreground")
        endBackgroundTask()
    }
    
    @objc private func appDidBecomeActive() {
        print("App became active")
        isMonitoring = false
        endBackgroundTask()
    }
    
    @objc private func appWillResignActive() {
        print("App will resign active - device likely being locked")
        // Background call functionality disabled
        // lastLockTime = Date()
        // isMonitoring = true
        
        // Start a timer to trigger call after a short delay
        // This simulates the device being locked
        // DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        //     if self.isMonitoring {
        //         self.triggerLockScreenCall()
        //     }
        // }
    }
    
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CallTrigger") {
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    func triggerLockScreenCall() {
        // Background call functionality disabled
        print("Background call functionality has been disabled")
        return
        
        // guard isMonitoring else { return }
        
        // print("Triggering lock screen call...")
        
        // // Use default caller info for background call
        // let phoneNumber = "+1 (555) 123-4567"
        // let displayName = "Background Call"
        
        // // Trigger the call
        // callKitManager.startIncomingCall(phoneNumber: phoneNumber, displayName: displayName)
        
        // // Stop monitoring after triggering
        // isMonitoring = false
    }
    
    func startLockScreenMonitoring() {
        print("Starting lock screen monitoring...")
        isMonitoring = true
        
        // Show instructions to user
        DispatchQueue.main.async {
            // You could show an alert here to inform the user
            print("Lock your device now to trigger a call!")
        }
    }
    
    func stopLockScreenMonitoring() {
        print("Stopping lock screen monitoring...")
        isMonitoring = false
        endBackgroundTask()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 