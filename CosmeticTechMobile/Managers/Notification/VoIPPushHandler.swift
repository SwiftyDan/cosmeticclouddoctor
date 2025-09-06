//
//  VoIPPushHandler.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import PushKit
import CallKit
import UIKit
import UserNotifications

extension Notification.Name {
    static let VoIPCallDidEnd = Notification.Name("VoIPCallDidEnd")
    static let VoIPCallAccepted = Notification.Name("VoIPCallAccepted")
}

/// Handles VoIP push notifications using PushKit framework
/// Following Apple's best practices for VoIP implementation
class VoIPPushHandler: NSObject {
    static let shared = VoIPPushHandler()
    
    private var voipRegistry: PKPushRegistry?
    private let keychain = KeychainService()
    private var isInCall: Bool = false
    private var isCallRinging: Bool = false

    // Simple in-memory queue for pending VoIP calls
    struct PendingCall {
        let phoneNumber: String
        let displayName: String
        let callType: String
        let roomId: String?
        let callHistoryId: Int?
        let conferenceUrl: String?
        let scriptId: Int?
        let clinicSlug: String?
        let timestamp: Date
    }
    private var pendingCalls: [PendingCall] = []
    private let pendingQueue = DispatchQueue(label: "com.cosmetictech.voip.pending")

    override init() {
        super.init()
        // Don't initialize PushKit registry here - wait for proper app lifecycle
        
        // Observe call state changes
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoIPCallDidEnd), name: .VoIPCallDidEnd, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoIPCallAccepted), name: .VoIPCallAccepted, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Initialize VoIP push registry when app is ready
    /// Should be called from AppDelegate's didFinishLaunchingWithOptions
    func initializeVoIPPushRegistry() {
        print("🔄 VoIPPushHandler: Initializing VoIP push registry...")
        
        // Only initialize if not already done
        guard voipRegistry == nil else {
            print("⚠️ VoIPPushHandler: Registry already initialized")
            return
        }
        
        voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        voipRegistry?.delegate = self
        voipRegistry?.desiredPushTypes = [.voIP]
        
        print("✅ VoIPPushHandler: VoIP push registry initialized")
    }
    
    /// Refresh VoIP token if needed
    func refreshVoIPToken() {
        guard let registry = voipRegistry else {
            print("⚠️ VoIPPushHandler: Cannot refresh token - registry not initialized")
            return
        }
        
        // Force token refresh by re-setting desired push types
        registry.desiredPushTypes = []
        registry.desiredPushTypes = [.voIP]
        
        print("🔄 VoIPPushHandler: Requesting VoIP token refresh...")
    }
    
    /// Get current VoIP push token
    func getCurrentVoIPToken() -> String? {
        return keychain.retrieve(key: "voip_push_token", type: String.self)
    }
    
    // MARK: - Call Queue Management
    
    /// Helper to enqueue a call from parsed payload data
    private func enqueuePendingCall(phoneNumber: String, displayName: String, callType: String, roomId: String?, callHistoryId: Int?, conferenceUrl: String?, scriptId: Int?, clinicSlug: String?) {
        let newCall = PendingCall(
            phoneNumber: phoneNumber,
            displayName: displayName,
            callType: callType,
            roomId: roomId,
            callHistoryId: callHistoryId,
            conferenceUrl: conferenceUrl,
            scriptId: scriptId,
            clinicSlug: clinicSlug,
            timestamp: Date()
        )
        
        pendingQueue.async {
            self.pendingCalls.append(newCall)
            let count = self.pendingCalls.count
            
            DispatchQueue.main.async {
                self.scheduleQueueNotification(count: count, callerName: displayName)
            }
        }
    }
    
    /// Attempt to dequeue and present the next queued call, if any
    func dequeueAndPresentNextIfAny() {
        pendingQueue.async {
            guard !self.pendingCalls.isEmpty else { return }
            let next = self.pendingCalls.removeFirst()
            
            DispatchQueue.main.async {
                // Present using first-class details
                CallKitManager.shared.startIncomingCall(
                    phoneNumber: next.phoneNumber,
                    displayName: next.displayName,
                    callType: next.callType,
                    roomId: next.roomId,
                    callHistoryId: next.callHistoryId,
                    conferenceUrl: next.conferenceUrl,
                    roomName: next.roomId,
                    scriptId: next.scriptId,
                    clinicSlug: next.clinicSlug
                )
            }
        }
    }
    
    /// Set call state (used by CallKitManager)
    func setCallState(isInCall: Bool, isRinging: Bool = false) {
        self.isInCall = isInCall
        self.isCallRinging = isRinging
    }
    
    // MARK: - VoIP Call State Handling
    
    @objc private func handleVoIPCallDidEnd(_ notification: Notification) {
        print("🔔 VoIPPushHandler: Received VoIPCallDidEnd notification")
        // Reset in-call state and present next queued call if any
        isInCall = false
        isCallRinging = false
        dequeueAndPresentNextIfAny()
    }
    
    @objc private func handleVoIPCallAccepted(_ notification: Notification) {
        print("🔔 VoIPPushHandler: Received VoIPCallAccepted notification")
        isInCall = true
        isCallRinging = false
        
        // Show notification about queued calls if any
        pendingQueue.async {
            let count = self.pendingCalls.count
            if count > 0 {
                DispatchQueue.main.async {
                    self.scheduleAcceptedCallNotification(queuedCount: count)
                }
            }
        }
    }
    
    // MARK: - Push Notifications
    
    /// Notify user about queued calls when a new call comes in
    private func scheduleQueueNotification(count: Int, callerName: String) {
        guard count > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "📞 Call Queue"
        content.body = "\(callerName) added to queue (\(count) call\(count > 1 ? "s" : "") waiting)"
        content.sound = .default
        content.badge = NSNumber(value: count)
        
        let request = UNNotificationRequest(
            identifier: "VoIPQueue_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("⚠️ Failed to schedule VoIP queue notification: \(error)")
            } else {
                print("📱 VoIPPushHandler: Queued call notification scheduled for \(callerName)")
            }
        }
    }
    
    /// Notify user about queued calls when they accept a call
    private func scheduleAcceptedCallNotification(queuedCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "📞 Call Accepted"
        content.body = "You have \(queuedCount) call\(queuedCount > 1 ? "s" : "") waiting in queue"
        content.sound = .default
        content.badge = NSNumber(value: queuedCount)
        
        let request = UNNotificationRequest(
            identifier: "VoIPAccepted_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("⚠️ Failed to schedule accepted call notification: \(error)")
            } else {
                print("📱 VoIPPushHandler: Accepted call notification scheduled with \(queuedCount) queued")
            }
        }
    }
    
    /// Check if user is validated for receiving calls
    private func validateUserForCall() -> Bool {
        print("🔍 VoIPPushHandler: Validating user for incoming call...")
        
        // Check if we have user data in keychain with better error handling
        guard let user: User = keychain.retrieve(key: "user_data", type: User.self) else {
            print("🚫 VoIPPushHandler: User validation failed - No user data in keychain")
            return false
        }
        
        // Check if user has required fields
        guard let name = user.name, !name.isEmpty else {
            print("🚫 VoIPPushHandler: User validation failed - User name is empty or nil")
            return false
        }
        
        guard !user.email.isEmpty else {
            print("🚫 VoIPPushHandler: User validation failed - User email is empty")
            return false
        }
        
        guard user.userId > 0 else {
            print("🚫 VoIPPushHandler: User validation failed - Invalid user ID")
            return false
        }
        
        // Check if we have authentication token
        guard let authToken = keychain.retrieve(key: "auth_token", type: String.self),
              !authToken.isEmpty else {
            print("🚫 VoIPPushHandler: User validation failed - No authentication token")
            return false
        }
        
        print("✅ VoIPPushHandler: User validation passed for incoming call")
        print("   - User: \(name)")
        print("   - Email: \(user.email)")
        print("   - ID: \(user.userId)")
        print("   - Has auth token: \(!authToken.isEmpty)")
        
        return true
    }
}

