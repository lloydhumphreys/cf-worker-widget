import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        TabView {
            ApiKeysView(apiKey: $apiKey, errorMessage: $errorMessage)
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }
            
            // Placeholder for future settings tabs
            Text("More settings coming soon...")
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 500, height: 300)
        .onAppear {
            loadApiKey()
        }
    }
    
    private func loadApiKey() {
        do {
            apiKey = try KeychainManager.shared.getApiKey() ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ApiKeysView: View {
    @Binding var apiKey: String
    @Binding var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                SecureField("Cloudflare API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        saveApiKey()
                    }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            } header: {
                Text("API Configuration")
            } footer: {
                Text("Your API key will be stored securely in the keychain.")
            }
        }
        .padding()
    }
    
    private func saveApiKey() {
        do {
            try KeychainManager.shared.saveApiKey(apiKey)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
} 