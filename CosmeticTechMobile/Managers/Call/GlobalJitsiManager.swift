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
    private var isDismissing = false
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    /// Present Jitsi meeting with given parameters
    func presentJitsi(with parameters: JitsiParameters) {
        // Ensure we're on the main thread for all UI updates
        DispatchQueue.main.async {
            print("🎥 GlobalJitsiManager: Presenting Jitsi meeting")
            print("   - Room: \(parameters.roomName)")
            print("   - Display Name: \(parameters.displayName ?? "nil")")
            print("   - Conference URL: \(parameters.conferenceUrl ?? "nil")")
            
            self.jitsiParameters = parameters
            self.isPresentingJitsi = true
        }
    }
    
    /// Dismiss Jitsi meeting
    func dismissJitsi() {
        // Ensure we're on the main thread for all UI updates
        DispatchQueue.main.async {
            guard self.isPresentingJitsi else {
                print("🎥 GlobalJitsiManager: No Jitsi meeting to dismiss")
                return
            }
            
            print("🎥 GlobalJitsiManager: Dismissing Jitsi meeting")
            self.isPresentingJitsi = false
            self.jitsiParameters = nil
            
            // Reset dismissal flag after a short delay to allow for proper cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isDismissing = false
            }
            
            // Note: We don't post VoIPCallDidEnd notification here because
            // this method is used for both VoIP calls and call back button calls
            // The VoIPCallDidEnd notification should only be posted by VoIP-specific flows
        }
    }
    
    /// Dismiss Jitsi meeting from VoIP call (posts VoIPCallDidEnd notification)
    func dismissJitsiFromVoIP() {
        // Ensure we're on the main thread for all UI updates
        DispatchQueue.main.async {
            print("🎥 GlobalJitsiManager: Dismissing Jitsi meeting from VoIP call")
            self.dismissJitsi()
            
            // Notify VoIP push handler that Jitsi meeting has ended
            // This allows new VoIP calls to be processed normally
            NotificationCenter.default.post(name: .VoIPCallDidEnd, object: nil)
        }
    }
    
    /// End call and dismiss Jitsi meeting
    func endCall() {
        // Prevent multiple simultaneous end call attempts
        guard !isDismissing else {
            print("🎥 GlobalJitsiManager: End call already in progress, ignoring duplicate call")
            return
        }
        
        print("🎥 GlobalJitsiManager: Ending call and dismissing Jitsi meeting")
        print("🎥 GlobalJitsiManager: Current app state: \(UIApplication.shared.applicationState.rawValue)")
        print("🎥 GlobalJitsiManager: isPresentingJitsi: \(isPresentingJitsi)")
        print("🎥 GlobalJitsiManager: isDismissing: \(isDismissing)")
        
        // Set dismissing flag immediately to prevent race conditions
        isDismissing = true
        
        // Set isPresentingJitsi to false immediately to ensure SwiftUI dismisses the fullScreenCover
        isPresentingJitsi = false
        
        // Ensure we're on the main thread for all UI updates
        DispatchQueue.main.async {
            // End the CallKit session properly
            print("🎥 GlobalJitsiManager: Calling CallKitManager.shared.endCallFromJitsi()")
            CallKitManager.shared.endCallFromJitsi()
            
            // Clear parameters
            self.jitsiParameters = nil
            
            // Reset dismissal flag after a short delay to allow for proper cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isDismissing = false
            }
            
            print("🎥 GlobalJitsiManager: End call completed")
        }
    }
    
    // MARK: - Clear State (for logout)
    
    /// Clears all Jitsi meeting state (used during logout)
    func clearJitsiState() {
        print("🗑️ GlobalJitsiManager: Clearing Jitsi state")
        isPresentingJitsi = false
        jitsiParameters = nil
        isDismissing = false
        print("✅ GlobalJitsiManager: Jitsi state cleared")
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
