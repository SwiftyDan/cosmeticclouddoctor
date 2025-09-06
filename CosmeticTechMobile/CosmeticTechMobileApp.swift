//
//  CosmeticTechMobileApp.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct CosmeticTechMobileApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var authManager = AuthManager()
    @StateObject private var authenticationHandler = AuthenticationHandler.shared
    
    // Initialize VoIP push handler for background call handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Minimal initialization - avoid early VoIP setup
        // VoIP and notifications will be initialized in AppDelegate
        print("🚀 CosmeticTechMobileApp: App initialized")
    }
    
    var body: some Scene {
        WindowGroup {
            if authManager.isLoggedIn {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(authManager)
                    .environmentObject(CallKitManager.shared)
                    .environmentObject(WebViewService.shared)
                    .onAppear {
                        // Initialize authentication handler with auth manager
                        authenticationHandler.setAuthManager(authManager)
                    }
            } else {
                LoginView()
                    .environmentObject(authManager)
                    .onAppear {
                        // Initialize authentication handler with auth manager
                        authenticationHandler.setAuthManager(authManager)
                    }
            }
        }
    }
}

// MARK: - App Delegate for VoIP Push Handling
@objcMembers
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Stored property exposed to Objective‑C runtime so frameworks can query it
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("🚀 AppDelegate: Application did finish launching")
        
        // Set UNUserNotificationCenter delegate for foreground notifications
        UNUserNotificationCenter.current().delegate = self
        
        // Initialize VoIP push registry following Apple's best practices
        // This should be done early in the app lifecycle
        VoIPPushHandler.shared.initializeVoIPPushRegistry()
        
        // Register for remote notifications (non-VoIP)
        // Do this silently without showing permission dialog
        NotificationService.shared.ensurePermissionsOrPromptSettings(showSettingsAlertIfDenied: false)
        UIApplication.shared.registerForRemoteNotifications()
        
        // Initialize background call trigger
        _ = BackgroundCallTrigger.shared
        
        // Handle app launch from push notification (rare case)
        handleLaunchFromPushNotification(launchOptions: launchOptions)
        
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if window == nil {
            window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        // Store token for later use if needed
        UserDefaults.standard.set(token, forKey: "deviceToken")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Log error to analytics or crash reporting service
        // For now, silently handle the error
    }
    
    // Handle incoming push notifications when app is in background
    // Note: VoIP calls should primarily come through PushKit, not regular push notifications
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📱 AppDelegate: Received remote notification: \(userInfo)")
        
        // For VoIP calls, we should primarily rely on PushKit (handled in VoIPPushHandler)
        // This method handles non-VoIP push notifications
        // If you receive VoIP calls here, consider moving them to PushKit for better reliability
        
        completionHandler(.noData)
    }
    
    // MARK: - Push Notification Handling
    
    /// Handle app launch from push notification (rare case for VoIP)
    private func handleLaunchFromPushNotification(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard let launchOptions = launchOptions,
              let userInfo = launchOptions[.remoteNotification] as? [AnyHashable: Any] else {
            return
        }
        
        print("📱 AppDelegate: App launched from push notification: \(userInfo)")
        
        // For VoIP calls launched from push, we should still validate and handle properly
        // However, most VoIP calls should come through PushKit, not launch options
        if let callData = userInfo["call"] as? [String: Any],
           let phoneNumber = callData["phoneNumber"] as? String,
           let displayName = callData["displayName"] as? String {
            
            print("📞 AppDelegate: Processing call from launch notification")
            
            // Delay call trigger to ensure app UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.validateUserForCall() {
                    CallKitManager.shared.startIncomingCall(phoneNumber: phoneNumber, displayName: displayName)
                } else {
                    print("🚫 AppDelegate: Launch call rejected - User validation failed")
                }
            }
        }
    }
    
    // MARK: - User Validation
    /// Validates that the user has complete information before allowing calls
    private func validateUserForCall() -> Bool {
        print("🔍 AppDelegate: Validating user for incoming call...")
        
        let keychain = KeychainService()
        
        // Check if we have user data in keychain
        guard let user: User = keychain.retrieve(key: "user_data", type: User.self) else {
            print("🚫 AppDelegate: User validation failed - No user data in keychain")
            return false
        }
        
        // Check if user has required fields
        guard let name = user.name, !name.isEmpty else {
            print("🚫 AppDelegate: User validation failed - User name is empty or nil")
            return false
        }
        
        guard !user.email.isEmpty else {
            print("🚫 AppDelegate: User validation failed - User email is empty")
            return false
        }
        
        guard user.userId > 0 else {
            print("🚫 AppDelegate: User validation failed - Invalid user ID")
            return false
        }
        
        // Check if we have authentication token
        guard let authToken = keychain.retrieve(key: "auth_token", type: String.self),
              !authToken.isEmpty else {
            print("🚫 AppDelegate: User validation failed - No authentication token")
            return false
        }
        
        print("✅ AppDelegate: User validation passed for incoming call")
        print("   - User: \(name)")
        print("   - Email: \(user.email)")
        print("   - ID: \(user.userId)")
        print("   - Has auth token: \(!authToken.isEmpty)")
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        print("🚀 AppDelegate: Application will terminate - cleaning up call session")
        // End any active call when app is terminated
        CallKitManager.shared.endCall()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("🚀 AppDelegate: Application did enter background")
        // Optionally end call when app goes to background
        // This ensures call session doesn't persist when app is backgrounded
        if CallKitManager.shared.isInCall {
            print("📞 AppDelegate: Ending call due to backgrounding")
            CallKitManager.shared.endCall()
        }
    }

}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate {
    // Show notifications while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    
    // Handle user tapping on notification
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
