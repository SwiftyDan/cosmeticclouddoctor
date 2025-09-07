//
//  EnvironmentSettingsView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI

struct EnvironmentSettingsView: View {
    @StateObject private var environmentManager = EnvironmentManager.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var customAPIURL: String = ""
    @State private var customJitsiURL: String = ""
    @State private var customSocketURL: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Environment Selection")) {
                    Picker("Environment", selection: $environmentManager.selectedEnvironment) {
                        ForEach(APIEnvironment.allCases, id: \.self) { environment in
                            Text(environment.displayName).tag(environment)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                if environmentManager.selectedEnvironment == .custom {
                    Section(header: Text("Custom URLs")) {
                        TextField("API URL", text: $customAPIURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextField("Jitsi URL", text: $customJitsiURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextField("Socket URL", text: $customSocketURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Update Custom URLs") {
                            environmentManager.customAPIURL = customAPIURL
                            environmentManager.customJitsiURL = customJitsiURL
                            environmentManager.customSocketURL = customSocketURL
                            alertMessage = "Custom URLs updated!"
                            showingAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                Section(header: Text("Current Environment Info")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment: \(environmentManager.currentEnvironment.displayName)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Text("API URL: \(environmentManager.currentAPIURL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                        
                        Text("Jitsi URL: \(environmentManager.currentJitsiURL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                        
                        Text("Socket URL: \(environmentManager.currentSocketURL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Actions")) {
                    Button("Reset to Production") {
                        environmentManager.setEnvironment(.production)
                        alertMessage = "Reset to Production environment!"
                        showingAlert = true
                    }
                    .foregroundColor(.red)
                    
                    Button("Copy Environment Info") {
                        let info = environmentManager.getEnvironmentInfo()
                        UIPasteboard.general.string = info
                        alertMessage = "Environment info copied to clipboard!"
                        showingAlert = true
                    }
                }
            }
            .navigationTitle("Environment Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadCustomURLs()
        }
        .alert("Environment Settings", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func loadCustomURLs() {
        customAPIURL = environmentManager.customAPIURL
        customJitsiURL = environmentManager.customJitsiURL
        customSocketURL = environmentManager.customSocketURL
    }
}