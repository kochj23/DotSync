//
//  DiffView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

/// Line-by-line diff viewer
struct DiffView: View {
    let content: String
    let otherContent: String
    let title: String

    @State private var diff: [DiffLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(title)
                .font(.headline)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))

            Divider()

            // Diff content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diff) { line in
                        DiffLineView(line: line)
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear {
            diff = computeDiff()
        }
    }

    /// Compute line-by-line diff
    private func computeDiff() -> [DiffLine] {
        let leftLines = content.components(separatedBy: .newlines)
        let rightLines = otherContent.components(separatedBy: .newlines)

        var result: [DiffLine] = []

        // Simple diff algorithm (Myers algorithm would be better for production)
        let maxLines = max(leftLines.count, rightLines.count)

        for i in 0..<maxLines {
            let leftLine = i < leftLines.count ? leftLines[i] : nil
            let rightLine = i < rightLines.count ? rightLines[i] : nil

            if let left = leftLine, let right = rightLine {
                if left == right {
                    // Lines match
                    result.append(DiffLine(lineNumber: i + 1, content: left, changeType: .unchanged))
                } else {
                    // Lines differ
                    result.append(DiffLine(lineNumber: i + 1, content: left, changeType: .modified))
                }
            } else if let left = leftLine {
                // Line only in left (deleted in right)
                result.append(DiffLine(lineNumber: i + 1, content: left, changeType: .removed))
            } else if let right = rightLine {
                // Line only in right (added)
                result.append(DiffLine(lineNumber: i + 1, content: right, changeType: .added))
            }
        }

        return result
    }
}

/// Single line in diff view
struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Line number
            Text("\(line.lineNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.leading, 4)

            // Change indicator
            Text(line.changeType.symbol)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(line.changeType.color)
                .frame(width: 20)

            // Line content
            Text(line.content)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
        .background(line.changeType.backgroundColor)
        .padding(.horizontal, 4)
    }
}

/// Diff line model
struct DiffLine: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let content: String
    let changeType: DiffChangeType
}

/// Type of change in diff
enum DiffChangeType {
    case unchanged
    case added
    case removed
    case modified

    var symbol: String {
        switch self {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "-"
        case .modified: return "~"
        }
    }

    var color: Color {
        switch self {
        case .unchanged: return .primary
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .unchanged: return .clear
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .modified: return Color.orange.opacity(0.15)
        }
    }
}
