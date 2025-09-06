//
//  JitsiMeetViewWrapper.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import SwiftUI
import UIKit
import JitsiMeetSDK
import AVFoundation

// Import AudioService for call audio session management
import Foundation

// MARK: - Jitsi Meet View Wrapper
struct JitsiMeetViewWrapper: UIViewRepresentable {
    let roomName: String
    let displayName: String?
    let email: String?
    let conferenceUrl: String?
    let roomId: String?
    let onConferenceJoined: (() -> Void)?
    let onConferenceTerminated: (() -> Void)?
    let onConferenceFailed: ((Error) -> Void)?
    let onEndCall: (() -> Void)?
    let isModerator: Bool
    
    init(
        roomName: String,
        displayName: String? = nil,
        email: String? = nil,
        conferenceUrl: String? = nil,
        roomId: String? = nil,
        isModerator: Bool = false,
        onConferenceJoined: (() -> Void)? = nil,
        onConferenceTerminated: (() -> Void)? = nil,
        onConferenceFailed: ((Error) -> Void)? = nil,
        onEndCall: (() -> Void)? = nil
    ) {
        self.roomName = roomName
        self.displayName = displayName
        self.email = email
        self.conferenceUrl = conferenceUrl
        self.roomId = roomId
        self.isModerator = isModerator
        self.onConferenceJoined = onConferenceJoined
        self.onConferenceTerminated = onConferenceTerminated
        self.onConferenceFailed = onConferenceFailed
        self.onEndCall = onEndCall
    }
    
    func makeUIView(context: Context) -> UIView {
        let jitsiMeetView = JitsiMeetView()
        jitsiMeetView.delegate = context.coordinator
        
        // Request camera permission before starting Jitsi
        requestCameraPermission { [weak jitsiMeetView] in
            DispatchQueue.main.async {
                // Activate call audio session for proper voice call audio
                AudioService.shared.activateCallAudioSession()
                
                // Log audio session status for debugging
                AudioService.shared.logAudioSessionStatus()
                
                // Configure and join conference after permissions are granted
                self.configureAndJoinConference(jitsiMeetView: jitsiMeetView)
            }
        }
        
        return jitsiMeetView
    }
    
    private func configureAndJoinConference(jitsiMeetView: JitsiMeetView?) {
        guard let jitsiMeetView = jitsiMeetView else { return }
        
        // Configure Jitsi Meet options
        let options = JitsiMeetConferenceOptions.fromBuilder { builder in
            builder.room = roomName
            builder.userInfo = JitsiMeetUserInfo(displayName: displayName ?? "User", andEmail: email, andAvatar: URL(string: ""))
            builder.serverURL = URL(string: conferenceUrl ?? "https://meet.jit.si")
            
            // Disable prejoin page and welcome page for VoIP calls
            builder.setConfigOverride("prejoinPageEnabled", withValue: false)
            builder.setConfigOverride("welcomePageEnabled", withValue: false)
            
            // Additional prejoin-related settings
            builder.setConfigOverride("disablePrejoinPage", withValue: true)
            builder.setConfigOverride("skipPrejoinButton", withValue: true)
            
            // iOS-specific features
            // Note: Some iOS-specific properties may not be available in this version of Jitsi Meet SDK
        }
        
        // Join the conference
        jitsiMeetView.join(options)
    }
    
