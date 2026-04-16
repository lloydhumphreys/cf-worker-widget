import SwiftUI
import ServiceManagement
import Sparkle

extension Notification.Name {
    static let apiKeyUpdated = Notification.Name("apiKeyUpdated")
}

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @StateObject private var workersViewModel = WorkersViewModel()
    
    var body: some View {
        TabView {
            ConnectionView(apiKey: $apiKey, errorMessage: $errorMessage)
                .tabItem {
                    Label("Cloudflare Connection", systemImage: "cloud")
                }
            
            WorkersView(viewModel: workersViewModel)
                .tabItem {
                    Label("Workers & Pages", systemImage: "server.rack")
                }

            DebugSettingsView()
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }
        }
        .frame(width: 620, height: 460)
        .onAppear {
            loadApiKey()
            Task {
                await workersViewModel.loadAccounts()
            }
        }
        .onDisappear {
            workersViewModel.deactivate()
            Task {
                await DataManager.shared.refreshBuildHistory(force: true)
            }
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
            DiagnosticsManager.shared.recordError(error, category: "settings", message: "Failed to load API key from keychain")
        }
    }
}

struct ConnectionView: View {
    @Binding var apiKey: String
    @Binding var errorMessage: String?
    @State private var refreshMinutes: Int = DataManager.shared.refreshIntervalMinutes
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

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

            Section {
                Picker("Refresh Interval", selection: $refreshMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
                .onChange(of: refreshMinutes) { _, newValue in
                    DataManager.shared.refreshIntervalMinutes = newValue
                }
            } header: {
                Text("Auto Refresh")
            } footer: {
                Text("How often build history refreshes automatically. The refresh button always fetches immediately.")
            }

            Section {
                Toggle("Start at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            } footer: {
                Text("Automatically start WorkerWidget when you log in.")
            }

            Section {
                CheckForUpdatesView()
            } footer: {
                Text("Check for new versions of WorkerWidget.")
            }
        }
        .padding()
    }

    private func saveApiKey() {
        do {
            try KeychainManager.shared.saveApiKey(apiKey)
            CloudflareService.shared.clearCachedApiKey()
            errorMessage = nil
            DiagnosticsManager.shared.log(.info, category: "settings", message: "Saved Cloudflare API key")

            // Trigger loading of accounts after successful save
            NotificationCenter.default.post(name: .apiKeyUpdated, object: nil)
            Task {
                await DataManager.shared.refreshBuildHistory(force: true)
            }
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsManager.shared.recordError(error, category: "settings", message: "Failed to save API key to keychain")
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
                .onChange(of: viewModel.selectedAccountId) { _, id in
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
                    viewModel.setAllVisibility(true)
                }
                Button("Disable All") {
                    viewModel.setAllVisibility(false)
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
                                            AppPreferences.saveVisibilitySettings(
                                                workers: viewModel.workers,
                                                pagesProjects: viewModel.pagesProjects
                                            )
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
                                            AppPreferences.saveVisibilitySettings(
                                                workers: viewModel.workers,
                                                pagesProjects: viewModel.pagesProjects
                                            )
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

// MARK: - Sparkle Update View

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel = CheckForUpdatesViewModel()

    var body: some View {
        Button("Check for Updates...") {
            (NSApp.delegate as? AppDelegate)?.updaterController.checkForUpdates(nil)
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var observation: NSKeyValueObservation?

    init() {
        guard let updater = (NSApp.delegate as? AppDelegate)?.updaterController.updater else { return }
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }
}

#Preview {
    SettingsView()
}
