//
//  EnvironmentSettingsView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/13/25.
//

import SwiftUI
import Combine

struct EnvironmentSettingsView: View {
    @StateObject private var environmentManager = EnvironmentManager.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var customAPIURL = ""
    @State private var customJitsiURL = ""
    @State private var customSocketURL = ""
    @State private var showingRestartAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Environment Settings")) {
                    Picker("API Environment", selection: Binding(
                        get: { environmentManager.currentEnvironment },
                        set: { newEnvironment in
                            if newEnvironment != environmentManager.currentEnvironment {
                                environmentManager.setEnvironment(newEnvironment)
                                showingRestartAlert = true
                            }
                        }
                    )) {
                        ForEach(APIEnvironment.allCases, id: \.self) { environment in
                            Text(environment.displayName).tag(environment)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Current Configuration")) {
                    HStack {
                        Text("API URL")
                        Spacer()
                        Text(environmentManager.currentAPIURL)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Jitsi URL")
                        Spacer()
                        Text(environmentManager.currentJitsiURL)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Socket URL")
                        Spacer()
                        Text(environmentManager.currentSocketURL)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                if environmentManager.currentEnvironment == .custom {
                    Section(header: Text("Custom URLs")) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading) {
                                Text("API URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("https://your-api.com/api", text: $customAPIURL)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Jitsi URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("https://your-jitsi.com", text: $customJitsiURL)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Socket URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("https://your-socket.com", text: $customSocketURL)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            Button("Update Custom URLs") {
                                updateCustomURLs()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .foregroundColor(.red)
                    
                    Button("Copy Environment Info") {
                        copyEnvironmentInfo()
                    }
                    
                    Button("Debug Current State") {
                        environmentManager.debugCurrentState()
                    }
                    .foregroundColor(.blue)
                    
                    Button("Test Development Environment") {
                        environmentManager.setEnvironment(.development)
                        alertMessage = "Switched to Development environment!"
                        showingAlert = true
                    }
                    .foregroundColor(.orange)
                    
                    Button("Test UserDefaults Change") {
                        UserDefaults.standard.set("development", forKey: "API_ENVIRONMENT")
                        UserDefaults.standard.synchronize()
                        alertMessage = "Changed UserDefaults to development - check if environment updates!"
                        showingAlert = true
                    }
                    .foregroundColor(.purple)
                    
                    Button("Test API Endpoints") {
                        let login = EnvironmentManager.shared.currentAPIURL + "/login"
                        let base = EnvironmentManager.shared.currentAPIURL
                        let env = EnvironmentManager.shared.currentEnvironment.displayName
                        let testMessage = """
                        Current API Endpoints:
                        Login: \(login)
                        Base URL: \(base)
                        Environment: \(env)
                        """
                        alertMessage = testMessage
                        showingAlert = true
                    }
                    .foregroundColor(.cyan)
                    
                    Button("Force Refresh All Components") {
                        environmentManager.forceRefreshAllComponents()
                        alertMessage = "Force refreshed all components with current environment!"
                        showingAlert = true
                    }
                    .foregroundColor(.green)
                    
                    Button("Restart App (Simulator Only)") {
                        restartApp()
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("About")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment switching allows you to change the API endpoints for testing and development purposes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Changes will take effect immediately for new API calls and Jitsi meetings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Environment Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadCustomURLs()
            }
            .alert("Environment Updated", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .alert("Environment Changed", isPresented: $showingRestartAlert) {
                Button("Continue") { }
                Button("Force Refresh") {
                    environmentManager.forceRefreshAllComponents()
                }
            } message: {
                Text("Environment has been changed to \(environmentManager.currentEnvironment.displayName). For best results, you may want to restart the app or force refresh all components.")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCustomURLs() {
        customAPIURL = environmentManager.customAPIURL
        customJitsiURL = environmentManager.customJitsiURL
        customSocketURL = environmentManager.customSocketURL
    }
    
    private func updateCustomURLs() {
        environmentManager.updateCustomURLs(
            api: customAPIURL,
            jitsi: customJitsiURL,
            socket: customSocketURL
        )
        
        alertMessage = "Custom URLs updated successfully!"
        showingAlert = true
    }
    
    private func resetToDefaults() {
        environmentManager.resetToDefaults()
        loadCustomURLs()
        
        alertMessage = "Environment reset to production defaults!"
        showingAlert = true
    }
    
    private func copyEnvironmentInfo() {
        let info = environmentManager.getEnvironmentInfo()
        UIPasteboard.general.string = info
        
        alertMessage = "Environment info copied to clipboard!"
        showingAlert = true
    }
    
    private func restartApp() {
        #if targetEnvironment(simulator)
        // This only works in simulator
        exit(0)
        #else
        alertMessage = "App restart is only available in simulator. Please manually restart the app."
        showingAlert = true
        #endif
    }
}

// MARK: - Preview
struct EnvironmentSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        EnvironmentSettingsView()
    }
}
