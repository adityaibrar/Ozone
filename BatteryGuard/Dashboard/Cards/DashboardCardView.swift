// DashboardCardView.swift
// BatteryGuard — Reusable card container (macOS 26 Tahoe refresh)
// Desain: Fresh static surface — performa scroll diprioritaskan

import SwiftUI

// MARK: - DashboardCardView

/// Container card yang konsisten untuk semua card dashboard.
/// Performa: background static (no material per-card), satu shadow, tanpa hover state.
struct DashboardCardView<Content: View>: View {

    let title: String
    let icon: String
    var accentColor: Color = .blue
    var isLoading: Bool = false
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Card Header
            HStack(spacing: 10) {
                // Icon dengan background tinted pill
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 30, height: 30)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accentColor)
                }
            }

            // Accent divider — static, tanpa gradient berat
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 40, height: 1)
                Rectangle()
                    .fill(accentColor.opacity(0.15))
                    .frame(maxWidth: .infinity, maxHeight: 1)
            }

            // MARK: Card Content
            content()
        }
        .padding(16)
        // Background: warna adaptif environment (sangat ringan, tidak blur per-card)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            // Accent stripe kiri — di luar clipShape supaya tidak double-render
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accentColor.opacity(0.65))
                .frame(width: 3)
        }
        .overlay {
            // Border tipis static — bukan gradient dinamis
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        // Satu shadow ringan — cukup untuk depth
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}


// MARK: - Info Row

/// Satu baris info key-value di dalam card
struct CardInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var isMonospaced: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            Spacer()

            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Preview

#Preview("Dashboard Card") {
    DashboardCardView(title: "Battery Specs", icon: "cpu", accentColor: .blue) {
        VStack(spacing: 6) {
            CardInfoRow(label: "Design Capacity", value: "6068 mAh")
            CardInfoRow(label: "Serial Number", value: "ABC123DEF456", isMonospaced: true)
            CardInfoRow(label: "Manufacturer", value: "Apple Inc.")
        }
    }
    .frame(width: 320)
    .padding()
}
