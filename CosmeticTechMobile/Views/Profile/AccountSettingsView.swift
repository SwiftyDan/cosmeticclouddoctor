import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showConfirmation: Bool = false
    @State private var isProcessing: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Account Settings")
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, 8)

                Button(action: {
                    showConfirmation = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.white)
                        Text("Deactivate Account")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .cornerRadius(12)
                    .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                if isProcessing {
                    ProgressView()
                        .padding(.top, 8)
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Account Settings")
        .alert(isPresented: $showConfirmation) {
            Alert(
                title: Text("Deactivate account"),
                message: Text("Deactivating your account will log you out and remove access. This action cannot be undone. Do you want to continue?"),
                primaryButton: .destructive(Text("Deactivate")) {
                    isProcessing = true
                    Task {
                        await authManager.deactivateAccount()
                        isProcessing = false
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct AccountSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountSettingsView()
            .environmentObject(AuthManager(authService: AuthService()))
    }
}


