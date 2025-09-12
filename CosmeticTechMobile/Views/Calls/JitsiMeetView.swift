//
//  JitsiMeetView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/8/25.
//

import SwiftUI
import Combine
import JitsiMeetSDK
import AVFoundation

// Moved business logic to `ConsultationViewModel`

// MARK: - Jitsi Meet View
struct JitsiMeetConferenceView: View {
    let roomName: String
    let displayName: String?
    let email: String?
    let conferenceUrl: String? // Keep for backward compatibility but will be nil now
    let roomId: String? // Add roomId for server routing
    let clinicSlug: String?
    let scriptId: Int?
    let scriptUUID: String? // Add scriptUUID for queue removal
    let clinicName: String? // Add clinicName for queue removal
    let onEndCall: (() -> Void)? // New callback for ending the CallKit call
    
    @Environment(\.presentationMode) var presentationMode
    private let deviceService = DeviceOrientationService.shared
    
    init(roomName: String,
         displayName: String? = nil,
         email: String? = nil,
         conferenceUrl: String? = nil,
         roomId: String? = nil,
         clinicSlug: String? = nil,
         scriptId: Int? = nil,
         scriptUUID: String? = nil,
         clinicName: String? = nil,
         onEndCall: (() -> Void)? = nil) {
        self.roomName = roomName
        self.displayName = displayName
        self.email = email
        self.conferenceUrl = conferenceUrl
        self.roomId = roomId
        self.clinicSlug = clinicSlug
        self.scriptId = scriptId
        self.scriptUUID = scriptUUID
        self.clinicName = clinicName
        self.onEndCall = onEndCall
        
        print("🎥 JitsiMeetConferenceView initialized:")
        print("   - roomName: \(roomName)")
        print("   - clinicSlug: \(clinicSlug ?? "nil")")
        print("   - scriptId: \(scriptId?.description ?? "nil")")
    }
    
    @State private var isConferenceActive = false
    @State private var isConferenceStarting = true // Track if conference is starting
    @State private var isUserEndingCall = false // Track if user intentionally ended the call
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showConsultSheet = false
    @State private var hasSetInitialFabAnchor = false
    @State private var fabAnchor: CGPoint = .zero
    @GestureState private var fabDragTranslation: CGSize = .zero
    @State private var isDraggingFab: Bool = false
    @State private var loadingTimeoutTimer: Timer?
    
    // Determine if user is moderator based on role or email
    private var isModerator: Bool {
        // For now, assume all users are moderators
        // This can be enhanced later with role-based logic
        return true
    }
    
    private let reservedBottomSpace: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Background color for better dark mode support
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // Direct Jitsi Meet View - no wrapper needed
            DirectJitsiMeetView(
                roomName: roomName,
                displayName: displayName,
                email: email,
                conferenceUrl: conferenceUrl,
                scriptId: scriptId,
                clinicSlug: clinicSlug,
                scriptUUID: scriptUUID,
                clinicName: clinicName,
                onConferenceJoined: {
                    print("🎥 Conference joined - showing consultation button")
                    isConferenceActive = true
                    isConferenceStarting = false
                },
                onConferenceTerminated: {
                    isConferenceActive = false
                    isConferenceStarting = false
                    print("🎥 Conference terminated - calling onEndCall to dismiss meeting")
                    // Call onEndCall to properly dismiss the meeting and end any remaining CallKit session
                    onEndCall?()
                },
                onConferenceFailed: { error in
                    isConferenceActive = false
                    isConferenceStarting = false
                    errorMessage = error.localizedDescription
                    showError = true
                },
                onEndCall: onEndCall,
                onNativeClosePressed: {
                    print("🎥 Native close button pressed via direct callback")
                    // Use the exact same working dismiss logic that the test button used
                    self.forceDismissView()
                }
            )
            .ignoresSafeArea(.all, edges: .all) // Ensure full-screen on all devices including iPad
            
            // Loading overlay to prevent user interaction while preparing
            if isConferenceStarting || !isConferenceActive {
                // Semi-transparent background to block user interaction
                Color.black.opacity(0.3)
                    .ignoresSafeArea(.all, edges: .all)
                    .zIndex(1000) // High z-index to ensure it's on top
            }
            
