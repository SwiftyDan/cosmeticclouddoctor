//
//  CallManager.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import Foundation
import CallKit
import AVFoundation

@MainActor
class CallManager: NSObject, ObservableObject {
    static let shared = CallManager()
    
    private let callController = CXCallController()
    private let provider: CXProvider
    private let callUpdate = CXCallUpdate()
    private let audioService = AudioService.shared
    
    @Published var isIncomingCall = false
    @Published var currentCallUUID: UUID?
    
    override init() {
        let providerConfiguration = CXProviderConfiguration(localizedName: "CosmeticTechMobile")
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallGroups = 1
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.phoneNumber, .generic]
        
        provider = CXProvider(configuration: providerConfiguration)
        
        super.init()
        provider.setDelegate(self, queue: nil)
    }
    
    func startIncomingCall(phoneNumber: String, displayName: String = "Unknown") {
        let uuid = UUID()
        currentCallUUID = uuid
        
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: phoneNumber)
        update.hasVideo = false
        update.localizedCallerName = displayName
        
        // Start playing incoming call sound
        audioService.playIncomingCallSound()
        
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                print("Failed to report incoming call: \(error.localizedDescription)")
                // Stop sound if call reporting fails
                self.audioService.stopIncomingCallSound()
            } else {
                DispatchQueue.main.async {
                    self.isIncomingCall = true
                }
            }
        }
    }
    
    func endCall() {
        guard let uuid = currentCallUUID else { return }
        
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("Failed to end call: \(error.localizedDescription)")
            } else {
                // Stop all sounds and play end call sound
                self.audioService.stopAllSounds()
                self.audioService.playCallEndedSound()
                
                DispatchQueue.main.async {
                    self.isIncomingCall = false
                    self.currentCallUUID = nil
                }
            }
        }
    }
    
    func answerCall() {
        guard let uuid = currentCallUUID else { return }
        
        let answerAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: answerAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("Failed to answer call: \(error.localizedDescription)")
            } else {
                // Stop incoming call sound and play connection sound
                self.audioService.stopIncomingCallSound()
                self.audioService.playCallConnectedSound()
                
                DispatchQueue.main.async {
                    self.isIncomingCall = false
                }
            }
        }
    }
}

// MARK: - CXProviderDelegate
extension CallManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        // Stop all sounds when provider resets
        audioService.stopAllSounds()
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()
        
        // Stop incoming call sound and play connection sound
        audioService.stopIncomingCallSound()
        audioService.playCallConnectedSound()
        
        DispatchQueue.main.async {
            self.isIncomingCall = false
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        
        // Stop all sounds and play end call sound
        audioService.stopAllSounds()
        audioService.playCallEndedSound()
        
        DispatchQueue.main.async {
            self.isIncomingCall = false
            self.currentCallUUID = nil
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }
} 