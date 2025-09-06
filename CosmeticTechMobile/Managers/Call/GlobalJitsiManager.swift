//
//  GlobalJitsiManager.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import SwiftUI
import Combine

/// Global manager for Jitsi meeting presentation across the entire app
/// This ensures Jitsi meetings can be presented even when the app launches from CallKit
@MainActor
class GlobalJitsiManager: ObservableObject {
    static let shared = GlobalJitsiManager()
    
    // MARK: - Published Properties
    @Published var isPresentingJitsi: Bool = false
    @Published var jitsiParameters: JitsiParameters?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    /// Present Jitsi meeting with given parameters
    func presentJitsi(with parameters: JitsiParameters) {
        print("🎥 GlobalJitsiManager: Presenting Jitsi meeting")
        print("   - Room: \(parameters.roomName)")
        print("   - Display Name: \(parameters.displayName ?? "nil")")
        print("   - Conference URL: \(parameters.conferenceUrl ?? "nil")")
        
        jitsiParameters = parameters
        isPresentingJitsi = true
    }
    
    /// Dismiss Jitsi meeting
    func dismissJitsi() {
        print("🎥 GlobalJitsiManager: Dismissing Jitsi meeting")
        isPresentingJitsi = false
        jitsiParameters = nil
        
        // Notify VoIP push handler that Jitsi meeting has ended
        // This allows new VoIP calls to be processed normally
        NotificationCenter.default.post(name: .VoIPCallDidEnd, object: nil)
    }
    
    /// End call and dismiss Jitsi meeting
    func endCall() {
        print("🎥 GlobalJitsiManager: Ending call and dismissing Jitsi meeting")
        
        // Clear call data from CallKitManager
        CallKitManager.shared.clearCallData()
        
        // Dismiss Jitsi meeting
        dismissJitsi()
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        // Listen for Jitsi presentation requests from CallKit
        NotificationCenter.default.publisher(for: NSNotification.Name("PresentJitsiFromCallKit"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                
                if let jitsiParameters = notification.userInfo?["jitsiParameters"] as? JitsiParameters {
                    print("🎥 GlobalJitsiManager: Received PresentJitsiFromCallKit notification")
                    self.presentJitsi(with: jitsiParameters)
                }
            }
            .store(in: &cancellables)
    }
}
