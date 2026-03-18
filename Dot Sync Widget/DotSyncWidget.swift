//
//  DotSyncWidget.swift
//  Dot Sync Widget
//
//  Created by Jordan Koch on 2/4/26.
//

import WidgetKit
import SwiftUI

// MARK: - Widget Provider

struct DotSyncWidgetProvider: TimelineProvider {
    typealias Entry = DotSyncWidgetEntry

    func placeholder(in context: Context) -> DotSyncWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DotSyncWidgetEntry) -> Void) {
        let data = SharedDataManager.shared.loadSyncData()
        let entry = DotSyncWidgetEntry(date: Date(), syncData: data)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DotSyncWidgetEntry>) -> Void) {
        let data = SharedDataManager.shared.loadSyncData()
        let entry = DotSyncWidgetEntry(date: Date(), syncData: data)

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

/// Small widget view
struct DotSyncWidgetSmallView: View {
    let entry: DotSyncWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Spacer()
                Image(systemName: entry.syncData.status.iconName)
                    .font(.title3)
                    .foregroundColor(statusColor)
            }

            Spacer()

            Text("Dot Sync")
                .font(.headline)
                .lineLimit(1)

            Text(entry.syncData.status.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(entry.syncData.formattedLastSync)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .widgetURL(SharedDataManager.openAppURL)
    }

    private var statusColor: Color {
        switch entry.syncData.status.colorName {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        default: return .gray
        }
    }
}

/// Medium widget view
struct DotSyncWidgetMediumView: View {
    let entry: DotSyncWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Status
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("Dot Sync")
                        .font(.headline)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: entry.syncData.status.iconName)
                        .foregroundColor(statusColor)
                    Text(entry.syncData.status.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text(entry.syncData.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Last sync: \(entry.syncData.formattedLastSync)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Right side - Stats and Action
            VStack(alignment: .trailing, spacing: 8) {
                // Stats
                VStack(alignment: .trailing, spacing: 4) {
                    StatRow(icon: "doc.fill", value: entry.syncData.totalTrackedFiles, label: "Tracked")
                    if entry.syncData.filesNeedingSync > 0 {
                        StatRow(icon: "arrow.triangle.2.circlepath", value: entry.syncData.filesNeedingSync, label: "Pending")
                    }
                    if entry.syncData.conflictCount > 0 {
                        StatRow(icon: "exclamationmark.triangle", value: entry.syncData.conflictCount, label: "Conflicts")
                    }
                }

                Spacer()

                // Sync Now button
                Link(destination: SharedDataManager.syncNowURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .widgetURL(SharedDataManager.openAppURL)
    }

    private var statusColor: Color {
        switch entry.syncData.status.colorName {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        default: return .gray
        }
    }
}

/// Large widget view
struct DotSyncWidgetLargeView: View {
    let entry: DotSyncWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("Dot Sync")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Dotfile Synchronization")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Link(destination: SharedDataManager.syncNowURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Now")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            Divider()

            // Status section
            HStack(spacing: 16) {
                // Status indicator
                VStack(alignment: .center, spacing: 4) {
                    Image(systemName: entry.syncData.status.iconName)
                        .font(.system(size: 40))
                        .foregroundColor(statusColor)
                    Text(entry.syncData.status.rawValue)
                        .font(.headline)
                    Text(entry.syncData.status.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 100)

                Divider()

                // Stats grid
                VStack(alignment: .leading, spacing: 8) {
                    LargeStatRow(icon: "doc.fill", value: entry.syncData.totalTrackedFiles, label: "Files Tracked", color: .blue)
                    LargeStatRow(icon: "arrow.up.circle.fill", value: entry.syncData.filesNeedingSync, label: "Pending Sync", color: .orange)
                    LargeStatRow(icon: "exclamationmark.triangle.fill", value: entry.syncData.conflictCount, label: "Conflicts", color: .red)
                }
            }

            Spacer()

            // Footer with last sync
            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Last synchronized: \(entry.syncData.formattedLastSync)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Updated: \(formattedUpdateTime)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .widgetURL(SharedDataManager.openAppURL)
    }

    private var statusColor: Color {
        switch entry.syncData.status.colorName {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        default: return .gray
        }
    }

    private var formattedUpdateTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.syncData.lastUpdated)
    }
}

// MARK: - Helper Views

struct StatRow: View {
    let icon: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

struct LargeStatRow: View {
    let icon: String
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Main Widget Entry View

struct DotSyncWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DotSyncWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            DotSyncWidgetSmallView(entry: entry)
        case .systemMedium:
            DotSyncWidgetMediumView(entry: entry)
        case .systemLarge:
            DotSyncWidgetLargeView(entry: entry)
        default:
            DotSyncWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

@main
struct DotSyncWidget: Widget {
    let kind: String = "DotSyncWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DotSyncWidgetProvider()) { entry in
            if #available(macOS 14.0, *) {
                DotSyncWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                DotSyncWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Dot Sync Status")
        .description("Monitor your dotfile synchronization status")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

@available(macOS 14.0, *)
struct DotSyncWidget_Previews: PreviewProvider {
    static var previews: some View {
        Text("Widget Preview requires macOS 14+")
    }
}
