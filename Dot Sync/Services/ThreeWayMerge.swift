//
//  ThreeWayMerge.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/6/26.
//

import Foundation

/// Smart three-way merge implementation
class ThreeWayMerge {

    /// Perform three-way merge
    static func merge(ancestor: String, local: String, remote: String) -> MergeResult {
        let ancestorLines = ancestor.components(separatedBy: .newlines)
        let localLines = local.components(separatedBy: .newlines)
        let remoteLines = remote.components(separatedBy: .newlines)

        var conflicts: [MergeConflict] = []
        var mergedLines: [String] = []
        var hasConflicts = false

        // Simple line-by-line comparison
        let maxLines = max(ancestorLines.count, localLines.count, remoteLines.count)

        for i in 0..<maxLines {
            let ancestorLine = i < ancestorLines.count ? ancestorLines[i] : ""
            let localLine = i < localLines.count ? localLines[i] : ""
            let remoteLine = i < remoteLines.count ? remoteLines[i] : ""

            if localLine == remoteLine {
                // Both made same change or no change - use either
                mergedLines.append(localLine)
            } else if localLine == ancestorLine {
                // Only remote changed - use remote
                mergedLines.append(remoteLine)
            } else if remoteLine == ancestorLine {
                // Only local changed - use local
                mergedLines.append(localLine)
            } else {
                // Both changed differently - conflict
                hasConflicts = true
                let conflict = MergeConflict(
                    lineNumber: i + 1,
                    ancestorLine: ancestorLine,
                    localLine: localLine,
                    remoteLine: remoteLine
                )
                conflicts.append(conflict)

                // Add conflict markers to merged output
                mergedLines.append("<<<<<<< LOCAL")
                mergedLines.append(localLine)
                mergedLines.append("=======")
                mergedLines.append(remoteLine)
                mergedLines.append(">>>>>>> REMOTE")
            }
        }

        let mergedContent = mergedLines.joined(separator: "\n")

        return MergeResult(
            mergedContent: mergedContent,
            hasConflicts: hasConflicts,
            conflicts: conflicts,
            autoMergedLines: mergedLines.count - (conflicts.count * 5) // Subtract conflict markers
        )
    }

    /// Check if files can be auto-merged
    static func canAutoMerge(ancestor: String, local: String, remote: String) -> Bool {
        let result = merge(ancestor: ancestor, local: local, remote: remote)
        return !result.hasConflicts
    }
}

/// Result of three-way merge
struct MergeResult {
    let mergedContent: String
    let hasConflicts: Bool
    let conflicts: [MergeConflict]
    let autoMergedLines: Int

    var summary: String {
        if hasConflicts {
            return "\(conflicts.count) conflicts, \(autoMergedLines) lines auto-merged"
        } else {
            return "Successfully auto-merged \(autoMergedLines) lines"
        }
    }
}