            // Consultation controls: floating button + sheet that won't block meeting controls when hidden
            if isConferenceActive {
                // While dragging the FAB, insert a transparent blocker to prevent Jitsi from handling the pan
                if isDraggingFab {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .zIndex(205)
                }
                // Floating circular white button to open the consultation sheet (hidden when sheet is open)
                if !showConsultSheet {
                    GeometryReader { geo in
                        let size = geo.size
                        let margin: CGFloat = deviceService.isIPad ? 32 : 16
                        let diameter: CGFloat = deviceService.isIPad ? 72 : 56
                        let hitPadding: CGFloat = deviceService.isIPad ? 20 : 16
                        let effectiveHalf: CGFloat = (diameter / 2) + hitPadding

                        // Compute visual position = anchor + live drag translation, then clamp inside safe bounds
                        let computedX = min(max(fabAnchor.x + fabDragTranslation.width, effectiveHalf + margin), size.width - effectiveHalf - margin)
                        let computedY = min(max(fabAnchor.y + fabDragTranslation.height, effectiveHalf + margin), size.height - effectiveHalf - margin)

                        // Larger invisible hit area so drag doesn't fall through to Jitsi when finger moves
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: diameter, height: diameter)
                                .shadow(color: Color.black.opacity(0.18), radius: deviceService.isIPad ? 15 : 10, x: 0, y: 4)
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: deviceService.isIPad ? 28 : 20, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .padding(hitPadding)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Open consultation panel")
                        .position(x: computedX, y: computedY)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    isDraggingFab = (abs(dx) + abs(dy)) > 2
                                }
                                .updating($fabDragTranslation) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    let travel = sqrt(dx*dx + dy*dy)
                                    if travel < 6 {
                                        // Treat as tap
                                        showConsultSheet = true
                                    } else {
                                        var newX = fabAnchor.x + dx
                                        var newY = fabAnchor.y + dy
                                        newX = min(max(newX, effectiveHalf + margin), size.width - effectiveHalf - margin)
                                        newY = min(max(newY, effectiveHalf + margin), size.height - effectiveHalf - margin)
                                        fabAnchor = CGPoint(x: newX, y: newY)
                                    }
                                    isDraggingFab = false
                                }
                        , including: .all)
                        .onAppear {
                            if !hasSetInitialFabAnchor {
                                // Start at top-left with same safe margins
                                fabAnchor = CGPoint(x: effectiveHalf + margin, y: effectiveHalf + margin)
                                hasSetInitialFabAnchor = true
                                print("📍 Consultation button positioned at: \(fabAnchor)")
                            }
                        }
                    }
                    .zIndex(210)
                }

                // Bottom sheet only when shown; does not render a collapsed tip so it never blocks meeting controls
                if showConsultSheet {
                    VStack(spacing: 0) {
                        Spacer()
                        BottomSheet(
                            isPresented: $showConsultSheet,
                            snapPoints: [0.2, 0.6, 1.0],
                            initialIndex: 2,
                            allowsBackgroundDismiss: true,
                            showsTipCollapsed: false,
                            bottomInset: 0,
                            tipBottomInset: 0,
                            collapsedHeight: 0,
                            showsHeaderControls: false
                        ) {
                            VStack(spacing: 0) {
                                HStack {
                                    Spacer()
                                    Button {
                                        showConsultSheet = false
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "chevron.down")
                                            Text("Hide")
                                        }
                                        .font(.system(size: 15, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6))
                                        .clipShape(Capsule())
                                    }
                                    .accessibilityLabel("Hide consultation panel")
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 8)

                                ConsultationContainerVM(clinicSlug: clinicSlug, scriptId: scriptId)
                                    .background(Color(.systemBackground))
                                    .onAppear {
                                        print("📋 ConsultationContainerVM shown - clinicSlug: \(clinicSlug ?? "nil"), scriptId: \(scriptId?.description ?? "nil")")
                                    }
                            }
                        }
                    }
                    .zIndex(220)
                }
            }
        }
        // Full-screen; no safe area insets
        .alert("Conference Error", isPresented: $showError) {
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
        .onAppear { 
            // Start timeout timer for loading overlay (30 seconds)
            loadingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
                print("⏰ Loading timeout reached, hiding overlay")
                isConferenceStarting = false
            }
            
            // Listen for call ended notifications
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("CallEnded"),
                object: nil,
                queue: .main
            ) { _ in
                print("🎥 Call ended notification received")
                // Only dismiss if the conference is active and we're not in the middle of joining
                if isConferenceActive {
                    print("🎥 Conference is active, dismissing view")
                    if let onEndCall = onEndCall {
                        print("🎥 Using onEndCall callback to dismiss view")
                        onEndCall()
                    } else {
                        print("🎥 No onEndCall callback, using presentationMode to dismiss")
                        presentationMode.wrappedValue.dismiss()
                    }
                } else {
                    print("🎥 Conference not active, ignoring CallEnded notification")
                }
            }
            
            // Listen for native Jitsi close button press
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("JitsiNativeClosePressed"),
                object: nil,
                queue: .main
            ) { _ in
                print("🎥 Native Jitsi close button pressed notification received")
                print("🎥 Current view state - isConferenceActive: \(self.isConferenceActive)")
                print("🎥 Current view state - onEndCall: \(self.onEndCall != nil ? "available" : "nil")")
                // Force dismiss the view when native close button is pressed
                self.forceDismissView()
            }
        }
        .onDisappear { 
            // Cancel loading timeout timer
            loadingTimeoutTimer?.invalidate()
            loadingTimeoutTimer = nil
            
            // Remove notification observers
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("CallEnded"), object: nil)
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("JitsiNativeClosePressed"), object: nil)
            
            // Only call onEndCall if the user intentionally ended the call
            // This prevents queue removal when switching tabs or going to background
            if let onEndCall = onEndCall, isUserEndingCall {
                print("🎥 View disappearing - calling onEndCall callback (user ended call)")
                onEndCall()
            } else {
                print("🎥 View disappearing - no onEndCall callback or not user-initiated end")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Force dismiss the view - used when native Jitsi close button is pressed
    private func forceDismissView() {
        print("🎥 Force dismissing Jitsi meeting view")
        print("🎥 Current thread: \(Thread.isMainThread ? "Main" : "Background")")
        
        // Ensure all operations happen on the main thread
        DispatchQueue.main.async {
            // Mark that user intentionally ended the call
            self.isUserEndingCall = true
            
            // Always call onEndCall when native close button is pressed, regardless of conference state
            if let onEndCall = self.onEndCall {
                print("🎥 Native close button pressed - calling onEndCall callback")
                onEndCall()
            } else {
                print("🎥 Native close button pressed - no onEndCall callback available")
            }
            
            // Try multiple dismissal methods to ensure the view is dismissed
            
            // Method 1: Try SwiftUI presentationMode dismiss (for fullScreenCover presentations)
            print("🎥 Attempting SwiftUI dismiss")
            self.presentationMode.wrappedValue.dismiss()
            
            // Method 2: Try UIKit modal dismiss (for UIKit modal presentations)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                // Find the topmost presented view controller
                var topController = rootViewController
                while let presentedController = topController.presentedViewController {
                    topController = presentedController
                }
                
                print("🎥 Top controller type: \(type(of: topController))")
                
                // If this is our Jitsi view, dismiss it
                if topController is UIHostingController<JitsiMeetConferenceView> {
                    print("🎥 Found Jitsi view controller, dismissing via UIKit")
                    topController.dismiss(animated: true) {
                        print("🎥 UIKit dismiss completed")
                    }
                } else {
                    print("🎥 Top controller is not Jitsi view")
                    
                    // Try to dismiss any presented view controller
                    if let presentedController = rootViewController.presentedViewController {
                        print("🎥 Dismissing presented controller: \(type(of: presentedController))")
                        presentedController.dismiss(animated: true) {
                            print("🎥 Presented controller dismissed")
                        }
                    } else {
                        print("🎥 No presented controller found")
                    }
                }
            } else {
                print("🎥 Could not find window or root view controller")
            }
            
            // Method 3: Post notification to trigger dismissal from other parts of the app
            print("🎥 Posting notification to trigger dismissal")
            NotificationCenter.default.post(name: NSNotification.Name("DismissJitsiMeeting"), object: nil)
        }
    }
    
    // Removed removeFromWindow method - no longer needed
}

