//
//  ThreeWayMergeTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class ThreeWayMergeTests: XCTestCase {

    // MARK: - No Changes

    func testNoChanges() {
        let ancestor = "line1\nline2\nline3"
        let local = "line1\nline2\nline3"
        let remote = "line1\nline2\nline3"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertFalse(result.hasConflicts)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.mergedContent, "line1\nline2\nline3")
    }

    // MARK: - Only Local Changes

    func testOnlyLocalChanged() {
        let ancestor = "line1\nline2\nline3"
        let local = "line1\nmodified\nline3"
        let remote = "line1\nline2\nline3"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertFalse(result.hasConflicts)
        XCTAssertEqual(result.mergedContent, "line1\nmodified\nline3")
    }

    // MARK: - Only Remote Changes

    func testOnlyRemoteChanged() {
        let ancestor = "line1\nline2\nline3"
        let local = "line1\nline2\nline3"
        let remote = "line1\nremote-change\nline3"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertFalse(result.hasConflicts)
        XCTAssertEqual(result.mergedContent, "line1\nremote-change\nline3")
    }

    // MARK: - Both Changed Same Way

    func testBothChangedSameWay() {
        let ancestor = "line1\nline2\nline3"
        let local = "line1\nsame-change\nline3"
        let remote = "line1\nsame-change\nline3"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertFalse(result.hasConflicts)
        XCTAssertEqual(result.mergedContent, "line1\nsame-change\nline3")
    }

    // MARK: - Both Changed Differently (Conflict)

    func testBothChangedDifferently() {
        let ancestor = "line1\nline2\nline3"
        let local = "line1\nlocal-change\nline3"
        let remote = "line1\nremote-change\nline3"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts.first?.lineNumber, 2)
        XCTAssertEqual(result.conflicts.first?.localLine, "local-change")
        XCTAssertEqual(result.conflicts.first?.remoteLine, "remote-change")
    }

    // MARK: - Conflict Markers

    func testConflictMarkersInOutput() {
        let ancestor = "A\nB\nC"
        let local = "A\nX\nC"
        let remote = "A\nY\nC"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertTrue(result.mergedContent.contains("<<<<<<< LOCAL"))
        XCTAssertTrue(result.mergedContent.contains("======="))
        XCTAssertTrue(result.mergedContent.contains(">>>>>>> REMOTE"))
        XCTAssertTrue(result.mergedContent.contains("X"))
        XCTAssertTrue(result.mergedContent.contains("Y"))
    }

    // MARK: - Mixed Changes and Conflicts

    func testMixedChangesAndConflicts() {
        let ancestor = "line1\nline2\nline3\nline4"
        let local = "line1\nlocal2\nline3\nlocal4"
        let remote = "line1\nremote2\nline3\nline4"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        // line2: both changed differently -> conflict
        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(result.conflicts.count, 1)
        // line4: only local changed -> local wins
        XCTAssertTrue(result.mergedContent.contains("local4"))
    }

    // MARK: - Different Length Files

    func testLocalAddsLine() {
        let ancestor = "line1\nline2"
        let local = "line1\nline2\nline3"
        let remote = "line1\nline2"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertFalse(result.hasConflicts)
        XCTAssertTrue(result.mergedContent.contains("line3"))
    }

    func testRemoteAddsLine() {
        let ancestor = "line1\nline2"
        let local = "line1\nline2"
        let remote = "line1\nline2\nnew-remote-line"

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        XCTAssertFalse(result.hasConflicts)
        XCTAssertTrue(result.mergedContent.contains("new-remote-line"))
    }

    // MARK: - Empty Inputs

    func testAllEmpty() {
        let result = ThreeWayMerge.merge(ancestor: "", local: "", remote: "")
        XCTAssertFalse(result.hasConflicts)
    }

    func testEmptyAncestorBothAddedSame() {
        let result = ThreeWayMerge.merge(ancestor: "", local: "new", remote: "new")
        XCTAssertFalse(result.hasConflicts)
        XCTAssertEqual(result.mergedContent, "new")
    }

    func testEmptyAncestorBothAddedDifferent() {
        let result = ThreeWayMerge.merge(ancestor: "", local: "local", remote: "remote")
        XCTAssertTrue(result.hasConflicts)
    }

    // MARK: - canAutoMerge

    func testCanAutoMergeTrue() {
        let canMerge = ThreeWayMerge.canAutoMerge(
            ancestor: "A\nB", local: "A\nX", remote: "A\nB"
        )
        XCTAssertTrue(canMerge)
    }

    func testCanAutoMergeFalse() {
        let canMerge = ThreeWayMerge.canAutoMerge(
            ancestor: "A\nB", local: "A\nX", remote: "A\nY"
        )
        XCTAssertFalse(canMerge)
    }

    // MARK: - MergeResult Summary

    func testMergeResultSummaryNoConflicts() {
        let result = ThreeWayMerge.merge(
            ancestor: "A\nB", local: "A\nX", remote: "A\nB"
        )
        XCTAssertTrue(result.summary.contains("auto-merged"))
        XCTAssertFalse(result.summary.contains("conflict"))
    }

    func testMergeResultSummaryWithConflicts() {
        let result = ThreeWayMerge.merge(
            ancestor: "A\nB", local: "A\nX", remote: "A\nY"
        )
        XCTAssertTrue(result.summary.lowercased().contains("conflict"))
    }

    // MARK: - MergeConflict

    func testMergeConflictDescription() {
        let conflict = MergeConflict(
            lineNumber: 5,
            ancestorLine: "old",
            localLine: "local",
            remoteLine: "remote"
        )

        XCTAssertTrue(conflict.description.contains("Line 5"))
        XCTAssertTrue(conflict.description.contains("old"))
        XCTAssertTrue(conflict.description.contains("local"))
        XCTAssertTrue(conflict.description.contains("remote"))
    }

    func testMergeConflictEmptyLines() {
        let conflict = MergeConflict(
            lineNumber: 1,
            ancestorLine: "",
            localLine: "",
            remoteLine: ""
        )

        XCTAssertTrue(conflict.description.contains("(empty)"))
    }

    // MARK: - Real-World Shell Config Merge

    func testRealWorldZshrcMerge() {
        let ancestor = """
        export PATH="/usr/local/bin:$PATH"
        alias ll='ls -la'
        export EDITOR=vim
        """
        let local = """
        export PATH="/usr/local/bin:$PATH"
        alias ll='ls -la'
        export EDITOR=nvim
        """
        let remote = """
        export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
        alias ll='ls -la'
        export EDITOR=vim
        """

        let result = ThreeWayMerge.merge(ancestor: ancestor, local: local, remote: remote)

        // PATH changed only on remote, EDITOR changed only on local -> auto-merge
        XCTAssertFalse(result.hasConflicts)
        XCTAssertTrue(result.mergedContent.contains("/opt/homebrew/bin"))
        XCTAssertTrue(result.mergedContent.contains("EDITOR=nvim"))
    }
}
