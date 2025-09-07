//
//  LoginView.swift
//  CosmeticTechMobile
//
//  Created by Dan Albert Luab on 8/7/25.
//

import SwiftUI

// Custom text field style for better visibility in both light and dark modes
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundColor(.primary)
            .accentColor(.blue)
    }
}

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @StateObject private var environmentManager = EnvironmentManager.shared
    @EnvironmentObject private var authManager: AuthManager
    private let deviceService = DeviceOrientationService.shared
    @State private var tapCount = 0
    @State private var showingEnvironmentAlert = false
    
    init() {
        // Initialize with a temporary AuthManager, will be updated in onAppear
        self._viewModel = StateObject(wrappedValue: LoginViewModel(authManager: AuthManager()))
    }
    
    var body: some View {
        ZStack {
            // Background color - adaptive for dark mode
            Color(.systemBackground)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: deviceService.isIPad ? 40 : 30) {
                    // Logo and Title
                    VStack(spacing: deviceService.isIPad ? 28 : 20) {
                        Image("cosmetic-cloud-icon-exact")
                            .resizable()
                            .scaledToFit()
                            .frame(width: deviceService.isIPad ? 128 : 96, height: deviceService.isIPad ? 128 : 96)
                            .clipShape(RoundedRectangle(cornerRadius: deviceService.cornerRadius, style: .continuous))
                            .onTapGesture {
                                tapCount += 1
                                if tapCount >= 5 {
                                    // Switch to development environment
                                    environmentManager.forceSetEnvironment(.development)
                                    showingEnvironmentAlert = true
                                    tapCount = 0
                                } else {
                                    // Reset tap count after 2 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        tapCount = 0
                                    }
                                }
                            }
                        
                        Text("Cosmetic Cloud VC")
                            .font(.system(size: deviceService.isIPad ? 42 : 34, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Sign in to your account")
                            .font(.system(size: deviceService.bodyFontSize))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, deviceService.isIPad ? 80 : 50)
                    
                    // Login Form - iPad optimized layout (full-screen width)
                    Group {
                        if deviceService.isIPad {
                            // iPad: Centered form with max width for better readability
                            VStack(spacing: 28) {
                                VStack(spacing: 28) {
                                    // Email Field
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Email")
                                            .font(.system(size: deviceService.headlineFontSize, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack {
                                            Image(systemName: "envelope.fill")
                                                .foregroundColor(.secondary)
                                                .frame(width: 24)
                                            
                                            TextField("Enter your email", text: $viewModel.email)
                                                .textFieldStyle(CustomTextFieldStyle())
                                                .keyboardType(.emailAddress)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                                .font(.system(size: deviceService.bodyFontSize))
                                                .foregroundColor(.primary)
                                        }
                                        .padding(20)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(deviceService.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: deviceService.cornerRadius)
                                                .stroke(viewModel.isEmailValid || viewModel.email.isEmpty ? Color.primary.opacity(0.2) : Color.red, lineWidth: viewModel.isEmailValid || viewModel.email.isEmpty ? 1 : 2)
                                        )
                                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                        .frame(maxWidth: .infinity)
                                    }
                                    
                                    // Password Field
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Password")
                                            .font(.system(size: deviceService.headlineFontSize, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        HStack {
                                            Image(systemName: "lock.fill")
                                                .foregroundColor(.secondary)
                                                .frame(width: 24)
                                            
                                            if viewModel.showPassword {
                                                TextField("Enter your password", text: $viewModel.password)
                                                    .textFieldStyle(CustomTextFieldStyle())
                                                    .font(.system(size: deviceService.bodyFontSize))
                                                    .foregroundColor(.primary)
                                            } else {
                                                SecureField("Enter your password", text: $viewModel.password)
                                                    .font(.system(size: deviceService.bodyFontSize))
                                                    .foregroundColor(.primary)
                                            }
                                            
                                            Button(action: {
                                                viewModel.showPassword.toggle()
                                            }) {
                                                Image(systemName: viewModel.showPassword ? "eye.slash.fill" : "eye.fill")
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(20)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(deviceService.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: deviceService.cornerRadius)
                                                .stroke(viewModel.isPasswordValid || viewModel.password.isEmpty ? Color.primary.opacity(0.2) : Color.red, lineWidth: viewModel.isPasswordValid || viewModel.password.isEmpty ? 1 : 2)
                                        )
                                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                        .frame(maxWidth: .infinity)
                                    }
                                    
                                    // Login Button
                                    Button(action: {
                                        Task {
                                            await viewModel.login()
                                        }
                                    }) {
                                        HStack {
                                            if case .loading = viewModel.state {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(1.0)
                                            } else {
                                                Image(systemName: "arrow.right")
                                            }
                                            
                                            Text("Sign In")
                                                .font(.system(size: 20, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(20)
                                        .background(
                                            viewModel.isFormValid ? Color.blue : Color.gray
                                        )
                                        .cornerRadius(deviceService.cornerRadius)
                                    }
                                    .disabled(!viewModel.isFormValid || viewModel.state == .loading)
                                    
                                    // Clear Saved Login Button (only show if credentials exist)
                                    if !viewModel.email.isEmpty || !viewModel.password.isEmpty {
                                        Button("Clear Saved Login") {
                                            viewModel.clearSavedCredentials()
                                        }
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 40)
                            }
                        } else {
                            // iPhone: Original layout
                            VStack(spacing: 20) {
                                // Email Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Email")
                                        .font(.system(size: deviceService.headlineFontSize, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    HStack {
                                        Image(systemName: "envelope.fill")
                                            .foregroundColor(.secondary)
                                            .frame(width: 20)
                                        
                                        TextField("Enter your email", text: $viewModel.email)
                                            .textFieldStyle(CustomTextFieldStyle())
                                            .keyboardType(.emailAddress)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .font(.system(size: deviceService.bodyFontSize))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(16)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(deviceService.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: deviceService.cornerRadius)
                                            .stroke(viewModel.isEmailValid || viewModel.email.isEmpty ? Color.primary.opacity(0.2) : Color.red, lineWidth: viewModel.isEmailValid || viewModel.email.isEmpty ? 1 : 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }
                                
                                // Password Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Password")
                                        .font(.system(size: deviceService.headlineFontSize, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    HStack {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.secondary)
                                            .frame(width: 20)
                                        
                                        if viewModel.showPassword {
                                            TextField("Enter your password", text: $viewModel.password)
                                                .textFieldStyle(CustomTextFieldStyle())
                                                .font(.system(size: deviceService.bodyFontSize))
                                                .foregroundColor(.primary)
                                        } else {
                                            SecureField("Enter your password", text: $viewModel.password)
                                                .font(.system(size: deviceService.bodyFontSize))
                                                .foregroundColor(.primary)
                                        }
                                        
                                        Button(action: {
                                            viewModel.showPassword.toggle()
                                        }) {
                                            Image(systemName: viewModel.showPassword ? "eye.slash.fill" : "eye.fill")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(16)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(deviceService.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: deviceService.cornerRadius)
                                            .stroke(viewModel.isPasswordValid || viewModel.password.isEmpty ? Color.primary.opacity(0.2) : Color.red, lineWidth: viewModel.isPasswordValid || viewModel.password.isEmpty ? 1 : 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }
                                
                                // Login Button
                                Button(action: {
                                    Task {
                                        await viewModel.login()
                                    }
                                }) {
                                    HStack {
                                        if case .loading = viewModel.state {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.right")
                                        }
                                        
                                        Text("Sign In")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                                    .background(
                                        viewModel.isFormValid ? Color.blue : Color.gray
                                    )
                                    .cornerRadius(deviceService.cornerRadius)
                                }
                                .disabled(!viewModel.isFormValid || viewModel.state == .loading)
                                
                                // Clear Saved Login Button (only show if credentials exist)
                                if !viewModel.email.isEmpty || !viewModel.password.isEmpty {
                                    Button("Clear Saved Login") {
                                        viewModel.clearSavedCredentials()
                                    }
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            // Error Alert
            if case .error(let message) = viewModel.state {
                VStack {
                    Spacer()
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        
                        Text(message)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        Button("Dismiss") {
                            viewModel.resetState()
                        }
                        .foregroundColor(.white)
                        .font(.system(size: deviceService.isIPad ? 20 : 17, weight: .semibold))
                    }
                    .padding(deviceService.isIPad ? 20 : 16)
                    .background(Color.red.opacity(0.9))
                    .cornerRadius(deviceService.cornerRadius)
                    .padding(.horizontal, deviceService.isIPad ? 40 : 20)
                    .padding(.bottom, deviceService.isIPad ? 32 : 20)
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: viewModel.state)
            }
        }
        .onAppear {
            // Update the viewModel with the correct AuthManager from environment
            viewModel.updateAuthManager(authManager)
        }
        .onReceive(viewModel.$state) { newState in
            if case .success = newState {
                // AuthManager will handle navigation automatically
                print("✅ Login successful, navigating to main app")
            }
        }
        .alert("Environment Switched", isPresented: $showingEnvironmentAlert) {
            Button("OK") { }
        } message: {
            Text("Environment switched to Development. API URL: \(environmentManager.currentAPIURL)")
        }
    }
}

#Preview {
    LoginView()
}

