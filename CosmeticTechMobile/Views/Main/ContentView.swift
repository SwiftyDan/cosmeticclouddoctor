//
//  ContentView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/6/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var callKitManager = CallKitManager.shared
    @StateObject private var webViewService = WebViewService.shared
    @StateObject private var globalJitsiManager = GlobalJitsiManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            
            // Calls Tab
            CallsView()
                .tabItem {
                    Image(systemName: "phone.fill")
                    Text("Calls")
                }
                .tag(1)
            
            // Profile Tab
            UserProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(2)
        }
        .accentColor(.blue)
        .sheet(isPresented: $webViewService.showWebView) {
            if let url = webViewService.webViewURL {
                WebViewModal(url: url) {
                    webViewService.dismissWebView()
                }
            }
        }
        .fullScreenCover(isPresented: $globalJitsiManager.isPresentingJitsi) {
            if let params = globalJitsiManager.jitsiParameters {
                JitsiMeetConferenceView(
                    roomName: params.roomName,
                    displayName: params.displayName,
                    email: params.email,
                    conferenceUrl: params.conferenceUrl,
                    roomId: params.roomId,
                    clinicSlug: params.clinicSlug,
                    scriptId: params.scriptId,
                    scriptUUID: params.scriptUUID,
                    clinicName: params.clinicName,
                    onEndCall: {
                        // End the call and dismiss the view
                        print("🎥 Call ended from GlobalJitsiManager, dismissing view")
                        print("🎥 Current app state: \(UIApplication.shared.applicationState.rawValue)")
                        print("🎥 GlobalJitsiManager isPresentingJitsi: \(globalJitsiManager.isPresentingJitsi)")
                        
                        // Set isPresentingJitsi to false immediately to ensure SwiftUI dismisses the fullScreenCover
                        globalJitsiManager.isPresentingJitsi = false
                        
                        // Ensure we're on the main thread for UI updates
                        DispatchQueue.main.async {
                            globalJitsiManager.endCall()
                            
                            // Notify HomeViewModel to handle consultation ending
                            NotificationCenter.default.post(name: .jitsiConferenceTerminated, object: nil)
                        }
                    }
                )
            }
        }
    }
}







#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthManager())
        .environmentObject(CallKitManager.shared)
        .environmentObject(WebViewService.shared)
}
