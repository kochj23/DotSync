//
//  PreferencesView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var syncEngine = SyncEngine.shared

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            CloudProviderView()
                .tabItem {
                    Label("Cloud Storage", systemImage: "cloud")
                }
                .tag(1)

            ProfilesPreferencesView()
                .tabItem {
                    Label("Profiles", systemImage: "folder.badge.gearshape")
                }
                .tag(2)

            SecurityPreferencesView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
                .tag(3)
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @AppStorage("autoSyncEnabled") private var autoSyncEnabled = false
    @AppStorage("syncInterval") private var syncInterval = 30.0 // minutes
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some View {
        Form {
            Section("Sync Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable auto-sync", isOn: .constant(false))
                        .disabled(true)

                    Text("Auto-sync temporarily disabled due to file watching stability issues. Use manual sync for now.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                HStack {
                    Text("Sync interval:")
                    Slider(value: $syncInterval, in: 5...120, step: 5)
                    Text("\(Int(syncInterval)) min")
                        .frame(width: 60, alignment: .trailing)
                }
                .disabled(true)
            }

            Section("Notifications") {
                Toggle("Show sync notifications", isOn: $showNotifications)
                    .help("Notify when syncs complete or conflicts occur")
            }

            Section("Appearance") {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .help("Display Dot Sync icon in menu bar")
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Cloud Provider View

struct CloudProviderView: View {
    @State private var selectedProvider: CloudProviderType = .awsS3
    @State private var bucketName = ""
    @State private var region = "us-east-1"

    // AWS S3 / S3-Compatible
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""
    @State private var endpoint = ""

    // Azure
    @State private var tenantId = ""
    @State private var clientId = ""
    @State private var clientSecret = ""

    // Google Cloud
    @State private var projectId = ""
    @State private var serviceAccountKey = ""

    // NAS
    @State private var serverAddress = ""
    @State private var sharePath = ""
    @State private var username = ""
    @State private var password = ""

    // OneDrive / Google Drive
    @State private var refreshToken = ""

    @State private var testingConnection = false
    @State private var connectionResult: String?

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Cloud Storage:", selection: $selectedProvider) {
                    ForEach(CloudProviderType.allCases, id: \.self) { provider in
                        HStack {
                            Image(systemName: provider.icon)
                            Text(provider.rawValue)
                        }
                        .tag(provider)
                    }
                }
            }

            Section("Configuration") {
                switch selectedProvider {
                case .awsS3, .s3Compatible, .googleCloud:
                    TextField("Bucket Name:", text: $bucketName)
                        .help("S3 bucket or GCS bucket name")
                case .azureBlob:
                    TextField("Container Name:", text: $bucketName)
                        .help("Azure Blob container name")
                case .iCloud:
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Folder Name or Path:", text: $bucketName)
                            .help("Folder name (e.g., 'DotFiles') or full path")

                        Text("Examples: 'DotFiles' or full path like '/Users/username/Library/Mobile Documents/com~apple~CloudDocs/DotFiles'")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("If you created a folder in Finder, just enter its name. The app will search common iCloud Drive locations.")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                case .nas:
                    TextField("Share Path:", text: $sharePath)
                        .help("NAS share path (e.g., /volume1/backup)")
                case .oneDrive, .googleDrive:
                    TextField("Folder ID:", text: $bucketName)
                        .help("Parent folder ID in Drive")
                }

                if selectedProvider == .awsS3 || selectedProvider == .s3Compatible {
                    TextField("Region:", text: $region)
                        .help("AWS region (e.g., us-east-1)")
                }

                if selectedProvider == .s3Compatible {
                    TextField("Endpoint URL:", text: $endpoint)
                        .help("S3-compatible endpoint (e.g., https://s3.provider.com)")
                }
            }

            if selectedProvider.requiresCredentials {
                Section("Credentials") {
                    switch selectedProvider {
                    case .awsS3, .s3Compatible:
                        TextField("Access Key ID:", text: $accessKeyId)
                        SecureField("Secret Access Key:", text: $secretAccessKey)

                    case .azureBlob:
                        TextField("Tenant ID:", text: $tenantId)
                        TextField("Client ID:", text: $clientId)
                        SecureField("Client Secret:", text: $clientSecret)

                    case .googleCloud:
                        TextField("Project ID:", text: $projectId)
                        SecureField("Service Account Key or Access Token:", text: $serviceAccountKey)
                            .help("Paste entire service account JSON or a pre-generated access token")

                    case .nas:
                        TextField("Server Address:", text: $serverAddress)
                            .help("NAS server address (e.g., 192.168.1.100 or nas.local)")
                        TextField("Username:", text: $username)
                        SecureField("Password:", text: $password)

                    case .oneDrive, .googleDrive:
                        TextField("Client ID:", text: $clientId)
                        SecureField("Client Secret:", text: $clientSecret)
                        SecureField("Refresh Token:", text: $refreshToken)
                            .help("OAuth refresh token from authorization flow")

                    case .iCloud:
                        EmptyView()
                    }

                    Text("Credentials are stored securely in macOS Keychain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(testingConnection || !isConfigurationValid)

                    if testingConnection {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    if let result = connectionResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("✅") ? .green : .red)
                    }
                }

                Button("Save") {
                    saveConfiguration()
                }
                .disabled(!isConfigurationValid)
            }
        }
        .padding()
    }

    private var isConfigurationValid: Bool {
        switch selectedProvider {
        case .awsS3, .s3Compatible:
            return !bucketName.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty
        case .azureBlob:
            return !bucketName.isEmpty && !tenantId.isEmpty && !clientId.isEmpty && !clientSecret.isEmpty
        case .googleCloud:
            return !bucketName.isEmpty && !projectId.isEmpty && !serviceAccountKey.isEmpty
        case .iCloud:
            return !bucketName.isEmpty
        case .nas:
            return !sharePath.isEmpty && !serverAddress.isEmpty && !username.isEmpty && !password.isEmpty
        case .oneDrive, .googleDrive:
            return !bucketName.isEmpty && !clientId.isEmpty && !clientSecret.isEmpty && !refreshToken.isEmpty
        }
    }

    private func testConnection() {
        testingConnection = true
        connectionResult = nil

        Task {
            do {
                let (config, credentials) = buildConfiguration()
                let provider = createProvider(config: config, credentials: credentials)

                let success = try await provider.testConnection()

                await MainActor.run {
                    connectionResult = success ? "✅ Connection successful" : "❌ Connection failed"
                    testingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionResult = "❌ Error: \(error.localizedDescription)"
                    testingConnection = false
                }
            }
        }
    }

    private func saveConfiguration() {
        let (config, credentials) = buildConfiguration()
        SyncEngine.shared.configure(provider: config, credentials: credentials)
        connectionResult = "✅ Configuration saved"
    }

    private func buildConfiguration() -> (CloudProviderConfig, CloudCredentials?) {
        let config = CloudProviderConfig(
            type: selectedProvider,
            name: selectedProvider.rawValue,
            bucket: selectedProvider == .nas ? sharePath : bucketName,
            region: region.isEmpty ? nil : region,
            endpoint: endpoint.isEmpty ? nil : endpoint
        )

        let credentials: CloudCredentials?

        switch selectedProvider {
        case .awsS3, .s3Compatible:
            credentials = CloudCredentials.aws(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey
            )

        case .azureBlob:
            credentials = CloudCredentials.azure(
                tenantId: tenantId,
                clientId: clientId,
                clientSecret: clientSecret
            )

        case .googleCloud:
            credentials = CloudCredentials.gcp(
                projectId: projectId,
                serviceAccountKey: serviceAccountKey
            )

        case .nas:
            credentials = CloudCredentials.nas(
                serverAddress: serverAddress,
                sharePath: sharePath,
                username: username,
                password: password
            )

        case .oneDrive:
            credentials = CloudCredentials.oneDrive(
                clientId: clientId,
                clientSecret: clientSecret,
                refreshToken: refreshToken
            )

        case .googleDrive:
            credentials = CloudCredentials.googleDrive(
                clientId: clientId,
                clientSecret: clientSecret,
                refreshToken: refreshToken
            )

        case .iCloud:
            credentials = CloudCredentials.iCloud
        }

        return (config, credentials)
    }

    private func createProvider(config: CloudProviderConfig, credentials: CloudCredentials?) -> CloudStorageProtocol {
        switch selectedProvider {
        case .awsS3, .s3Compatible:
            return S3Provider(config: config, credentials: credentials)

        case .azureBlob:
            return AzureBlobProvider(config: config, credentials: credentials)

        case .googleCloud:
            return GCPProvider(config: config, credentials: credentials)

        case .iCloud:
            return iCloudProvider(config: config, credentials: credentials)

        case .nas:
            return NASProvider(config: config, credentials: credentials)

        case .oneDrive:
            return OneDriveProvider(config: config, credentials: credentials)

        case .googleDrive:
            return GoogleDriveProvider(config: config, credentials: credentials)
        }
    }
}

