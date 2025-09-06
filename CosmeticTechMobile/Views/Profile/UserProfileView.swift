//
//  UserProfileView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI

struct UserProfileView: View {
    @EnvironmentObject private var authManager: AuthManager
    private let deviceService = DeviceOrientationService.shared
    @State private var selectedTab = 0
    @State private var voipToken: String = ""
    @State private var copied: Bool = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: deviceService.isIPad ? 32 : 20) {
                    // User Profile Header
                    userProfileHeader
                    
                    // Profile Details Only
                    voipTokenSection
                    
                    // Logout Section
                    logoutSection
                }
                .padding(deviceService.isIPad ? 32 : 20)
                .frame(maxWidth: deviceService.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { }
        }

    }
    
    // MARK: - VoIP Token Section
    private var voipTokenSection: some View {
        VStack(alignment: .leading, spacing: deviceService.isIPad ? 12 : 8) {
            HStack {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundColor(.purple)
                Text("VoIP Push Token").font(.system(size: deviceService.headlineFontSize, weight: .semibold))
                Spacer()
                if copied {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
            }
            .padding(.bottom, 4)

            if voipToken.isEmpty {
                Text("Not available yet. Keep the app open for a few seconds.")
                    .font(.system(size: deviceService.captionFontSize))
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(voipToken)
                        .font(.system(size: deviceService.captionFontSize))
                        .textSelection(.enabled)
                        .padding(deviceService.isIPad ? 12 : 8)
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(deviceService.isIPad ? 12 : 8)
                }
                Button(action: {
                    UIPasteboard.general.string = voipToken
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: deviceService.captionFontSize))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(deviceService.isIPad ? 24 : 16)
        .background(Color(.systemBackground))
        .cornerRadius(deviceService.cornerRadius)
        .shadow(color: .black.opacity(0.1), radius: deviceService.isIPad ? 8 : 5, x: 0, y: 2)
        .onAppear { loadVoipToken() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.voipTokenUpdated)) { notif in
            if let token = notif.object as? String { voipToken = token }
        }
    }

    // MARK: - User Profile Header
    private var userProfileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [.blue, .purple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                )
            
            // User Info
            VStack(spacing: 8) {
                Text(authManager.currentUser?.name ?? "User")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(authManager.currentUser?.email ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let phone = authManager.currentUser?.phone {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // VoIP token section removed
    

    

    
    // MARK: - Test Section (Development Only)
    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "testtube.2")
                    .foregroundColor(.orange)
                Text("🧪 Development Tools")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text("Test Jitsi Meet integration and conference functionality")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                // Test functionality removed
            }) {
                HStack {
                    Image(systemName: "video.fill")
                        .foregroundColor(.green)
                    Text("Open Jitsi Meet Test Suite")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Logout Section
    private var logoutSection: some View {
        VStack(spacing: 16) {
            // Logout Button
            Button(action: {
                Task { await authManager.logout() }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.title3)
                        .foregroundColor(.white)
                    
                    if authManager.isLoggingOut {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(authManager.isLoggingOut ? "Logging out..." : "Logout")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(authManager.isLoggingOut)
            
            // Account Settings navigation (deactivate is moved to dedicated screen)
            NavigationLink(destination: AccountSettingsView()) {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.white)
                    Text("Account Settings")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())

            // App Version / Build / Environment
            VStack(spacing: 4) {
                Text("CosmeticTech Mobile")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Version \(appVersion) (Build \(buildNumber))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Environment: \(APIConfiguration.shared.endpoints.environmentName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // Helper
    private func loadVoipToken() {
        if let live = VoIPPushHandler.shared.getCurrentVoIPToken(), !live.isEmpty {
            voipToken = live
            return
        }
        let keychain = KeychainService()
        if let cached: String = keychain.retrieve(key: "voip_token", type: String.self) {
            voipToken = cached
        }
    }

}



 