    private func requestCameraPermission(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("📹 Camera permission already granted")
            completion()
        case .notDetermined:
            print("📹 Requesting camera permission...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("📹 Camera permission granted")
                    } else {
                        print("📹 Camera permission denied")
                    }
                    completion()
                }
            }
        case .denied, .restricted:
            print("📹 Camera permission denied or restricted")
            completion()
        @unknown default:
            print("📹 Camera permission unknown status")
            completion()
        }
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Clean up Jitsi Meet view
        if let jitsiView = uiView as? JitsiMeetView {
            jitsiView.leave()
        }
        // Deactivate call audio session when view is dismantled
        DispatchQueue.main.async {
            AudioService.shared.deactivateCallAudioSession()
        }
        
        // Only trigger queue removal if user intentionally ended the call
        // This prevents queue removal when switching tabs or going to background
        if coordinator.isUserEndingCall {
            print("🎥 Wrapper view dismantled - user ended call, triggering queue removal")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .jitsiConferenceTerminated, object: nil)
            }
        } else {
            print("🎥 Wrapper view dismantled - not user-initiated, skipping queue removal")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, JitsiMeetViewDelegate {
        let parent: JitsiMeetViewWrapper
        var isUserEndingCall = false // Track if user intentionally ended the call
        
        init(_ parent: JitsiMeetViewWrapper) {
            self.parent = parent
        }
        
        // MARK: - JitsiMeetViewDelegate
        func conferenceJoined(_ data: [AnyHashable : Any]!) {
            print("🎥 Jitsi conference joined")
            parent.onConferenceJoined?()
            
            // Post notification that Jitsi conference has started
            // This allows CallKitManager to reset the accepting call flag
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("JitsiConferenceStarted"), object: nil)
            }
        }
        
        func conferenceTerminated(_ data: [AnyHashable : Any]!) {
            print("🎥 Jitsi conference terminated")
            // Mark that user intentionally ended the call
            isUserEndingCall = true
            
            // Deactivate call audio session when meeting ends
            DispatchQueue.main.async {
                AudioService.shared.deactivateCallAudioSession()
            }
            parent.onConferenceTerminated?()
            
            // Trigger queue list API refresh when meeting ends
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .jitsiConferenceTerminated, object: nil)
            }
        }
        
        func conferenceWillJoin(_ data: [AnyHashable : Any]!) {
            print("🎥 Jitsi conference will join")
        }
        
        func conferenceWillTerminate(_ data: [AnyHashable : Any]!) {
            print("🎥 Jitsi conference will terminate")
            // Mark that user intentionally ended the call
            isUserEndingCall = true
            
            // Deactivate call audio session when meeting is about to end
            DispatchQueue.main.async {
                AudioService.shared.deactivateCallAudioSession()
            }
            // Trigger the onEndCall callback to handle queue item removal
            if let onEndCall = parent.onEndCall {
                print("🎥 Native end call button pressed, triggering onEndCall callback")
                DispatchQueue.main.async {
                    onEndCall()
                }
            }
            
            // Trigger queue list API refresh when meeting is about to end
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .jitsiConferenceTerminated, object: nil)
            }
        }
        
        func enterPicture(inPicture data: [AnyHashable : Any]!) {
            print("🎥 Entered picture in picture mode")
        }
        
        func exitPicture(inPicture data: [AnyHashable : Any]!) {
            print("🎥 Exited picture in picture mode")
        }
        
        func participantJoined(_ data: [AnyHashable : Any]!) {
            print("🎥 Participant joined")
        }
        
        func participantLeft(_ data: [AnyHashable : Any]!) {
            print("🎥 Participant left")
        }
        
        func audioMutedChanged(_ data: [AnyHashable : Any]!) {
            print("🎥 Audio muted changed")
        }
        
        func videoMutedChanged(_ data: [AnyHashable : Any]!) {
            print("🎥 Video muted changed")
        }
        
        func endpointTextMessageReceived(_ data: [AnyHashable : Any]!) {
            print("🎥 Endpoint text message received")
        }
        
        func screenShareToggled(_ data: [AnyHashable : Any]!) {
            print("🎥 Screen share toggled")
        }
        
        func chatMessageReceived(_ data: [AnyHashable : Any]!) {
            print("🎥 Chat message received")
        }
        
        func chatToggled(_ data: [AnyHashable : Any]!) {
            print("🎥 Chat toggled")
        }
        
        func participantsInfoRetrieved(_ data: [AnyHashable : Any]!) {
            print("🎥 Participants info retrieved")
        }
        
        func openSettings(_ data: [AnyHashable : Any]!) {
            print("🎥 Open settings")
        }
        
        func raiseHandUpdated(_ data: [AnyHashable : Any]!) {
            print("🎥 Raise hand updated")
        }
        
        func recordingStatusChanged(_ data: [AnyHashable : Any]!) {
            print("🎥 Recording status changed")
        }
        
        func liveStreamingStatusChanged(_ data: [AnyHashable : Any]!) {
            print("🎥 Live streaming status changed")
        }
        
        func error(_ data: [AnyHashable : Any]!) {
            print("🎥 Jitsi error: \(String(describing: data))")
            if let error = data["error"] as? Error {
                parent.onConferenceFailed?(error)
            } else {
                let customError = NSError(domain: "JitsiMeet", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown Jitsi error"])
                parent.onConferenceFailed?(customError)
            }
        }
    }
}

