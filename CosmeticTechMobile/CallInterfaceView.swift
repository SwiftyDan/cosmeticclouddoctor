//
//  CallInterfaceView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import SwiftUI
import AVFAudio

struct CallInterfaceView: View {
    @ObservedObject var callKitManager: CallKitManager
    @ObservedObject var audioService = AudioService.shared
    let phoneNumber: String
    let displayName: String
    
    @State private var showAcceptedMessage = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.8), Color.black]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Caller info
                VStack(spacing: 20) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 8) {
                        Text(displayName)
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text(phoneNumber)
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Call status
                Text(statusText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.bottom, 20)
                
                // Sound status indicator
                if audioService.isPlayingRingtone {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text("Playing ringtone...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.bottom, 10)
                }
                
                // Action buttons
                if callKitManager.currentCallState == .incoming {
                    HStack(spacing: 60) {
                        // Decline button
                        Button(action: {
                            callKitManager.endCall()
                        }) {
                            VStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 70, height: 70)
                                    
                                    Image(systemName: "phone.down.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                                
                                Text("Decline")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.top, 8)
                            }
                        }
                        
                        // Answer button
                        Button(action: {
                            callKitManager.acceptCall()
                            showAcceptedMessage = true
                        }) {
                            VStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 70, height: 70)
                                    
                                    Image(systemName: "phone.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                                
                                Text("Answer")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.top, 8)
                            }
                        }
                    }
                } else if showAcceptedMessage {
                    // Show brief "Call Accepted" message
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Call Accepted")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("Opening web content...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                    .frame(height: 100)
            }
        }
        .onReceive(callKitManager.$currentCallState) { newState in
            if newState == .ended {
                showAcceptedMessage = false
            }
        }
    }
    
    private var statusText: String {
        switch callKitManager.currentCallState {
        case .idle:
            return "Call Ended"
        case .incoming:
            return "Incoming Call..."
        case .connected:
            return "Call Accepted"
        case .ended:
            return "Call Ended"
        }
    }
}

#Preview {
    CallInterfaceView(
        callKitManager: CallKitManager.shared,
        phoneNumber: "+1 (555) 123-4567",
        displayName: "John Doe"
    )
} 