// MARK: - Bottom Sheet Container that fetches real consultation data
private struct ConsultationContainerVM: View {
    let clinicSlug: String?
    let scriptId: Int?
    @StateObject private var vm: ConsultationViewModel

    init(clinicSlug: String?, scriptId: Int?) {
        self.clinicSlug = clinicSlug
        self.scriptId = scriptId
        _vm = StateObject(wrappedValue: ConsultationViewModel(clinicSlug: clinicSlug, scriptId: scriptId))
    }
    
    // Determine whether to show buttons based on script status
    private var shouldShowButtons: Bool {
        // Show buttons if script status is empty or indicates it's waiting for approval
        guard let scriptStatus = vm.scriptStatus, !scriptStatus.isEmpty else {
            print("📋 No script status found, showing buttons")
            return true
        }
        
        print("📋 Checking script status: '\(scriptStatus)'")
        
        // Check if the script is already approved or rejected
        let lowercasedStatus = scriptStatus.lowercased()
        if lowercasedStatus.contains("approved") || lowercasedStatus.contains("rejected") {
            print("📋 Script already processed (status: '\(scriptStatus)'), hiding buttons")
            return false
        }
        
        // Show buttons specifically for "Awaiting Approval" status
        if lowercasedStatus.contains("awaiting approval") {
            print("📋 Script status is 'Awaiting Approval', showing buttons")
            return true
        }
        
        // For other statuses, don't show buttons by default
        print("📋 Script status is '\(scriptStatus)', hiding buttons")
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                LoadingView("Loading consultation details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            } else if let error = vm.error {
                ErrorView(message: error, retryAction: { Task { await vm.load() } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ConsultFormOverlayView(
                            fields: vm.fields.map { .init(name: $0.name, value: $0.value) },
                            patientSignatureURL: vm.patientSignatureURL,
                            nurseSignatureURL: vm.nurseSignatureURL,
                            scriptProducts: vm.scriptProducts,
                            showsButtons: shouldShowButtons,
                            isAccepting: vm.actionState == .processingApprove,
                            isRejecting: vm.actionState == .processingReject,
                            onAccept: { Task { await vm.updateStatus(1) } },
                            onReject: { Task { await vm.updateStatus(2) } }
                        )
                        .background(Color(.systemBackground))

                        // Show status cards based on script status or action state
                        Group {
                            if let scriptStatus = vm.scriptStatus, !scriptStatus.isEmpty {
                                // Show status based on script_status from API
                                let lowercasedStatus = scriptStatus.lowercased()
                                if lowercasedStatus.contains("approved") {
                                    StatusCardView(title: "Consultation Approved", subtitle: "This consultation has been approved.", icon: "checkmark.seal.fill", tint: .green)
                                        .padding(.top, 12)
                                } else if lowercasedStatus.contains("rejected") {
                                    StatusCardView(title: "Consultation Rejected", subtitle: "This consultation has been rejected.", icon: "xmark.seal.fill", tint: .red)
                                        .padding(.top, 12)
                                } else if lowercasedStatus.contains("awaiting approval") {
                                    // Show awaiting approval status
                                    StatusCardView(title: "Awaiting Approval", subtitle: "This consultation is waiting for your approval.", icon: "clock.badge.questionmark", tint: .orange)
                                        .padding(.top, 12)
                                } else {
                                    // For other statuses, show generic status
                                    StatusCardView(title: "Status: \(scriptStatus)", subtitle: "Current consultation status.", icon: "info.circle", tint: .blue)
                                        .padding(.top, 12)
                                }
                            } else {
                                // Show action state status cards
                                switch vm.actionState {
                                case .processingApprove:
                                    StatusCardView(title: "Approving consultation...", subtitle: "Please wait while we update the record.", icon: "hourglass", tint: .green, showsSpinner: true)
                                        .padding(.top, 12)
                                case .processingReject:
                                    StatusCardView(title: "Rejecting consultation...", subtitle: "Please wait while we update the record.", icon: "hourglass", tint: .red, showsSpinner: true)
                                        .padding(.top, 12)
                                case .successApprove:
                                    // Don't show success card when no script status - just show buttons
                                    EmptyView()
                                case .successReject:
                                    // Don't show success card when no script status - just show buttons
                                    EmptyView()
                                case .failure(let message):
                                    StatusCardView(title: "Update failed", subtitle: message, icon: "exclamationmark.triangle.fill", tint: .orange)
                                        .padding(.top, 12)
                                default:
                                    EmptyView()
                                }
                            }
                        }
                        .padding(.horizontal, 12)

                        // Large bottom spacer to ensure buttons are fully scrollable above safe area
                        Color.clear.frame(height: 48)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .task { await vm.load() }
        .alert("Success", isPresented: Binding(get: { vm.showSuccess }, set: { vm.showSuccess = $0 })) {
            Button("OK") {}
        } message: { Text(vm.successMessage) }
    }
}

private extension Notification.Name {
    static let consultationAcceptTapped = Notification.Name("consultationAcceptTapped")
    static let consultationRejectTapped = Notification.Name("consultationRejectTapped")
}

// MARK: - Status Card
private struct StatusCardView: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var showsSpinner: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    if showsSpinner { ProgressView().scaleEffect(0.8) }
                }
                Text(subtitle).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Custom Jitsi Meet View that intercepts close button
class CustomJitsiMeetView: JitsiMeetView {
    var onNativeClosePressed: (() -> Void)?
    
    override func leave() {
        // Call our callback before leaving
        if let onNativeClosePressed = onNativeClosePressed {
            DispatchQueue.main.async {
                onNativeClosePressed()
            }
        }
        // Call the original leave method
        super.leave()
    }
    
    // Override the close button behavior by intercepting touch events
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Let the parent handle the touch event normally
        return super.point(inside: point, with: event)
    }
    
    // Also try to override the close button's action method
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        // Try to find and override the close button
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.findAndOverrideCloseButton()
        }
    }
    
    private func findAndOverrideCloseButton() {
        // Only override close buttons if we have a callback
        guard onNativeClosePressed != nil else { return }
        
        // Recursively search for buttons in the view hierarchy
        func findButtons(in view: UIView) {
            if let button = view as? UIButton {
                // Check if this looks like a close button (position, size, etc.)
                if button.frame.origin.x < 100 && button.frame.origin.y < 100 {
                    // Only add our custom action if it's not already added
                    if !button.allTargets.contains(self) {
                        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
                    }
                }
            }
            
            // Recursively search subviews
            for subview in view.subviews {
                findButtons(in: subview)
            }
        }
        
        findButtons(in: self)
    }
    
    @objc private func closeButtonTapped() {
        if let onNativeClosePressed = onNativeClosePressed {
            DispatchQueue.main.async {
                onNativeClosePressed()
            }
        }
    }
}

