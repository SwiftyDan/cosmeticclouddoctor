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
    
    // Use a dedicated high-priority queue for VoIP push handling
    private let voipQueue = DispatchQueue(label: "com.cosmetictech.voip.registry", qos: .userInteractive)
    
    private lazy var voipRegistry: PKPushRegistry = {
        let registry = PKPushRegistry(queue: voipQueue)
        // Preconfigure desired types immediately so the system starts fetching a token
        registry.desiredPushTypes = [.voIP]
        return registry
    }()
    
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
        let roomName: String?
        let scriptId: Int?
        let clinicSlug: String?
        let scriptUUID: String?
        let clinicName: String?
        let timestamp: Date
    }
    private var pendingCalls: [PendingCall] = []
    private let pendingQueue = DispatchQueue(label: "com.cosmetictech.voip.pending")

    // Enhanced monitoring for VoIP delivery
    private var callDeliveryStats: [String: Date] = [:]
    private var lastVoIPTokenRefresh: Date?
    private var voipPushCount: Int = 0

    override init() {
        super.init()
        print("🚀 VoIPPushHandler initializing...")
        // IMPORTANT: Set up PushKit delegate immediately on launch (especially when app is launched by VoIP push)
        setupVoIPPush()
        // Capability checks can be deferred
        DispatchQueue.main.async { self.checkAppCapabilities() }
        
        // Observe call state changes
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoIPCallDidEnd), name: .VoIPCallDidEnd, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoIPCallAccepted), name: .VoIPCallAccepted, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Helper Methods
    
    /// Extract script_uuid and clinic_name from conference URL query parameters
    private func extractScriptDataFromURL(_ urlString: String) -> (scriptUUID: String?, clinicName: String?) {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return (nil, nil)
        }
        
        var scriptUUID: String?
        var clinicName: String?
        
        for item in queryItems {
            switch item.name {
            case "script_uuid":
                scriptUUID = item.value
            case "clinic_name":
                clinicName = item.value
            default:
                break
            }
        }
        
        print("🔍 Extracted from URL: script_uuid=\(scriptUUID ?? "nil"), clinic_name=\(clinicName ?? "nil")")
        return (scriptUUID, clinicName)
    }
    
    private func setupVoIPPush() {
        print("🔧 Setting up VoIP push registry...")
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
        print("✅ VoIP push registry setup completed")
        print("📱 Requesting VoIP push token...")
        
        // Also register for remote notifications
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
            print("📱 Registered for remote notifications")
        }
    }
    
    private func checkAppCapabilities() {
        print("🔍 Checking app capabilities...")
        
        // Check permissions silently; do not show alerts here
        NotificationService.shared.ensurePermissionsOrPromptSettings(showSettingsAlertIfDenied: false,
                                                                    requestIfNotDetermined: false)
        
        // Check background modes
        if let backgroundModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] {
            print("🔄 Background modes: \(backgroundModes)")
            if backgroundModes.contains("voip") {
                print("✅ VoIP background mode enabled")
            } else {
                print("❌ VoIP background mode NOT enabled")
            }
        } else {
            print("❌ No background modes found in Info.plist")
        }
    }
    
    // MARK: - Public Methods
    
    /// Initialize VoIP push registry when app is ready
    /// Should be called from AppDelegate's didFinishLaunchingWithOptions
    func initializeVoIPPushRegistry() {
        print("🔄 VoIPPushHandler: Initializing VoIP push registry...")
        
        // Registry is already initialized in init(), just ensure it's set up
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
        
        print("✅ VoIPPushHandler: VoIP push registry initialized")
    }
    
    /// Refresh VoIP token if needed
    func refreshVoIPToken() {
        // Force token refresh by re-setting desired push types
        voipRegistry.desiredPushTypes = []
        voipRegistry.desiredPushTypes = [.voIP]
        lastVoIPTokenRefresh = Date()

        print("🔄 VoIPPushHandler: Requesting VoIP token refresh...")
    }
    
    /// Get current VoIP push token
    func getCurrentVoIPToken() -> String? {
        if let pushCredentials = voipRegistry.pushToken(for: .voIP) {
            let token = pushCredentials.map { String(format: "%02.2hhx", $0) }.joined()
            return token
        }
        if let cached: String = keychain.retrieve(key: "voip_push_token", type: String.self), !cached.isEmpty {
            return cached
        }
        return nil
    }
    
    func printCurrentVoIPToken() {
        print("🔍 Checking current VoIP token status...")
        
        if let token = getCurrentVoIPToken() {
            print("🔔 Current VoIP push token: \(token)")
            print("📱 Token length: \(token.count / 2) bytes")
        } else {
            print("❌ No VoIP token available yet")
            print("🔄 Attempting to refresh VoIP token...")
            refreshVoIPToken()
        }
    }
    
    func checkVoIPRegistrationStatus() {
        print("🔍 Checking VoIP registration status...")
        print("📱 Desired push types: \(String(describing: voipRegistry.desiredPushTypes))")

        if let pushToken = voipRegistry.pushToken(for: .voIP) {
            let token = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
            print("🔔 Current VoIP token: \(token)")
        } else {
            print("❌ No VoIP token available")
        }
    }

    // MARK: - Enhanced Monitoring Methods

    /// Get comprehensive VoIP status for debugging
    func getVoIPStatus() -> [String: Any] {
        var status: [String: Any] = [:]

        // Token status
        if let token = getCurrentVoIPToken() {
            status["token_available"] = true
            status["token_length"] = token.count
        } else {
            status["token_available"] = false
        }

        // Background modes check
        if let backgroundModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] {
            status["background_modes"] = backgroundModes
            status["voip_background_enabled"] = backgroundModes.contains("voip")
        } else {
            status["background_modes"] = []
            status["voip_background_enabled"] = false
        }

        // Call state
        status["is_in_call"] = isInCall
        status["is_call_ringing"] = isCallRinging
        status["pending_calls_count"] = pendingCalls.count

        // Statistics
        status["total_voip_pushes"] = voipPushCount
        status["last_token_refresh"] = lastVoIPTokenRefresh?.description ?? "never"

        // Jitsi state check
        DispatchQueue.main.sync {
            status["jitsi_active"] = GlobalJitsiManager.shared.isPresentingJitsi
        }

        return status
    }

    /// Print detailed VoIP status for debugging
    func printVoIPStatus() {
        let status = getVoIPStatus()
        print("🔍 ===== VoIP STATUS REPORT =====")
        print("📱 Token Available: \(status["token_available"] ?? "unknown")")
        print("📏 Token Length: \(status["token_length"] ?? "N/A")")
        print("🔄 VoIP Background Enabled: \(status["voip_background_enabled"] ?? "unknown")")
        print("📞 In Call: \(status["is_in_call"] ?? "unknown")")
        print("🔔 Call Ringing: \(status["is_call_ringing"] ?? "unknown")")
        print("📋 Pending Calls: \(status["pending_calls_count"] ?? "unknown")")
        print("📊 Total VoIP Pushes: \(status["total_voip_pushes"] ?? "unknown")")
        print("🔄 Last Token Refresh: \(status["last_token_refresh"] ?? "unknown")")
        print("🎥 Jitsi Active: \(status["jitsi_active"] ?? "unknown")")
        print("===================================")
    }

    /// Track call delivery for monitoring
    private func trackCallDelivery(callId: String, successful: Bool) {
        let now = Date()
        if successful {
            callDeliveryStats[callId] = now
            print("✅ Call delivery tracked: \(callId)")
        } else {
            print("❌ Call delivery failed: \(callId)")
        }
    }

    /// Check for missed calls and provide statistics
    func checkCallDeliveryStats() {
        let now = Date()
        let recentCalls = callDeliveryStats.filter {
            now.timeIntervalSince($0.value) < 300 // Last 5 minutes
        }

        let oldCalls = callDeliveryStats.filter {
            now.timeIntervalSince($0.value) >= 300 // Older than 5 minutes
        }

        print("📊 Call Delivery Stats:")
        print("   - Recent calls (5min): \(recentCalls.count)")
        print("   - Older calls: \(oldCalls.count)")
        print("   - Total tracked: \(callDeliveryStats.count)")

        if oldCalls.count > 0 {
            print("⚠️ Potential missed calls detected: \(oldCalls.count)")
        }
    }
    
    // MARK: - Call Queue Management
    
    /// Helper to enqueue a call from parsed payload data
    private func enqueuePendingCall(phoneNumber: String, displayName: String, callType: String, roomId: String?, callHistoryId: Int?, conferenceUrl: String?, roomName: String?, scriptId: Int?, clinicSlug: String?, scriptUUID: String?, clinicName: String?) {
        let newCall = PendingCall(
            phoneNumber: phoneNumber,
            displayName: displayName,
            callType: callType,
            roomId: roomId,
            callHistoryId: callHistoryId,
            conferenceUrl: conferenceUrl,
            roomName: roomName,
            scriptId: scriptId,
            clinicSlug: clinicSlug,
            scriptUUID: scriptUUID,
            clinicName: clinicName,
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
                    roomName: next.roomName,
                    scriptId: next.scriptId,
                    clinicSlug: next.clinicSlug
                )
            }
        }
    }
    
    /// Clear queued calls that were queued during Jitsi meetings
    private func clearQueuedCallsFromJitsi() {
        pendingQueue.async {
            let clearedCount = self.pendingCalls.count
            self.pendingCalls.removeAll()
            
            if clearedCount > 0 {
                print("🎥 VoIPPushHandler: Cleared \(clearedCount) queued calls that were queued during Jitsi meeting")
            }
        }
    }
    
    /// Set call state (used by CallKitManager)
    func setCallState(isInCall: Bool, isRinging: Bool = false) {
        self.isInCall = isInCall
        self.isCallRinging = isRinging
    }
    
    /// Show push notification when Jitsi meeting is active
    private func showPushNotificationForJitsiCall(callerName: String, callerId: String, scriptId: Int?, clinicSlug: String?) {
        print("📱 VoIPPushHandler: Showing push notification for Jitsi call from \(callerName)")
        
        let content = UNMutableNotificationContent()
        content.title = "Incoming Call"
        content.body = "\(callerName) is calling you"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("ringtone.caf"))
        content.badge = 1
        content.categoryIdentifier = "INCOMING_CALL"
        
        // Add call data to userInfo for potential handling
        var userInfo: [String: Any] = [
            "caller_name": callerName,
            "caller_id": callerId,
            "call_type": "video"
        ]
        
        if let scriptId = scriptId {
            userInfo["script_id"] = scriptId
        }
        if let clinicSlug = clinicSlug {
            userInfo["clinic_slug"] = clinicSlug
        }
        
        content.userInfo = userInfo
        
        let request = UNNotificationRequest(
            identifier: "jitsi_call_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to show push notification for Jitsi call: \(error)")
            } else {
                print("✅ Push notification shown for Jitsi call from \(callerName)")
            }
        }
    }
    
    // MARK: - VoIP Call State Handling
    
    @objc private func handleVoIPCallDidEnd(_ notification: Notification) {
        print("🔔 VoIPPushHandler: Received VoIPCallDidEnd notification")
        // Reset in-call state
        isInCall = false
        isCallRinging = false
        
        // Check if this is from a Jitsi meeting ending
        // If so, clear queued calls instead of processing them
        Task { @MainActor in
            if GlobalJitsiManager.shared.isPresentingJitsi {
                print("🎥 VoIPPushHandler: Jitsi meeting is still active - not processing queued calls")
                return
            }
            
            // If Jitsi is not active, clear any queued calls that were queued during Jitsi
            // and only process queued calls that were queued for normal call conflicts
            self.clearQueuedCallsFromJitsi()
        }
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
        // Don't set badge here - let BadgeManager handle it based on actual queue count
        
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
        // Don't set badge here - let BadgeManager handle it based on actual queue count
        
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
        print("📨 Push credentials updated for type: \(type)")
        print("📨 Token data length: \(pushCredentials.token.count) bytes")
        
        if type == .voIP {
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
            print("🔔 VoIP push token: \(token)")
            print("📱 Token length: \(pushCredentials.token.count) bytes")
            print("📋 Copy this token to your Laravel backend for VoIP push notifications")
        
        // Store token in keychain for API registration
        do {
            try keychain.save(key: "voip_push_token", value: token)
                print("✅ VoIP token saved to keychain")
        } catch {
            print("❌ VoIPPushHandler: Failed to save VoIP token to keychain: \(error)")
            }
            
            // Post notification for token update
            NotificationCenter.default.post(name: .voipTokenUpdated, object: token)
        } else {
            print("⚠️ Received push credentials for non-VoIP type: \(type)")
        }
    }
    
    /// Called when VoIP push token becomes invalid
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        
        print("⚠️ VoIPPushHandler: VoIP push token invalidated")
        
        // Remove token from keychain
        keychain.delete(key: "voip_push_token")
    }
    

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }
        
        // CRITICAL: Must report call to CallKit and wait for it to complete
        // before calling the VoIP push completion handler
        handleVoIPPush(payload, voipCompletion: completion)
    }

    private func handleVoIPPush(_ payload: PKPushPayload, voipCompletion: (() -> Void)? = nil) {
        voipPushCount += 1
        let pushId = "voip_\(Date().timeIntervalSince1970)"

        print("📨 [\(pushId)] Received incoming VoIP push #\(voipPushCount): \(payload.dictionaryPayload)")

        // Print comprehensive status at the start of each VoIP push
        printVoIPStatus()

        // CRITICAL: Always report a call to CallKit, even if payload parsing fails
        // This prevents the app from being terminated by iOS

        // Store pushId for use in completion handler
        let currentPushId = pushId
        
        // Extract call information from push payload
        // Support multiple payload formats (new preferred: additional_data)
        var phoneNumber: String?
        var displayName: String?
        var callType: String = "video"
        var roomId: String?
        var callHistoryId: Int?
        var conferenceUrl: String?
        var roomName: String?
        var scriptId: Int?
        var clinicSlug: String?
        var scriptUUID: String?
        var clinicName: String?

        if let additional = payload.dictionaryPayload["additional_data"] as? [String: Any] {
            phoneNumber = payload.dictionaryPayload["caller_id"] as? String
            displayName = additional["caller_name"] as? String
            callType = (additional["call_type"] as? String) ?? callType
            conferenceUrl = additional["conference_url"] as? String
            roomName = additional["room_name"] as? String
            clinicSlug = additional["clinic_slug"] as? String
            scriptUUID = additional["script_uuid"] as? String
            clinicName = additional["clinic_name"] as? String
            if let chId = additional["call_history_id"] as? Int { callHistoryId = chId }
            else if let chStr = additional["call_history_id"] as? String, let chInt = Int(chStr) { callHistoryId = chInt }
            if let scId = additional["script_id"] as? Int { scriptId = scId }
            else if let scStr = additional["script_id"] as? String, let scInt = Int(scStr) { scriptId = scInt }
            
            // Extract script_uuid and clinic_name from conference_url if not present in additional_data
            if scriptUUID == nil || clinicName == nil, let urlString = conferenceUrl {
                let extracted = extractScriptDataFromURL(urlString)
                if scriptUUID == nil { scriptUUID = extracted.scriptUUID }
                if clinicName == nil { clinicName = extracted.clinicName }
            }
        } else if let callData = payload.dictionaryPayload["call_data"] as? [String: Any] {
            displayName = callData["caller_name"] as? String
            callType = callData["call_type"] as? String ?? "video"
            roomId = callData["room_id"] as? String
            callHistoryId = callData["call_history_id"] as? Int
            conferenceUrl = callData["conference_url"] as? String
            roomName = callData["room_name"] as? String
            scriptId = callData["script_id"] as? Int
            clinicSlug = callData["clinic_slug"] as? String
            scriptUUID = callData["script_uuid"] as? String
            clinicName = callData["clinic_name"] as? String
            
            // Extract script_uuid and clinic_name from conference_url if not present in call_data
            if scriptUUID == nil || clinicName == nil, let urlString = conferenceUrl {
                let extracted = extractScriptDataFromURL(urlString)
                if scriptUUID == nil { scriptUUID = extracted.scriptUUID }
                if clinicName == nil { clinicName = extracted.clinicName }
            }
            
            if let callerId = payload.dictionaryPayload["caller_id"] as? String { phoneNumber = callerId }
        } else if let callData = payload.dictionaryPayload["call"] as? [String: Any] {
            phoneNumber = callData["phoneNumber"] as? String
            displayName = callData["displayName"] as? String
            callType = callData["callType"] as? String ?? "video"
            roomId = callData["room_id"] as? String
        }

        let phoneNumberFinal = phoneNumber ?? "Unknown"
        let displayNameFinal = displayName ?? "Unknown"
        
        // Debug log the extracted values
        print("📱 VoIP Push Parsed Data:")
        print("   - phoneNumber: \(phoneNumberFinal)")
        print("   - displayName: \(displayNameFinal)")
        print("   - callType: \(callType)")
        print("   - clinicSlug: \(clinicSlug ?? "nil")")
        print("   - scriptId: \(scriptId?.description ?? "nil")")
        print("   - roomName: \(roomName ?? "nil")")
        print("   - conferenceUrl: \(conferenceUrl ?? "nil")")
        print("   - scriptUUID: \(scriptUUID ?? "nil")")
        print("   - clinicName: \(clinicName ?? "nil")")

        // Check if we're already in a call, have a call ringing, or in a Jitsi meeting
        if isInCall || isCallRinging {
            print("📞 VoIPPushHandler: Call already in progress or ringing - queuing this call")
            enqueuePendingCall(
                phoneNumber: phoneNumberFinal,
                displayName: displayNameFinal,
                callType: callType,
                roomId: roomId ?? roomName,
                callHistoryId: callHistoryId,
                conferenceUrl: conferenceUrl,
                roomName: roomName,
                scriptId: scriptId,
                clinicSlug: clinicSlug,
                scriptUUID: scriptUUID,
                clinicName: clinicName
            )
            voipCompletion?()
            return
        }
        
        // Check if Jitsi meeting is currently active
        DispatchQueue.main.async {
            if GlobalJitsiManager.shared.isPresentingJitsi {
                print("🎥 VoIPPushHandler: Jitsi meeting is active - showing push notification instead of CallKit call")
                self.showPushNotificationForJitsiCall(
                    callerName: displayNameFinal,
                    callerId: phoneNumberFinal,
                    scriptId: scriptId,
                    clinicSlug: clinicSlug
                )
                voipCompletion?()
                return
            }
            
            // If Jitsi is not active, proceed with normal CallKit flow
            self.reportCallToCallKit(phoneNumber: phoneNumberFinal,
                                   displayName: displayNameFinal,
                                   callType: callType,
                                   roomId: roomId ?? roomName,
                                   callHistoryId: callHistoryId,
                                   conferenceUrl: conferenceUrl,
                                   roomName: roomName,
                                   scriptId: scriptId,
                                   clinicSlug: clinicSlug,
                                   scriptUUID: scriptUUID,
                                   clinicName: clinicName,
                                   voipCompletion: voipCompletion)
        }
    }
    
    private func reportCallToCallKit(phoneNumber: String,
                                     displayName: String,
                                     callType: String,
                                     roomId: String?,
                                     callHistoryId: Int?,
                                     conferenceUrl: String?,
                                     roomName: String?,
                                     scriptId: Int?,
                                     clinicSlug: String?,
                                     scriptUUID: String?,
                                     clinicName: String?,
                                     voipCompletion: (() -> Void)?) {
        // CRITICAL: Report call to CallKit and wait for completion
        // This ensures iOS doesn't terminate the app for unhandled VoIP pushes
        if Thread.isMainThread {
        CallKitManager.shared.startIncomingCall(
            phoneNumber: phoneNumber,
            displayName: displayName,
            callType: callType,
            roomId: roomId,
            callHistoryId: callHistoryId,
            conferenceUrl: conferenceUrl,
                roomName: roomName,
            scriptId: scriptId,
                clinicSlug: clinicSlug,
                scriptUUID: scriptUUID,
                clinicName: clinicName
        ) { error in
                // Track call delivery success/failure
                if let error = error {
                    print("❌ [\(currentPushId)] CallKit error: \(error)")
                    self.trackCallDelivery(callId: currentPushId, successful: false)
                } else {
                    print("✅ [\(currentPushId)] CallKit reported successfully")
                    self.trackCallDelivery(callId: currentPushId, successful: true)
                }

                // Call VoIP completion handler after CallKit is notified
                // CRITICAL: Must call completion even on error to prevent crash
                if let voipCompletion = voipCompletion {
                    voipCompletion()
                }
            }
            } else {
            DispatchQueue.main.sync {
                CallKitManager.shared.startIncomingCall(
                    phoneNumber: phoneNumber,
                    displayName: displayName,
                    callType: callType,
                    roomId: roomId,
                    callHistoryId: callHistoryId,
                    conferenceUrl: conferenceUrl,
                    roomName: roomName,
                    scriptId: scriptId,
                    clinicSlug: clinicSlug,
                    scriptUUID: scriptUUID,
                    clinicName: clinicName
                ) { error in
                    // Track call delivery success/failure
                    if let error = error {
                        print("❌ [\(currentPushId)] CallKit error (sync): \(error)")
                        self.trackCallDelivery(callId: currentPushId, successful: false)
                    } else {
                        print("✅ [\(currentPushId)] CallKit reported successfully (sync)")
                        self.trackCallDelivery(callId: currentPushId, successful: true)
                    }

                    // Call VoIP completion handler after CallKit is notified
                    // CRITICAL: Must call completion even on error to prevent crash
                    if let voipCompletion = voipCompletion {
                        voipCompletion()
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Register VoIP token with your server
    private func registerVoIPTokenWithServer(token: String) {
    
    }
    
    /// Unregister VoIP token from your server
    private func unregisterVoIPTokenWithServer() {
      
    }
}