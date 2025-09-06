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
    }
    
    override init() {
        super.init()
        setupCallKit()
    }
    
    // MARK: - Setup
    
    private func setupCallKit() {
        let configuration = CXProviderConfiguration(localizedName: "CosmeticTech")
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        
        callProvider = CXProvider(configuration: configuration)
        callProvider?.setDelegate(self, queue: nil)
        
        callController = CXCallController()
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
        completion: ((Error?) -> Void)? = nil
    ) {
        print("📞 CallKitManager: Starting incoming call from \(displayName) (\(phoneNumber))")
        
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
            clinicSlug: clinicSlug
        )
        
        currentCall = callInfo
        
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: phoneNumber)
        update.localizedCallerName = displayName
        update.hasVideo = (callType == "video")
        
        callProvider?.reportNewIncomingCall(with: callUUID, update: update) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ CallKitManager: Failed to report incoming call: \(error)")
                    self.currentCallUUID = nil
                    self.currentCall = nil
                    self.currentCallState = .idle
                } else {
                    print("✅ CallKitManager: Incoming call reported successfully")
                    self.isInCall = true
                    self.currentCallState = .incoming
                }
                completion?(error)
            }
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
            }
        }
    }
    
    /// Accept the current call
    func acceptCall() {
        guard let callUUID = currentCallUUID else {
            print("⚠️ CallKitManager: No active call to accept")
            return
        }
        
        print("📞 CallKitManager: Accepting call")
        
        let answerAction = CXAnswerCallAction(call: callUUID)
        let transaction = CXTransaction(action: answerAction)
        
        callController?.request(transaction) { error in
            if let error = error {
                print("❌ CallKitManager: Failed to accept call: \(error)")
            } else {
                print("✅ CallKitManager: Call accepted successfully")
                // Post notification that call was accepted
                NotificationCenter.default.post(name: .VoIPCallAccepted, object: nil)
                
                // Trigger Jitsi meeting if we have call info
                if let call = self.currentCall {
                    print("🎥 CallKitManager: Triggering Jitsi meeting for accepted call")
                    self.triggerJitsiMeeting(for: call)
                }
            }
        }
    }
    
    /// Reject the current call
    func rejectCall() {
        guard let callUUID = currentCallUUID else {
            print("⚠️ CallKitManager: No active call to reject")
            return
        }
        
        print("📞 CallKitManager: Rejecting call")
        
        let endCallAction = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction(action: endCallAction)
        
        callController?.request(transaction) { error in
            if let error = error {
                print("❌ CallKitManager: Failed to reject call: \(error)")
            } else {
                print("✅ CallKitManager: Call rejected successfully")
                // Post notification that call ended
                NotificationCenter.default.post(name: .VoIPCallDidEnd, object: nil)
            }
        }
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
            conferenceUrl: "https://video-chat.cosmeticcloud.tech",
            roomId: roomName,
            clinicSlug: call.clinicSlug,
            scriptId: call.scriptId
        )
        
        // Post notification to trigger Jitsi presentation
        NotificationCenter.default.post(
            name: NSNotification.Name("PresentJitsiFromCallKit"),
            object: nil,
            userInfo: ["jitsiParameters": jitsiParameters]
        )
        
        print("🎥 CallKitManager: Posted PresentJitsiFromCallKit notification")
        print("   - Room: \(jitsiParameters.roomName)")
        print("   - Display Name: \(jitsiParameters.displayName)")
        print("   - Conference URL: \(jitsiParameters.conferenceUrl)")
    }
    
    /// Resolves room name using the same logic as home screen
    /// This ensures consistency between VoIP calls and home screen call back
    private func resolveRoomNameForCall(_ call: CallInfo) -> String {
        // Priority 1: Use roomId if available and not empty
        if let roomId = call.roomId, !roomId.isEmpty {
            print("🎥 Using roomId from call: \(roomId)")
            return roomId
        }
        
        // Priority 2: Use scriptId if available
        if let scriptId = call.scriptId {
            let fallback = "script_\(scriptId)"
            print("🎥 Using scriptId as room: \(fallback)")
            return fallback
        }
        
        // Priority 3: Use phone number as fallback
        let fallback = call.phoneNumber
        print("🎥 Using phone number as room: \(fallback)")
        return fallback
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("📞 CallKitManager: Answer call action")
        action.fulfill()
        
        // Update call state
        currentCallState = .connected
        
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
        
        // Reset state
        currentCallUUID = nil
        currentCall = nil
        isInCall = false
        currentCallState = .ended
        
        // Post notification that call ended
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
    }
}

