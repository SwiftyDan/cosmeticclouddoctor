//
//  CallKitManager.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import CallKit
import UIKit

/// Manages CallKit integration for VoIP calls
class CallKitManager: NSObject, ObservableObject {
    static let shared = CallKitManager()
    
    // MARK: - Properties
    private var callProvider: CXProvider?
    private var callController: CXCallController?
    private var currentCallUUID: UUID?
    private var isEndingForJitsiTransition: Bool = false
    private var pendingJitsiParameters: JitsiParameters?
    
    @Published var isInCall: Bool = false
    @Published var currentCall: CallInfo?
    @Published var currentCallState: CallState = .idle
    
    enum CallState {
        case idle
        case incoming
        case connected
        case ended
    }
    
    struct CallInfo {
        let phoneNumber: String
        let displayName: String
        let callType: String
        let roomId: String?
        let callHistoryId: Int?
        let conferenceUrl: String?
        let scriptId: Int?
        let clinicSlug: String?
        let scriptUUID: String?
        let clinicName: String?
        let roomName: String?
    }
    
    override init() {
        super.init()
        setupCallKit()
    }
    
    // MARK: - Setup
    
    private func setupCallKit() {
        print("🔧 CallKitManager: Setting up CallKit...")
        let configuration = CXProviderConfiguration(localizedName: "CosmeticTech")
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber]
        
        callProvider = CXProvider(configuration: configuration)
        callProvider?.setDelegate(self, queue: nil)
        
        callController = CXCallController()
        
        print("✅ CallKitManager: CallKit setup completed")
        print("   📞 Provider: \(callProvider != nil ? "✅" : "❌")")
        print("   🎮 Controller: \(callController != nil ? "✅" : "❌")")
        
