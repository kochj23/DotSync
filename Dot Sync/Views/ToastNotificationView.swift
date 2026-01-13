//
//  ToastNotificationView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/12/26.
//

import SwiftUI

/// Toast notification view for in-app alerts
struct ToastNotificationView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: toast.type.icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 24, height: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(toast.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(toast.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }

    private var iconColor: Color {
        switch toast.type {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }

    private var backgroundColor: Color {
        Color(.windowBackgroundColor).opacity(0.95)
    }
}

/// Toast container that manages multiple toasts
struct ToastContainerView: View {
    let toasts: [ToastMessage]
    let onDismiss: (ToastMessage) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts) { toast in
                ToastNotificationView(toast: toast) {
                    onDismiss(toast)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toasts)
    }
}
