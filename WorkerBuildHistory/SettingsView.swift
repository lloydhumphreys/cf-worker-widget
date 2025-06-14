import SwiftUI

extension Notification.Name {
    static let apiKeyUpdated = Notification.Name("apiKeyUpdated")
}

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @StateObject private var workersViewModel = WorkersViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        TabView {
            ApiKeysView(apiKey: $apiKey, errorMessage: $errorMessage)
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }
            
            WorkersView(viewModel: workersViewModel)
                .tabItem {
                    Label("Workers & Pages", systemImage: "server.rack")
                }
        }
        .frame(width: 500, height: 400)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save & Close") {
                    saveAllSettings()
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadApiKey()
            Task {
                await workersViewModel.loadAccounts()
                // Load saved visibility settings after accounts are loaded
                loadVisibilitySettings()
            }
        }
        .onDisappear {
            workersViewModel.deactivate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeyUpdated)) { _ in
            Task {
                await workersViewModel.loadAccounts()
            }
        }
    }
    
    private func loadApiKey() {
        do {
            apiKey = try KeychainManager.shared.getApiKey() ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func saveAllSettings() {
        // Save API key if it has changed
        if !apiKey.isEmpty {
            do {
                try KeychainManager.shared.saveApiKey(apiKey)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        
        // Save visibility settings directly
        saveVisibilitySettings()
        
        // Update build history with the new settings (force refresh since user explicitly saved)
        Task {
            await DataManager.shared.refreshBuildHistory(force: true)
        }
    }
    
    private func saveVisibilitySettings() {
        let workerSettings = workersViewModel.workers.reduce(into: [String: Bool]()) { result, worker in
            result[worker.id] = worker.isVisible
        }
        
        let pagesSettings = workersViewModel.pagesProjects.reduce(into: [String: Bool]()) { result, project in
            result[project.id] = project.isVisible
        }
        
        UserDefaults.standard.set(workerSettings, forKey: "workerVisibilitySettings")
        UserDefaults.standard.set(pagesSettings, forKey: "pagesVisibilitySettings")
    }
    
    private func loadVisibilitySettings() {
        guard let workerSettings = UserDefaults.standard.dictionary(forKey: "workerVisibilitySettings") as? [String: Bool],
              let pagesSettings = UserDefaults.standard.dictionary(forKey: "pagesVisibilitySettings") as? [String: Bool] else {
            return
        }
        
        // Apply saved settings to workers
        for i in workersViewModel.workers.indices {
            if let savedVisibility = workerSettings[workersViewModel.workers[i].id] {
                workersViewModel.workers[i].isVisible = savedVisibility
            }
        }
        
        // Apply saved settings to pages projects
        for i in workersViewModel.pagesProjects.indices {
            if let savedVisibility = pagesSettings[workersViewModel.pagesProjects[i].id] {
                workersViewModel.pagesProjects[i].isVisible = savedVisibility
            }
        }
    }
}

struct ApiKeysView: View {
    @Binding var apiKey: String
    @Binding var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField("Cloudflare API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            saveApiKey()
                        }
                    
                    Button("Save") {
                        saveApiKey()
                    }
                    .disabled(apiKey.isEmpty)
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
            
            // Trigger loading of accounts after successful save
            NotificationCenter.default.post(name: .apiKeyUpdated, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkersView: View {
    @ObservedObject var viewModel: WorkersViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Account Picker
            if !viewModel.accounts.isEmpty {
                Picker("Account", selection: $viewModel.selectedAccountId) {
                    ForEach(viewModel.accounts, id: \.id) { account in
                        Text(account.name).tag(account.id as String?)
                    }
                }
                .pickerStyle(PopUpButtonPickerStyle())
                .onChange(of: viewModel.selectedAccountId) { id in
                    guard viewModel.isActive, let id = id else { return }
                    Task {
                        await viewModel.loadWorkers(for: id)
                        await viewModel.loadPagesProjects(for: id)
                    }
                }
                .padding(.horizontal)
            }
            
            // Enable/Disable All
            HStack {
                Button("Enable All") {
                    viewModel.enableAll()
                    for i in viewModel.pagesProjects.indices {
                        viewModel.pagesProjects[i].isVisible = true
                    }
                }
                Button("Disable All") {
                    viewModel.disableAll()
                    for i in viewModel.pagesProjects.indices {
                        viewModel.pagesProjects[i].isVisible = false
                    }
                }
            }
            .padding(.horizontal)
            
            // Unified List
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                List {
                    if !viewModel.workers.isEmpty {
                        Section(header: Text("Workers")) {
                            ForEach($viewModel.workers) { $worker in
                                HStack {
                                    Text(worker.id)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { worker.isVisible },
                                        set: { newValue in
                                            guard viewModel.isActive else { return }
                                            worker.isVisible = newValue
                                        }
                                    ))
                                    .disabled(!viewModel.isActive)
                                }
                            }
                        }
                    }
                    if !viewModel.pagesProjects.isEmpty {
                        Section(header: Text("Pages")) {
                            ForEach($viewModel.pagesProjects) { $project in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(project.name)
                                        Text(project.subdomain)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { project.isVisible },
                                        set: { newValue in
                                            guard viewModel.isActive else { return }
                                            project.isVisible = newValue
                                        }
                                    ))
                                    .disabled(!viewModel.isActive)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.vertical)
    }
}

#Preview {
    SettingsView()
} 