        // Verify provider is properly configured
        if let provider = callProvider {
            print("   🔍 Provider configuration verified")
        } else {
            print("   ❌ CRITICAL: CallKit provider is nil!")
        }
    }
    
    // MARK: - Public Methods
    
    /// Start an incoming call
    func startIncomingCall(
        phoneNumber: String,
        displayName: String,
        callType: String = "video",
        roomId: String? = nil,
        callHistoryId: Int? = nil,
        conferenceUrl: String? = nil,
        roomName: String? = nil,
        scriptId: Int? = nil,
        clinicSlug: String? = nil,
        scriptUUID: String? = nil,
        clinicName: String? = nil,
        completion: ((Error?) -> Void)? = nil
    ) {
        print("📞 CallKitManager: Starting incoming call from \(displayName) (\(phoneNumber))")
        print("📞 CallKitManager: Provider exists: \(callProvider != nil ? "✅" : "❌")")
        print("📞 CallKitManager: Controller exists: \(callController != nil ? "✅" : "❌")")
        
        guard let provider = callProvider else {
            print("❌ CallKitManager: No provider available, cannot start call")
            completion?(NSError(domain: "CallKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "CallKit provider not available"]))
            return
        }
        
        let callUUID = UUID()
        currentCallUUID = callUUID
        
        let callInfo = CallInfo(
            phoneNumber: phoneNumber,
            displayName: displayName,
            callType: callType,
            roomId: roomId,
            callHistoryId: callHistoryId,
            conferenceUrl: conferenceUrl,
            scriptId: scriptId,
            clinicSlug: clinicSlug,
            scriptUUID: scriptUUID,
            clinicName: clinicName,
            roomName: roomName
        )
        
        currentCall = callInfo
        
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
        update.localizedCallerName = displayName
        update.hasVideo = (callType == "video")
        
        print("📞 CallKitManager: About to report call to CallKit provider")
        print("   📞 Call UUID: \(callUUID)")
        print("   📞 Provider exists: \(provider != nil)")
        
        provider.reportNewIncomingCall(with: callUUID, update: update) { error in
            print("📞 CallKitManager: CallKit reportNewIncomingCall completion called")
            if let error = error {
                print("❌ CallKitManager: Failed to report incoming call: \(error)")
                print("❌ CallKitManager: Error details: \(error.localizedDescription)")
                self.currentCallUUID = nil
                self.currentCall = nil
                self.isInCall = false
                self.currentCallState = .idle
            } else {
                print("✅ CallKitManager: Incoming call reported successfully")
                print("✅ CallKitManager: Call UUID: \(callUUID)")
                print("✅ CallKitManager: Caller: \(displayName) (\(phoneNumber))")
                print("✅ CallKitManager: Has video: \(update.hasVideo)")
                self.isInCall = true
                self.currentCallState = .incoming
                
                // Notify VoIPPushHandler that call is ringing
                VoIPPushHandler.shared.setCallState(isInCall: true, isRinging: true)
            }
            print("📞 CallKitManager: Calling completion handler")
            completion?(error)
        }
    }
    
    /// End the current call
    func endCall() {
        guard let callUUID = currentCallUUID else {
            print("⚠️ CallKitManager: No active call to end")
            return
        }
        
        print("📞 CallKitManager: Ending call")
        
        let endCallAction = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction(action: endCallAction)
        
        callController?.request(transaction) { error in
            if let error = error {
                print("❌ CallKitManager: Failed to end call: \(error)")
            } else {
                print("✅ CallKitManager: Call ended successfully")
                // Reset all call state
                self.currentCallUUID = nil
                self.currentCall = nil
                self.isInCall = false
                self.currentCallState = .ended
            }
        }
    }
    
    /// End call from Jitsi meeting (when user ends the meeting)
    func endCallFromJitsi() {
        print("📞 CallKitManager: Ending call from Jitsi meeting")
        
        // Reset all call state since CallKit session was already ended
        currentCallUUID = nil
        currentCall = nil
        isInCall = false
        currentCallState = .ended
        
        // Post notification that call ended
        NotificationCenter.default.post(name: .VoIPCallDidEnd, object: nil)
    }
    
    /// Clear call data after queue removal is complete
    func clearCallData() {
        print("📞 CallKitManager: Clearing call data after queue removal")
        currentCall = nil
        pendingJitsiParameters = nil
    }
    
    /// Check for pending Jitsi presentation when app becomes active
    func presentPendingJitsiIfNeeded() {
        guard let jitsiParameters = pendingJitsiParameters else {
            print("🎥 CallKitManager: No pending Jitsi presentation")
            return
        }
        
        print("🎥 CallKitManager: Presenting pending Jitsi meeting")
        print("   - Room: \(jitsiParameters.roomName)")
        print("   - Display Name: \(jitsiParameters.displayName)")
        
        // Use global Jitsi manager to present the meeting
        DispatchQueue.main.async {
            GlobalJitsiManager.shared.presentJitsi(with: jitsiParameters)
        }
        
        // Clear pending parameters
        pendingJitsiParameters = nil
    }
    
    
    /// Trigger Jitsi meeting for accepted call
    private func triggerJitsiMeeting(for call: CallInfo) {
        // Resolve room name using the same logic as home screen
        let roomName = resolveRoomNameForCall(call)
        
        // Create Jitsi parameters from call info
        // Always use the standard video-chat server, not the conference_url from payload
        let jitsiParameters = JitsiParameters(
            roomName: roomName,
            displayName: call.displayName,
            email: nil, // Could be extracted from user data if needed
            conferenceUrl: EnvironmentManager.shared.currentJitsiURL,
            roomId: roomName,
            clinicSlug: call.clinicSlug,
            scriptId: call.scriptId,
            scriptUUID: call.scriptUUID,
            clinicName: call.clinicName
        )
        
        // Store pending Jitsi parameters for when app becomes active
        pendingJitsiParameters = jitsiParameters
        
        // Use global Jitsi manager to present the meeting
        DispatchQueue.main.async {
            GlobalJitsiManager.shared.presentJitsi(with: jitsiParameters)
        }
        
        print("🎥 CallKitManager: Triggered Jitsi meeting presentation")
        print("   - Room: \(jitsiParameters.roomName)")
        print("   - Display Name: \(jitsiParameters.displayName)")
        print("   - Conference URL: \(jitsiParameters.conferenceUrl)")
        
        // CRITICAL: End the CallKit session when Jitsi meeting starts
        // This prevents conflicts between CallKit and Jitsi audio sessions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🎥 CallKitManager: Ending CallKit session to transition to Jitsi")
            self.endCallKitSession()
            
            // Transition to Jitsi audio session
            AudioService.shared.transitionToJitsiAudioSession()
        }
    }
    
    /// End the CallKit session while preserving call state for Jitsi
    private func endCallKitSession() {
        guard let callUUID = currentCallUUID else {
            print("⚠️ CallKitManager: No active CallKit session to end")
            return
        }
        
        print("📞 CallKitManager: Ending CallKit session for Jitsi transition")
        
        let endCallAction = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction(action: endCallAction)
        
        // Mark that this end is part of Jitsi transition so the delegate doesn't treat it as a rejection
        isEndingForJitsiTransition = true

        callController?.request(transaction) { error in
            if let error = error {
                print("❌ CallKitManager: Failed to end CallKit session: \(error)")
                self.isEndingForJitsiTransition = false
            } else {
                print("✅ CallKitManager: CallKit session ended successfully")
                // Delegate callback will handle state updates; avoid double-posting or clearing here
            }
        }
    }
    
    /// Resolves room name using the same logic as home screen
    /// This ensures consistency between VoIP calls and home screen call back
    private func resolveRoomNameForCall(_ call: CallInfo) -> String {
        // Priority 1: Use room_name if available
        if let roomName = call.roomName, !roomName.isEmpty {
            print("🎥 Using room_name from call: \(roomName)")
            return roomName
        }

        // Priority 2: Use room_id if available
        if let roomId = call.roomId, !roomId.isEmpty {
            print("🎥 Using room_id from call: \(roomId)")
            return roomId
        }

        // Priority 3: Use script_uuid if available
        if let scriptUUID = call.scriptUUID, !scriptUUID.isEmpty {
            print("🎥 Using script_uuid from call: \(scriptUUID)")
            return scriptUUID
        }

        // Priority 4: Use script_id as fallback
        if let scriptId = call.scriptId {
            let fallback = "script_\(scriptId)"
            print("🎥 Using script_id as fallback room: \(fallback)")
            return fallback
        }

        // Priority 5: Use phone number as last resort
        let fallback = call.phoneNumber
        print("🎥 Using phone number as room fallback: \(fallback)")
        return fallback
    }
    
    /// Report call action to API
    private func reportCallAction(_ action: CallAction) {
        guard let call = currentCall,
              let scriptId = call.scriptId,
              let clinicSlug = call.clinicSlug else {
            print("⚠️ CallKitManager: Cannot report call action - missing required parameters")
            print("   - Script ID: \(currentCall?.scriptId?.description ?? "nil")")
            print("   - Clinic Slug: \(currentCall?.clinicSlug ?? "nil")")
            return
        }
        
        print("📞 CallKitManager: Reporting call action to API: \(action.rawValue)")
        
        Task {
            do {
                let callActionService = CallActionAPIService()
                let _ = try await callActionService.reportCallAction(
                    scriptId: scriptId,
                    clinicSlug: clinicSlug,
                    scriptUUID: call.scriptUUID,
                    action: action
                )
                print("✅ CallKitManager: Call action reported successfully")
            } catch {
                print("❌ CallKitManager: Failed to report call action: \(error)")
                // Don't fail the call action if API reporting fails
            }
        }
    }
    
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("📞 CallKitManager: Answer call action")
        action.fulfill()
        
        // Update call state
        currentCallState = .connected
        
        // Reset ringing state
        VoIPPushHandler.shared.setCallState(isInCall: true, isRinging: false)
        
        // Report call action to API
        reportCallAction(.accepted)
        
        // Post notification that call was accepted
        NotificationCenter.default.post(name: .VoIPCallAccepted, object: nil)
        
        // Trigger Jitsi meeting if we have call info
        if let call = currentCall {
            print("🎥 CallKitManager: Triggering Jitsi meeting for accepted call")
            triggerJitsiMeeting(for: call)
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("📞 CallKitManager: End call action")
        action.fulfill()

        if isEndingForJitsiTransition {
            // This end was initiated to hand off to Jitsi – do NOT report as rejected or clear call info
            print("🎥 CallKitManager: End due to Jitsi transition – preserving call info")
            isEndingForJitsiTransition = false
            currentCallUUID = nil
            isInCall = false
            currentCallState = .ended
            // Do not post VoIPCallDidEnd here; Jitsi flow will manage lifecycle
            return
        }

        // Normal end: report as rejected/ended BEFORE clearing state
        // This ensures we have the call data when reporting the action
        if currentCall != nil {
            reportCallAction(.rejected)
        }
        
        // Clear state after reporting
        currentCallUUID = nil
        currentCall = nil
        isInCall = false
        currentCallState = .ended
        
        // Reset VoIPPushHandler call state
        VoIPPushHandler.shared.setCallState(isInCall: false, isRinging: false)
        
        NotificationCenter.default.post(name: .VoIPCallDidEnd, object: nil)
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        print("📞 CallKitManager: Set held call action")
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("📞 CallKitManager: Set muted call action")
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
        print("📞 CallKitManager: Set group call action")
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        print("📞 CallKitManager: Play DTMF call action")
        action.fulfill()
    }
    
    func providerDidReset(_ provider: CXProvider) {
        print("📞 CallKitManager: Provider did reset")
        currentCallUUID = nil
        currentCall = nil
        isInCall = false
        currentCallState = .idle
        
        // Reset VoIPPushHandler call state
        VoIPPushHandler.shared.setCallState(isInCall: false, isRinging: false)
    }
}

