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
                Toggle("Enable auto-sync", isOn: $autoSyncEnabled)
                    .help("Automatically sync when files change")

                HStack {
                    Text("Sync interval:")
                    Slider(value: $syncInterval, in: 5...120, step: 5)
                    Text("\(Int(syncInterval)) min")
                        .frame(width: 60, alignment: .trailing)
                }
                .disabled(!autoSyncEnabled)
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
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""
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
                TextField("Bucket/Container Name:", text: $bucketName)
                    .help("S3 bucket, Azure container, or GCS bucket name")

                if selectedProvider == .awsS3 {
                    TextField("Region:", text: $region)
                        .help("AWS region (e.g., us-east-1)")
                }
            }

            if selectedProvider.requiresCredentials {
                Section("Credentials") {
                    TextField("Access Key ID:", text: $accessKeyId)
                    SecureField("Secret Access Key:", text: $secretAccessKey)

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
                    .disabled(bucketName.isEmpty || testingConnection)

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
                .disabled(bucketName.isEmpty)
            }
        }
        .padding()
    }

    private func testConnection() {
        testingConnection = true
        connectionResult = nil

        Task {
            do {
                // Create temporary config and test
                let config = CloudProviderConfig(
                    type: selectedProvider,
                    name: selectedProvider.rawValue,
                    bucket: bucketName,
                    region: region.isEmpty ? nil : region
                )

                let credentials = CloudCredentials.aws(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey
                )

                let provider = S3Provider(config: config, credentials: credentials)
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
        // Save to SyncEngine
        let config = CloudProviderConfig(
            type: selectedProvider,
            name: selectedProvider.rawValue,
            bucket: bucketName,
            region: region.isEmpty ? nil : region
        )

        let credentials = selectedProvider.requiresCredentials ?
            CloudCredentials.aws(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey) : nil

        SyncEngine.shared.configure(provider: config, credentials: credentials)

        connectionResult = "✅ Configuration saved"
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
