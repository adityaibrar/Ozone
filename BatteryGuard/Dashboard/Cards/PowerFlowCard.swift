// PowerFlowCard.swift
// Card 8: Visual aliran daya — charger → baterai → sistem

import SwiftUI

struct PowerFlowCard: View {
    @EnvironmentObject var viewModel: SystemStatsViewModel

    @State private var animationOffset: CGFloat = 0

    private var isCharging: Bool { viewModel.batteryStatus.isCharging }
    private var isPluggedIn: Bool { viewModel.batteryStatus.isPluggedIn }

    var body: some View {
        DashboardCardView(title: "Power Flow", icon: "arrow.trianglehead.2.clockwise.rotate.90", accentColor: flowColor) {
            VStack(spacing: 16) {
                // Flow diagram
                HStack(spacing: 0) {
                    // Charger node
                    PowerFlowNode(
                        icon: isPluggedIn ? "powerplug.fill" : "powerplug",
                        label: "Adapter",
                        sublabel: viewModel.adapterInfo.wattage.map { "\(Int($0))W" } ?? "—",
                        color: isPluggedIn ? .indigo : .secondary,
                        isActive: isPluggedIn
                    )

                    // Flow arrow: Adapter → Battery
                    FlowArrow(
                        isActive: isCharging,
                        direction: .right,
                        color: .green
                    )

                    // Battery node
                    PowerFlowNode(
                        icon: viewModel.batteryIconName,
                        label: "Battery",
                        sublabel: "\(viewModel.batteryStatus.percentage)%",
                        color: viewModel.batteryStatus.isCharging ? .green : .primary,
                        isActive: true
                    )

                    // Flow arrow: Battery → System
                    FlowArrow(
                        isActive: !isCharging,
                        direction: .right,
                        color: .orange
                    )

                    // System node
                    PowerFlowNode(
                        icon: "desktopcomputer",
                        label: "System",
                        sublabel: viewModel.powerFlow.instantWattage.map {
                            String(format: "%.1fW", $0)
                        } ?? "—",
                        color: .blue,
                        isActive: true
                    )
                }

                // Status label
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .animation(.easeInOut, value: statusLabel)
            }
        }
    }

    private var statusLabel: String {
        if isCharging {
            return "Charging from adapter to battery"
        } else if isPluggedIn {
            return "Running on adapter, battery not charging"
        } else {
            return "Running on battery power"
        }
    }

    private var flowColor: Color {
        isCharging ? .green : (isPluggedIn ? .indigo : .orange)
    }
}

// MARK: - Power Flow Node

struct PowerFlowNode: View {
    let icon: String
    let label: String
    let sublabel: String
    var color: Color = .primary
    var isActive: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Outer glow ring saat aktif
                Circle()
                    .fill(color.opacity(isActive ? 0.08 : 0))
                    .frame(width: 56, height: 56)

                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isActive ? color : .secondary)
            }

            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(sublabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(isActive ? color.opacity(0.8) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .opacity(isActive ? 1.0 : 0.45)
    }
}

// MARK: - Flow Arrow

struct FlowArrow: View {
    let isActive: Bool
    let direction: Direction
    let color: Color

    enum Direction { case right, left }

    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? color : .secondary.opacity(0.2))
                    .opacity(isActive ? (animating ? Double(index + 1) / 3.0 : Double(3 - index) / 3.0) : 0.3)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: false).delay(Double(index) * 0.25)
                            : .default,
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .frame(width: 24)
    }
}