// MARK: - Profiles Preferences

struct ProfilesPreferencesView: View {
    @StateObject private var profileManager = ProfileManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync Profiles")
                .font(.headline)

            Text("Choose which config files to sync for different scenarios")
                .font(.subheadline)
                .foregroundColor(.secondary)

            List(profileManager.profiles) { profile in
                ProfileRow(profile: profile, isActive: profile.id == profileManager.activeProfile.id)
                    .onTapGesture {
                        profileManager.setActiveProfile(profile)
                    }
            }

            Spacer()
        }
        .padding()
    }
}

struct ProfileRow: View {
    let profile: SyncProfile
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                Text(profile.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(profile.includedCategories.count) categories")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Security Preferences

struct SecurityPreferencesView: View {
    @AppStorage("scanForCredentials") private var scanForCredentials = true
    @AppStorage("encryptCloudStorage") private var encryptCloudStorage = false
    @AppStorage("createBackups") private var createBackups = true
    @AppStorage("backupCount") private var backupCount = 5.0

    var body: some View {
        Form {
            Section("Security Scanning") {
                Toggle("Scan for credentials before sync", isOn: $scanForCredentials)
                    .help("Automatically detect and exclude files with API keys or passwords")
            }

            Section("Encryption") {
                Toggle("Encrypt files in cloud storage", isOn: $encryptCloudStorage)
                    .help("Use AES-256-GCM encryption (key stored in Keychain)")

                if encryptCloudStorage {
                    Text("Files will be encrypted before upload. Encryption key is stored in macOS Keychain and never uploaded.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Backups") {
                Toggle("Create backups before overwriting", isOn: $createBackups)
                    .help("Backup files before downloading from cloud")

                HStack {
                    Text("Keep last \(Int(backupCount)) backups")
                    Slider(value: $backupCount, in: 1...10, step: 1)
                }
                .disabled(!createBackups)
            }

            Spacer()
        }
        .padding()
    }
}
