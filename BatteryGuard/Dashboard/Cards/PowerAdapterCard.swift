// PowerAdapterCard.swift
// Card 3: Informasi power adapter dari IOPSCopyExternalPowerAdapterDetails

import SwiftUI

struct PowerAdapterCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    var adapter: AdapterInfo { viewModel.adapterInfo }

    var body: some View {
        DashboardCardView(title: "Power Adapter", icon: "powerplug.fill", accentColor: .indigo) {
            VStack(spacing: 10) {
                // Connection status
                HStack {
                    Circle()
                        .fill(adapter.isConnected ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(adapter.isConnected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundStyle(adapter.isConnected ? Color.green : Color.secondary)
                    Spacer()
                }

                if adapter.isConnected {
                    Divider()

                    VStack(spacing: 6) {
                        CardInfoRow(
                            label: "Wattage",
                            value: adapter.wattage.map { "\(Int($0)) W" } ?? "—"
                        )
                        CardInfoRow(
                            label: "Current",
                            value: adapter.amperage.map { String(format: "%.2f A", $0) } ?? "—"
                        )
                        CardInfoRow(
                            label: "Voltage",
                            value: adapter.voltage.map { String(format: "%.1f V", $0) } ?? "—"
                        )
                        if let name = adapter.name, !name.isEmpty {
                            CardInfoRow(label: "Name", value: name)
                        }
                        if let family = adapter.family {
                            CardInfoRow(label: "Type", value: family)
                        }
                    }
                } else {
                    // Empty state — "powerplug.slash" tidak tersedia, gunakan xmark.circle overlay
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            ZStack {
                                Image(systemName: "powerplug")
                                    .font(.title2)
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .offset(x: 8, y: -8)
                            }
                            Text("No adapter connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
