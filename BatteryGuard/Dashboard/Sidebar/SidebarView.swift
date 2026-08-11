// SidebarView.swift
// BatteryGuard — Navigasi sidebar kiri dashboard

import SwiftUI

// MARK: - Sidebar Navigation Items

enum DashboardSection: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case dashboard     = "Dashboard"
    case chargeControl = "Charge Control"
    case mouse         = "Mouse & Scroll"
    case energyUse     = "Energy Use"
    case volumeMixer   = "Volume Mixer"
    case keyboard      = "Keyboard Monitor"
    case log           = "Log"
    case uninstaller   = "Uninstaller"

    var icon: String {
        switch self {
        case .dashboard:      return "gauge.with.dots.needle.bottom.50percent"
        case .chargeControl:  return "bolt.badge.clock"
        case .mouse:          return "computermouse"
        case .energyUse:      return "bolt.fill"
        case .volumeMixer:    return "speaker.wave.3.fill"
        case .keyboard:       return "keyboard"
        case .log:            return "terminal"
        case .uninstaller:    return "trash"
        }
    }

    var color: Color {
        switch self {
        case .dashboard:      return .blue
        case .chargeControl:  return .green
        case .mouse:          return .indigo
        case .energyUse:      return .orange
        case .volumeMixer:    return .teal
        case .keyboard:       return .purple
        case .log:            return .secondary
        case .uninstaller:    return .red
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selection: DashboardSection?

    var body: some View {
        List(DashboardSection.allCases, selection: $selection) { section in
            Label {
                Text(section.rawValue)
            } icon: {
                Image(systemName: section.icon)
                    .foregroundStyle(section.color)
            }
            .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Ozone")
        .frame(minWidth: 180)
    }
}