// MARK: - PKPushRegistryDelegate
extension VoIPPushHandler: PKPushRegistryDelegate {
    
    /// Called when VoIP push token is updated
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 VoIPPushHandler: Received VoIP push token: \(token)")
        
        // Store token in keychain for API registration
        do {
            try keychain.save(key: "voip_push_token", value: token)
        } catch {
            print("❌ VoIPPushHandler: Failed to save VoIP token to keychain: \(error)")
        }
        
        // TODO: Send token to your server for VoIP push notifications
        // You should implement API call to register this token with your backend
        registerVoIPTokenWithServer(token: token)
    }
    
    /// Called when VoIP push token becomes invalid
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        
        print("⚠️ VoIPPushHandler: VoIP push token invalidated")
        
        // Remove token from keychain
        keychain.delete(key: "voip_push_token")
        
        // TODO: Notify your server that the token is no longer valid
        unregisterVoIPTokenWithServer()
    }
    
    /// Called when VoIP push notification is received
    /// This is the critical method that must report incoming calls to CallKit
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }
        
        print("📞 VoIPPushHandler: Received VoIP push notification")
        print("📞 Payload: \(payload.dictionaryPayload)")
        
        // CRITICAL: We must ALWAYS report a call to CallKit when receiving VoIP push
        // Even if we plan to reject it, we must report it first to avoid app termination
        // Apple requires this to prevent abuse of VoIP pushes
        
        // Extract call information from payload
        // The payload structure shows: additional_data contains the call info
        guard let additionalData = payload.dictionaryPayload["additional_data"] as? [String: Any] else {
            print("🚫 VoIPPushHandler: No additional_data in payload")
            print("🚫 Available keys: \(payload.dictionaryPayload.keys)")
            
            // CRITICAL: Still must report a call to avoid termination
            CallKitManager.shared.startIncomingCall(
                phoneNumber: "unknown",
                displayName: "Unknown Caller"
            ) { error in
                if let error = error {
                    print("❌ VoIPPushHandler: Failed to report fallback call: \(error)")
                }
                // Immediately end the call since payload is invalid
                CallKitManager.shared.endCall()
            }
            
            completion()
            return
        }
        
        // Extract call information from additional_data
        guard let callerName = additionalData["caller_name"] as? String else {
            print("🚫 VoIPPushHandler: No caller_name in additional_data")
            print("🚫 Available additional_data keys: \(additionalData.keys)")
            
            // CRITICAL: Still must report a call to avoid termination
            CallKitManager.shared.startIncomingCall(
                phoneNumber: "unknown",
                displayName: "Unknown Caller"
            ) { error in
                if let error = error {
                    print("❌ VoIPPushHandler: Failed to report fallback call: \(error)")
                }
                // Immediately end the call since caller name is missing
                CallKitManager.shared.endCall()
            }
            
            completion()
            return
        }
        
        // Use caller_id as phone number if available, otherwise use a placeholder
        let phoneNumber = payload.dictionaryPayload["caller_id"] as? String ?? "unknown"
        let displayName = callerName
        
        // Extract additional call parameters
        let callType = additionalData["call_type"] as? String ?? "video"
        // Try both room_id and room_name for compatibility
        let roomId = additionalData["room_id"] as? String ?? additionalData["room_name"] as? String
        let callHistoryId = additionalData["call_history_id"] as? Int
        let conferenceUrl = additionalData["conference_url"] as? String
        let scriptId = additionalData["script_id"] as? Int
        let clinicSlug = additionalData["clinic_slug"] as? String
        
        print("📞 VoIPPushHandler: Processing incoming call from \(displayName) (\(phoneNumber))")
        print("📞 Call details: type=\(callType), roomId=\(roomId ?? "nil"), callHistoryId=\(callHistoryId ?? 0)")
        
        // Check if we're already in a call or have a call ringing
        if isInCall || isCallRinging {
            print("📞 VoIPPushHandler: Call already in progress or ringing - queuing this call")
            enqueuePendingCall(
                phoneNumber: phoneNumber,
                displayName: displayName,
                callType: callType,
                roomId: roomId,
                callHistoryId: callHistoryId,
                conferenceUrl: conferenceUrl,
                scriptId: scriptId,
                clinicSlug: clinicSlug
            )
            completion()
            return
        }
        
        // CRITICAL: Always report call to CallKit first, then validate user
        // This prevents iOS from terminating the app
        CallKitManager.shared.startIncomingCall(
            phoneNumber: phoneNumber,
            displayName: displayName,
            callType: callType,
            roomId: roomId,
            callHistoryId: callHistoryId,
            conferenceUrl: conferenceUrl,
            roomName: roomId, // Use roomId as roomName for now
            scriptId: scriptId,
            clinicSlug: clinicSlug
        ) { error in
            if let error = error {
                print("❌ VoIPPushHandler: Failed to report call to CallKit: \(error)")
            } else {
                print("✅ VoIPPushHandler: Call reported to CallKit successfully")
                
                // Mark as ringing
                self.isCallRinging = true
                
                // Now validate user - if validation fails, end the call
                if !self.validateUserForCall() {
                    print("🚫 VoIPPushHandler: User validation failed after reporting call - ending call")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        CallKitManager.shared.endCall()
                    }
                }
            }
        }
        
        // Complete the handler to tell the system we've processed the push
        completion()
    }
    
    // MARK: - Private Methods
    
    /// Register VoIP token with your server
    private func registerVoIPTokenWithServer(token: String) {
        // TODO: Implement API call to register VoIP token with your backend
        print("🔄 VoIPPushHandler: Should register token with server: \(token)")
        
        // Example implementation:
        /*
        Task {
            do {
                try await APIService.shared.registerVoIPToken(token)
                print("✅ VoIPPushHandler: Token registered with server")
            } catch {
                print("❌ VoIPPushHandler: Failed to register token: \(error)")
            }
        }
        */
    }
    
    /// Unregister VoIP token from your server
    private func unregisterVoIPTokenWithServer() {
        // TODO: Implement API call to unregister VoIP token from your backend
        print("🔄 VoIPPushHandler: Should unregister token from server")
        
        // Example implementation:
        /*
        Task {
            do {
                try await APIService.shared.unregisterVoIPToken()
                print("✅ VoIPPushHandler: Token unregistered from server")
            } catch {
                print("❌ VoIPPushHandler: Failed to unregister token: \(error)")
            }
        }
        */
    }
}