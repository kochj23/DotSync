//
//  SyncProfileTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class SyncProfileTests: XCTestCase {

    // MARK: - Profile Matching

    func testFullProfileMatchesAllCategories() {
        let profile = SyncProfile.full
        for category in ConfigCategory.allCases {
            let file = makeFile(category: category)
            XCTAssertTrue(profile.matches(file),
                          "Full profile should match \(category.rawValue)")
        }
    }

    func testMinimalProfileMatchesOnlyShellAndGit() {
        let profile = SyncProfile.minimal

        XCTAssertTrue(profile.matches(makeFile(category: .shell)))
        XCTAssertTrue(profile.matches(makeFile(category: .git)))
        XCTAssertFalse(profile.matches(makeFile(category: .editor)))
        XCTAssertFalse(profile.matches(makeFile(category: .cloud)))
        XCTAssertFalse(profile.matches(makeFile(category: .docker)))
    }

    func testWorkProfileCategories() {
        let profile = SyncProfile.work

        XCTAssertTrue(profile.matches(makeFile(category: .shell)))
        XCTAssertTrue(profile.matches(makeFile(category: .git)))
        XCTAssertTrue(profile.matches(makeFile(category: .cloud)))
        XCTAssertTrue(profile.matches(makeFile(category: .claude)))
        XCTAssertTrue(profile.matches(makeFile(category: .docker)))
        XCTAssertFalse(profile.matches(makeFile(category: .editor)))
        XCTAssertFalse(profile.matches(makeFile(category: .documentation)))
    }

    func testHomeProfileCategories() {
        let profile = SyncProfile.home

        XCTAssertTrue(profile.matches(makeFile(category: .shell)))
        XCTAssertTrue(profile.matches(makeFile(category: .git)))
        XCTAssertTrue(profile.matches(makeFile(category: .editor)))
        XCTAssertTrue(profile.matches(makeFile(category: .claude)))
        XCTAssertFalse(profile.matches(makeFile(category: .docker)))
        XCTAssertFalse(profile.matches(makeFile(category: .cloud)))
    }

    // MARK: - Explicit Include/Exclude

    func testExplicitExclusion() {
        var profile = SyncProfile.full
        profile.excludedFiles = [".zshrc"]

        let file = makeFile(relativePath: ".zshrc", category: .shell)
        XCTAssertFalse(profile.matches(file),
                       "Explicitly excluded files should not match")
    }

    func testExplicitInclusion() {
        let profile = SyncProfile(
            name: "Custom",
            description: "Test",
            includedCategories: [],  // No categories
            includedFiles: [".custom-config"]
        )

        let file = makeFile(relativePath: ".custom-config", category: .unknown)
        XCTAssertTrue(profile.matches(file),
                      "Explicitly included files should match even without category")
    }

    func testExclusionOverridesInclusion() {
        let profile = SyncProfile(
            name: "Test",
            description: "Test",
            includedCategories: [.shell],
            includedFiles: [],
            excludedFiles: [".zshrc"]
        )

        let file = makeFile(relativePath: ".zshrc", category: .shell)
        XCTAssertFalse(profile.matches(file),
                       "Exclusion should override category match")
    }

    // MARK: - Default Profiles

    func testDefaultProfilesNotEmpty() {
        XCTAssertFalse(SyncProfile.defaultProfiles.isEmpty)
    }

    func testDefaultProfilesContainFull() {
        let hasFullProfile = SyncProfile.defaultProfiles.contains { $0.name == "Full" }
        XCTAssertTrue(hasFullProfile)
    }

    func testDefaultProfilesContainMinimal() {
        let hasMinimalProfile = SyncProfile.defaultProfiles.contains { $0.name == "Minimal" }
        XCTAssertTrue(hasMinimalProfile)
    }

    func testFullProfileIsDefault() {
        XCTAssertTrue(SyncProfile.full.isDefault)
    }

    func testOtherProfilesAreNotDefault() {
        XCTAssertFalse(SyncProfile.minimal.isDefault)
        XCTAssertFalse(SyncProfile.work.isDefault)
        XCTAssertFalse(SyncProfile.home.isDefault)
    }

    // MARK: - Codable

    func testSyncProfileCodable() throws {
        let original = SyncProfile.work
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncProfile.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.includedCategories, original.includedCategories)
        XCTAssertEqual(decoded.isDefault, original.isDefault)
    }

    // MARK: - Hashable & Equatable

    func testProfileEquality() {
        let profile1 = SyncProfile.full
        let profile2 = profile1  // Same instance copy
        XCTAssertEqual(profile1, profile2)
    }

    func testProfileInequality() {
        let profile1 = SyncProfile.full
        let profile2 = SyncProfile.minimal
        XCTAssertNotEqual(profile1, profile2)
    }

    func testProfileHashable() {
        var set: Set<SyncProfile> = []
        set.insert(SyncProfile.full)
        set.insert(SyncProfile.minimal)
        set.insert(SyncProfile.work)
        XCTAssertEqual(set.count, 3)
    }

    // MARK: - Helpers

    private func makeFile(
        relativePath: String = ".zshrc",
        category: ConfigCategory = .shell
    ) -> ConfigFile {
        ConfigFile(
            path: "/Users/test/\(relativePath)",
            relativePath: relativePath,
            filename: relativePath,
            category: category,
            size: 100,
            lastModified: Date(),
            checksum: "abc",
            isSafeToSync: true,
            syncPriority: .medium
        )
    }
}
