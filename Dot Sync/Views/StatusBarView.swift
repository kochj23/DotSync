//
//  StatusBarView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/12/26.
//

import SwiftUI

/// Status bar showing app state at bottom of window
struct StatusBarView: View {
    @ObservedObject var syncEngine: SyncEngine
    @ObservedObject var discoveryService: FileDiscoveryService

    var body: some View {
        HStack(spacing: 12) {
            // Cloud connection status
            HStack(spacing: 6) {
                Image(systemName: cloudIcon)
                    .foregroundColor(cloudColor)
                    .font(.caption)

                Text(cloudStatusText)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .help(cloudTooltip)

            Divider()
                .frame(height: 14)

            // Machine role
            HStack(spacing: 6) {
                Image(systemName: roleIcon)
                    .foregroundColor(roleColor)
                    .font(.caption)

                Text(syncEngine.machineRole.rawValue)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .help(syncEngine.machineRole.description)

            Divider()
                .frame(height: 14)

            // Last sync time
            if let lastSync = syncEngine.lastSyncDate {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text("Last sync: \(lastSync.relativeFormatted)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help("Last synced: \(lastSync.formatted())")

                Divider()
                    .frame(height: 14)
            }

            // File count
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Text("\(discoveryService.discoveredFiles.count) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .help("\(discoveryService.discoveredFiles.count) configuration files tracked")

            Spacer()

            // Sync status indicator
            if syncEngine.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)

                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor).opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Computed Properties

    private var cloudIcon: String {
        if syncEngine.currentProvider != nil {
            return "cloud.fill"
        } else {
            return "cloud.slash"
        }
    }

    private var cloudColor: Color {
        if syncEngine.currentProvider != nil {
            return .green
        } else {
            return .red
        }
    }

    private var cloudStatusText: String {
        if let provider = syncEngine.currentProvider {
            return provider.name
        } else {
            return "Not Connected"
        }
    }

    private var cloudTooltip: String {
        if let provider = syncEngine.currentProvider {
            return "Connected to \(provider.name)"
        } else {
            return "No cloud storage configured"
        }
    }

    private var roleIcon: String {
        switch syncEngine.machineRole {
        case .master:
            return "arrow.up.arrow.down.circle.fill"
        case .client:
            return "arrow.down.circle.fill"
        }
    }

    private var roleColor: Color {
        switch syncEngine.machineRole {
        case .master:
            return .blue
        case .client:
            return .orange
        }
    }
}

// MARK: - Date Extension for Relative Formatting

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