// MARK: - Mock Consult Form Overlay (for demo during meeting)
struct ConsultFormOverlayView: View {
    struct Field: Identifiable { let id = UUID(); let name: String; let value: String }
    let fields: [Field]
    let patientSignatureURL: URL?
    let nurseSignatureURL: URL?
    let scriptProducts: String?
    var showsButtons: Bool = true
    var isAccepting: Bool = false
    var isRejecting: Bool = false
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Consultation Details")
                .font(.title3).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.primary)

            // Clean form style list (no container)
            VStack(spacing: 8) {
                ForEach(fields) { f in
                    HStack(alignment: .top, spacing: 12) {
                        Text(f.name)
                            .foregroundColor(.secondary)
                            .frame(width: 150, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(f.value)
                            .font(.body)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }

                // Script Products section (if available)
                if let scriptProducts = scriptProducts, !scriptProducts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Script Products")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HTMLContentView(
                            htmlContent: scriptProducts,
                            title: "",
                            height: 200
                        )
                    }
                    .padding(.vertical, 6)
                    Divider()
                }

                if let patientSignatureURL {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Patient Signature")
                            .foregroundColor(.secondary)
                            .frame(width: 150, alignment: .leading)
                        AsyncImage(url: patientSignatureURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { ProgressView() }
                        .frame(height: 120)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }

                if let nurseSignatureURL {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Administering Nurse")
                            .foregroundColor(.secondary)
                            .frame(width: 150, alignment: .leading)
                        AsyncImage(url: nurseSignatureURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { ProgressView() }
                        .frame(height: 120)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    }
                    .padding(.vertical, 6)
                }
            }

            if showsButtons {
                HStack(spacing: 12) {
                    Button(action: onAccept) {
                        HStack(spacing: 8) {
                            if isAccepting { ProgressView().scaleEffect(0.8) }
                            Text(isAccepting ? "Accepting..." : "Accept")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isAccepting || isRejecting)

                    Button(action: onReject) {
                        HStack(spacing: 8) {
                            if isRejecting { ProgressView().scaleEffect(0.8) }
                            Text(isRejecting ? "Rejecting..." : "Reject")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isAccepting || isRejecting)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview with mock data
#Preview {
    ScrollView {
        ConsultFormOverlayView(
            fields: [
                .init(name: "Do you need to talk\nto the doctor?", value: "Yes"),
                .init(name: "Patient", value: "Jocelyn Levy"),
                .init(name: "Date of birth", value: "1981-03-02"),
                .init(name: "Doctor", value: "Asaph Amador"),
                .init(name: "Nurse", value: "Alana Jensen"),
                .init(name: "Medical\nconsultation", value: "2025-08-13"),
                .init(name: "Patient Consent to\nPhotographs", value: "Yes"),
                .init(name: "Patient Consent to\nTreatment", value: "Yes")
            ],
            patientSignatureURL: URL(string: "https://example.com/patient-signature.png"),
            nurseSignatureURL: URL(string: "https://example.com/nurse-signature.png"),
            scriptProducts: """
                <h3>Treatment Plan</h3>
                <p><strong>Primary Treatment:</strong> Botox injection for forehead lines</p>
                <ul>
                    <li>Dosage: 20 units</li>
                    <li>Areas: Frontalis muscle</li>
                    <li>Expected results: 3-4 months</li>
                </ul>
                <p><em>Note: Patient has no contraindications</em></p>
                """,
            showsButtons: true,
            isAccepting: false,
            isRejecting: false,
            onAccept: {},
            onReject: {}
        )
    }
}

