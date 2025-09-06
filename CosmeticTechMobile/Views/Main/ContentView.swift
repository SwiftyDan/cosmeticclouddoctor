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
    }
}







#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthManager())
        .environmentObject(CallKitManager.shared)
        .environmentObject(WebViewService.shared)
}
