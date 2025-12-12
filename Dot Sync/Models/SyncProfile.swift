//
//  SyncProfile.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Sync profile for different machine scenarios
struct SyncProfile: Identifiable, Codable, Hashable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var includedCategories: Set<ConfigCategory>
    var includedFiles: Set<String> // Specific file paths
    var excludedFiles: Set<String> // Specific files to exclude
    var isDefault: Bool

    static func == (lhs: SyncProfile, rhs: SyncProfile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(name: String, description: String,
         includedCategories: Set<ConfigCategory>,
         includedFiles: Set<String> = [],
         excludedFiles: Set<String> = [],
         isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.includedCategories = includedCategories
        self.includedFiles = includedFiles
        self.excludedFiles = excludedFiles
        self.isDefault = isDefault
    }

    /// Check if a config file matches this profile
    func matches(_ file: ConfigFile) -> Bool {
        // Check if explicitly excluded
        if excludedFiles.contains(file.relativePath) {
            return false
        }

        // Check if explicitly included
        if includedFiles.contains(file.relativePath) {
            return true
        }

        // Check by category
        return includedCategories.contains(file.category)
    }

    /// Predefined profiles
    static var full: SyncProfile {
        SyncProfile(
            name: "Full",
            description: "All detected config files",
            includedCategories: Set(ConfigCategory.allCases),
            isDefault: true
        )
    }

    static var minimal: SyncProfile {
        SyncProfile(
            name: "Minimal",
            description: "Just shell and git (quick setup)",
            includedCategories: [.shell, .git]
        )
    }

    static var work: SyncProfile {
        SyncProfile(
            name: "Work",
            description: "Work environment (cloud CLIs, git, claude)",
            includedCategories: [.shell, .git, .cloud, .claude, .docker]
        )
    }

    static var home: SyncProfile {
        SyncProfile(
            name: "Home",
            description: "Personal machine setup",
            includedCategories: [.shell, .git, .editor, .claude]
        )
    }

    static var defaultProfiles: [SyncProfile] {
        [.full, .minimal, .work, .home]
    }
}

/// Profile manager for storing and managing profiles
@MainActor
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    @Published var profiles: [SyncProfile] = []
    @Published var activeProfile: SyncProfile

    private let userDefaults = UserDefaults.standard
    private let profilesKey = "DotSync.Profiles"
    private let activeProfileKey = "DotSync.ActiveProfile"

    init() {
        // Load profiles or use defaults
        let loadedProfiles: [SyncProfile]
        if let data = userDefaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([SyncProfile].self, from: data) {
            loadedProfiles = decoded
        } else {
            loadedProfiles = SyncProfile.defaultProfiles
        }
        self.profiles = loadedProfiles

        // Load active profile
        if let data = userDefaults.data(forKey: activeProfileKey),
           let decoded = try? JSONDecoder().decode(SyncProfile.self, from: data) {
            self.activeProfile = decoded
        } else {
            self.activeProfile = loadedProfiles.first ?? .full
        }
    }

    /// Save profiles to UserDefaults
    func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            userDefaults.set(encoded, forKey: profilesKey)
        }
    }

    /// Save active profile
    func saveActiveProfile() {
        if let encoded = try? JSONEncoder().encode(activeProfile) {
            userDefaults.set(encoded, forKey: activeProfileKey)
        }
    }

    /// Add custom profile
    func addProfile(_ profile: SyncProfile) {
        profiles.append(profile)
        saveProfiles()
    }

    /// Remove profile
    func removeProfile(_ profile: SyncProfile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }

    /// Set active profile
    func setActiveProfile(_ profile: SyncProfile) {
        activeProfile = profile
        saveActiveProfile()
    }

    /// Get files matching active profile
    func filteredFiles(from allFiles: [ConfigFile]) -> [ConfigFile] {
        allFiles.filter { activeProfile.matches($0) }
    }
}