// MARK: - Direct Jitsi Meet View (No Wrapper Needed)
struct DirectJitsiMeetView: UIViewRepresentable {
    let roomName: String
    let displayName: String?
    let email: String?
    let conferenceUrl: String?
    let scriptId: Int?
    let clinicSlug: String?
    let scriptUUID: String?
    let clinicName: String?
    let onConferenceJoined: (() -> Void)?
    let onConferenceTerminated: (() -> Void)?
    let onConferenceFailed: ((Error) -> Void)?
    let onEndCall: (() -> Void)?
    let onNativeClosePressed: (() -> Void)? // New callback for native close button
    
    func makeUIView(context: Context) -> UIView {
        let jitsiMeetView = CustomJitsiMeetView()
        jitsiMeetView.delegate = context.coordinator
        jitsiMeetView.onNativeClosePressed = onNativeClosePressed
        
        // Request camera permission before starting Jitsi
        requestCameraPermission { [weak jitsiMeetView] in
            DispatchQueue.main.async {
                // Activate call audio session for proper voice call audio
                AudioService.shared.activateCallAudioSession()
                
                // Log audio session status for debugging
                print("🎤 Jitsi meeting starting - Audio session configured")
                print("🎤 Room name: \(roomName)")
                print("🎤 Server URL: \(conferenceUrl ?? EnvironmentManager.shared.currentJitsiURL)")
                
                // Configure and join conference after permissions are granted
                self.configureAndJoinConference(jitsiMeetView: jitsiMeetView)
            }
        }
        
        return jitsiMeetView
    }
    
    private func configureAndJoinConference(jitsiMeetView: CustomJitsiMeetView?) {
        guard let jitsiMeetView = jitsiMeetView else { return }
        
        // Configure Jitsi Meet options following official SDK patterns
        let options = JitsiMeetConferenceOptions.fromBuilder { builder in
            // Set the room name for the conference
            builder.room = roomName
            
            // Configure user information
            builder.userInfo = JitsiMeetUserInfo(
                displayName: displayName ?? "User",
                andEmail: email,
                andAvatar: URL(string: "")
            )
            
            // Set the server URL to your custom Jitsi server
            builder.serverURL = URL(string: conferenceUrl ?? EnvironmentManager.shared.currentJitsiURL)
            
            // Disable config loading to prevent disconnection issues
            builder.setConfigOverride("disableConfigLoading", withValue: true)
            builder.setConfigOverride("loadConfigOverwrite", withValue: false)
            
            // Configure meeting settings
            builder.setAudioMuted(false)
            builder.setVideoMuted(false)
            
            // Enable features
            builder.setFeatureFlag("ios.recording.enabled", withValue: false)
            builder.setFeatureFlag("ios.screensharing.enabled", withValue: false)
            builder.setFeatureFlag("ios.pip.enabled", withValue: true)
            
            // Set meeting properties
            builder.setSubject("Cosmetic Consultation")
            builder.setConfigOverride("startWithAudioMuted", withValue: false)
            builder.setConfigOverride("startWithVideoMuted", withValue: false)
            builder.setConfigOverride("disableModeratorIndicator", withValue: true)
            builder.setConfigOverride("enableClosePage", withValue: false)
            builder.setConfigOverride("disableDeepLinking", withValue: true)
            builder.setConfigOverride("disableInviteFunctions", withValue: true)
            builder.setConfigOverride("disablePolls", withValue: true)
            builder.setConfigOverride("disableReactions", withValue: true)
            builder.setConfigOverride("disableSelfView", withValue: false)
            builder.setConfigOverride("disableSelfViewSettings", withValue: true)
            
            // Disable prejoin page and welcome page
            builder.setConfigOverride("prejoinPageEnabled", withValue: false)
            builder.setConfigOverride("welcomePageEnabled", withValue: false)
            
            // Additional prejoin-related settings
            builder.setConfigOverride("disablePrejoinPage", withValue: true)
            builder.setConfigOverride("skipPrejoinButton", withValue: true)
            
            // Add stability configurations
            builder.setConfigOverride("enableNoisyMicDetection", withValue: false)
            builder.setConfigOverride("enableTalkWhileMuted", withValue: false)
            builder.setConfigOverride("enableLayerSuspension", withValue: false)
            builder.setConfigOverride("channelLastN", withValue: 4)
            builder.setConfigOverride("startWithAudioMuted", withValue: false)
            builder.setConfigOverride("startWithVideoMuted", withValue: false)
            
        }
        
        // Join the conference
        print("🎤 Joining conference with room: \(roomName)")
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
        
        // Only trigger queue removal if user intentionally ended the call
        // This prevents queue removal when switching tabs or going to background
        if coordinator.isUserEndingCall {
            print("🎥 View dismantled - user ended call, triggering queue removal")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .jitsiConferenceTerminated, object: nil)
            }
        } else {
            print("🎥 View dismantled - not user-initiated, skipping queue removal")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, JitsiMeetViewDelegate {
        let parent: DirectJitsiMeetView
        private var hasJoinedConference = false
        private var isConferenceEnding = false
        var isUserEndingCall = false // Track if user intentionally ended the call
        
        init(_ parent: DirectJitsiMeetView) {
            self.parent = parent
        }
        
        // MARK: - JitsiMeetViewDelegate
        func conferenceJoined(_ data: [AnyHashable : Any]!) {
            print("🎥 Conference joined successfully")
            print("🎥 Conference data: \(data ?? [:])")
            hasJoinedConference = true
            parent.onConferenceJoined?()
            
            // Post notification that Jitsi conference has started
            // This allows CallKitManager to reset the accepting call flag
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("JitsiConferenceStarted"), object: nil)
            }
        }
        
        func conferenceFailed(_ data: [AnyHashable : Any]!) {
            print("🎥 Conference failed to join")
            print("🎥 Failure data: \(data ?? [:])")
            hasJoinedConference = false
            
            // Extract error information from the data
            var errorMessage = "Failed to join conference"
            if let error = data?["error"] as? String {
                errorMessage = error
            } else if let error = data?["error"] as? Error {
                errorMessage = error.localizedDescription
            }
            
            let error = NSError(
                domain: "JitsiMeet",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMessage,
                    "conferenceData": data ?? [:]
                ]
            )
            parent.onConferenceFailed?(error)
        }
        
        func conferenceLeft(_ data: [AnyHashable : Any]!) {
            print("🎥 Conference left")
            // Only trigger dismissal if we had actually joined the conference
            if hasJoinedConference && !isConferenceEnding {
                handleConferenceEnd()
            }
        }
        
        func conferenceEnded(_ data: [AnyHashable : Any]!) {
            print("🎥 Conference ended")
            // Only trigger dismissal if we had actually joined the conference
            if hasJoinedConference && !isConferenceEnding {
                handleConferenceEnd()
            }
        }
        
        func conferenceWillJoin(_ data: [AnyHashable : Any]!) {
            print("🎥 Conference will join - room loading, conference starting")
            hasJoinedConference = false
            isConferenceEnding = false
        }
        
        func conferenceWillTerminate(_ data: [AnyHashable : Any]!) {
            print("🎥 Conference will terminate")
            // Mark that user intentionally ended the call
            isUserEndingCall = true
            
            // Deactivate call audio session when meeting is about to end
            DispatchQueue.main.async {
                AudioService.shared.deactivateCallAudioSession()
            }
            
            // Only trigger dismissal if we had actually joined the conference
            if hasJoinedConference && !isConferenceEnding {
                handleConferenceEnd()
            }
            
            // Note: Don't post jitsiConferenceTerminated here as it will be posted in conferenceTerminated
        }
        
        // CRITICAL: This is the main delegate method for native close button
        func conferenceTerminated(_ data: [AnyHashable : Any]!) {
            print("🎥 Conference terminated")
            // Mark that user intentionally ended the call
            isUserEndingCall = true
            
            // Deactivate call audio session when meeting ends
            DispatchQueue.main.async {
                AudioService.shared.deactivateCallAudioSession()
            }
            
            // Only trigger dismissal if we had actually joined the conference and it's not already ending
            if hasJoinedConference && !isConferenceEnding {
                handleConferenceEnd()
            }
            
            // Trigger queue list API refresh when meeting ends
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .jitsiConferenceTerminated, object: nil)
            }
        }
        
        // MARK: - Helper Methods
        private func handleConferenceEnd() {
            print("🎥 Handling conference end - hasJoinedConference: \(hasJoinedConference), isConferenceEnding: \(isConferenceEnding)")
            print("🎥 Current app state: \(UIApplication.shared.applicationState.rawValue)")
            print("🎥 Current thread: \(Thread.isMainThread ? "Main" : "Background")")
            
            // Only proceed if we actually joined the conference
            guard hasJoinedConference else {
                print("🎥 Conference never joined, ignoring end call")
                return
            }
            
            // Set the flag to prevent duplicate calls
            isConferenceEnding = true
            print("🎥 Set isConferenceEnding to true")
            
            // Ensure all operations happen on the main thread
            DispatchQueue.main.async {
                // Remove queue item when Jitsi meeting ends (native end call button)
                print("🎥 Removing queue item from Jitsi")
                self.removeQueueItemFromJitsi()
                
                // Transition back to normal audio session
                print("🎥 Transitioning audio session")
                AudioService.shared.transitionFromJitsiAudioSession()
                
                // Use direct callback for native close button - this will trigger the dismissal flow
                if let onNativeClosePressed = self.parent.onNativeClosePressed {
                    print("🎥 Using direct onNativeClosePressed callback")
                    onNativeClosePressed()
                } else {
                    // Fallback: Post notification for native close button
                    print("🎥 Using fallback notification for native close button")
                    NotificationCenter.default.post(name: NSNotification.Name("JitsiNativeClosePressed"), object: nil)
                }
                
                print("🎥 handleConferenceEnd completed")
            }
        }
        
        /// Remove queue item when Jitsi meeting ends (native end call button)
        private func removeQueueItemFromJitsi() {
            // Try to get call data from CallKitManager first
            if let call = CallKitManager.shared.currentCall {
                // Use CallKitManager data if available (clinicName optional)
                guard let scriptId = call.scriptId,
                      let clinicSlug = call.clinicSlug,
                      let scriptUUID = call.scriptUUID else {
                    print("⚠️ JitsiMeetView: Cannot remove queue item - missing required parameters from CallKitManager")
                    print("   - Script ID: \(call.scriptId?.description ?? "nil")")
                    print("   - Clinic Slug: \(call.clinicSlug ?? "nil")")
                    print("   - Script UUID: \(call.scriptUUID ?? "nil")")
                    print("   - Clinic Name: \(call.clinicName ?? "nil")")
                    return
                }
                
                print("🗑️ JitsiMeetView: Removing queue item for ended Jitsi meeting (from CallKitManager)")
                print("   - Script ID: \(scriptId)")
                print("   - Script UUID: \(scriptUUID)")
                print("   - Clinic Slug: \(clinicSlug)")
                print("   - Clinic Name: \(call.clinicName ?? "")")
                print("   - Caller Name: \(call.displayName)")
                print("   - Room Name: \(call.roomName ?? "nil")")
                
                Task {
                    do {
                        let queueAPIService = QueueAPIService()
                        let success = try await queueAPIService.removeQueueItem(
                            scriptUUID: scriptUUID,
                            scriptId: scriptId,
                            clinicSlug: clinicSlug,
                            clinicName: call.clinicName,
                            callerName: call.displayName,
                            roomName: call.roomName ?? parent.roomName
                        )
                        
                        if success {
                            print("✅ JitsiMeetView: Queue item removed successfully")
                            
                            // Clear call data after successful queue removal
                            CallKitManager.shared.clearCallData()
                        } else {
                            print("❌ JitsiMeetView: Failed to remove queue item - API returned false")
                        }
                    } catch {
                        print("❌ JitsiMeetView: Failed to remove queue item: \(error)")
                    }
                }
            } else {
                // Fallback to parent data if CallKitManager data is not available (clinicName optional)
                guard let scriptId = parent.scriptId,
                      let clinicSlug = parent.clinicSlug,
                      let scriptUUID = parent.scriptUUID else {
                    print("⚠️ JitsiMeetView: Cannot remove queue item - missing required parameters from both CallKitManager and parent")
                    print("   - Script ID: \(parent.scriptId?.description ?? "nil")")
                    print("   - Clinic Slug: \(parent.clinicSlug ?? "nil")")
                    print("   - Script UUID: \(parent.scriptUUID ?? "nil")")
                    print("   - Clinic Name: \(parent.clinicName ?? "nil")")
                    return
                }
                
                print("🗑️ JitsiMeetView: Removing queue item for ended Jitsi meeting (from parent data)")
                print("   - Script ID: \(scriptId)")
                print("   - Script UUID: \(scriptUUID)")
                print("   - Clinic Slug: \(clinicSlug)")
                print("   - Clinic Name: \(parent.clinicName ?? "")")
                print("   - Caller Name: \(parent.displayName ?? "nil")")
                print("   - Room Name: \(parent.roomName)")
                
                Task {
                    do {
                        let queueAPIService = QueueAPIService()
                        let success = try await queueAPIService.removeQueueItem(
                            scriptUUID: scriptUUID,
                            scriptId: scriptId,
                            clinicSlug: clinicSlug,
                            clinicName: parent.clinicName,
                            callerName: parent.displayName ?? "Unknown",
                            roomName: parent.roomName
                        )
                        
                        if success {
                            print("✅ JitsiMeetView: Queue item removed successfully")
                        } else {
                            print("❌ JitsiMeetView: Failed to remove queue item - API returned false")
                        }
                    } catch {
                        print("❌ JitsiMeetView: Failed to remove queue item: \(error)")
                    }
                }
            }
        }
        
        func enterPicture(inPicture data: [AnyHashable : Any]!) {
            // Entered picture in picture mode
        }
        
        func exitPicture(inPicture data: [AnyHashable : Any]!) {
            // Exited picture in picture mode
        }
        
        func participantJoined(_ data: [AnyHashable : Any]!) {
            print("🎥 Participant joined: \(data ?? [:])")
        }
        
        func participantLeft(_ data: [AnyHashable : Any]!) {
            print("🎥 Participant left: \(data ?? [:])")
        }
        
        func audioMutedChanged(_ data: [AnyHashable : Any]!) {
            // Audio muted changed
        }
        
        func videoMutedChanged(_ data: [AnyHashable : Any]!) {
            // Video muted changed
        }
        
        func endpointTextMessageReceived(_ data: [AnyHashable : Any]!) {
            // Endpoint text message received
        }
        
        func screenShareToggled(_ data: [AnyHashable : Any]!) {
            // Screen share toggled
        }
        
        func chatMessageReceived(_ data: [AnyHashable : Any]!) {
            // Chat message received
        }
        
        func chatToggled(_ data: [AnyHashable : Any]!) {
            // Chat toggled
        }
        
        func participantsInfoRetrieved(_ data: [AnyHashable : Any]!) {
            // Participants info retrieved
        }
        
        func openSettings(_ data: [AnyHashable : Any]!) {
            // Open settings
        }
        
        func raiseHandUpdated(_ data: [AnyHashable : Any]!) {
            // Raise hand updated
        }
        
        func recordingStatusChanged(_ data: [AnyHashable : Any]!) {
            // Recording status changed
        }
        
        func liveStreamingStatusChanged(_ data: [AnyHashable : Any]!) {
            // Live streaming status changed
        }
        
        func error(_ data: [AnyHashable : Any]!) {
            if let error = data["error"] as? Error {
                parent.onConferenceFailed?(error)
            } else {
                let customError = NSError(domain: "JitsiMeet", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown Jitsi error"])
                parent.onConferenceFailed?(customError)
            }
        }
    }
}

// MARK: - Preview
struct JitsiMeetConferenceView_Previews: PreviewProvider {
    static var previews: some View {
        JitsiMeetConferenceView(
            roomName: "test_room_123",
            displayName: "Test User",
            email: "test@example.com",
            conferenceUrl: nil,
            roomId: nil,
            clinicSlug: "6_on_the_spot_clinic",
            scriptId: 21,
            onEndCall: nil
        )
    }
}
