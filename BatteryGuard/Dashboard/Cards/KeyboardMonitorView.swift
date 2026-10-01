// KeyboardMonitorView.swift
// BatteryGuard — Full-page dashboard view untuk Keyboard Key Press Counter
// Menampilkan: device picker, summary stats, top-10 bar chart, dan heatmap QWERTY layout

import SwiftUI
import AppKit

struct KeyboardMonitorView: View {
    @ObservedObject private var keyService = KeyboardMonitorService.shared
    @EnvironmentObject var prefs: PreferencesStore

    /// State untuk konfirmasi reset
    @State private var showResetConfirm: Bool = false
    @State private var showResetAllConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Header & Master Toggle ──────────────────────────────────
                masterToggleSection

                // ── Permission Banner ───────────────────────────────────────
                if !keyService.hasInputMonitoringPermission && prefs.keyboardMonitorEnabled {
                    permissionBanner
                }

                // ── Device Picker ───────────────────────────────────────────
                if keyService.allKnownDevices.count > 1 {
                    devicePickerSection
                }

                // ── Summary & Heatmap (Selalu tampil agar dashboard interaktif)
                summarySection
                topKeysSection
                heatmapSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            keyService.refreshPermissionStatus()
        }
        .confirmationDialog(
            "Reset data keyboard ini?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                let id = keyService.effectiveSelectedDeviceID
                keyService.reset(deviceID: id)
            }
            Button("Batal", role: .cancel) {}
        }
        .confirmationDialog(
            "Reset semua data keyboard?",
            isPresented: $showResetAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Semua", role: .destructive) {
                keyService.resetAll()
            }
            Button("Batal", role: .cancel) {}
        }
    }

    // MARK: - Master Toggle Section

    private var masterToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.title2)
                            .foregroundStyle(.purple)

                        Text("Keyboard Monitor")
                            .font(.title2)
                            .fontWeight(.bold)

                        statusBadge
                    }

                    Text("Pantau frekuensi penekanan setiap tombol keyboard — termasuk modifier keys, disimpan permanen per perangkat.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { prefs.keyboardMonitorEnabled },
                    set: { newValue in
                        prefs.keyboardMonitorEnabled = newValue
                        if newValue {
                            keyService.start(userInitiated: true)
                        } else {
                            keyService.stop()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(
                    // Pulse animasi saat aktif
                    Circle()
                        .stroke(statusColor.opacity(0.4), lineWidth: 2)
                        .scaleEffect(keyService.isActive ? 1.6 : 1.0)
                        .opacity(keyService.isActive ? 0 : 1)
                        .animation(
                            keyService.isActive
                                ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                                : .default,
                            value: keyService.isActive
                        )
                )

            Text(statusTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusTitle: String {
        guard prefs.keyboardMonitorEnabled else { return "Nonaktif" }
        guard keyService.hasInputMonitoringPermission else { return "Perlu Izin" }
        return keyService.isActive ? "Aktif & Merekam" : "Siap"
    }

    private var statusColor: Color {
        guard prefs.keyboardMonitorEnabled else { return .secondary }
        guard keyService.hasInputMonitoringPermission else { return .orange }
        return keyService.isActive ? .purple : .blue
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Izin Input Monitoring Diperlukan")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("macOS memerlukan izin **Input Monitoring** di Pengaturan Sistem agar Ozone dapat mencatat penekanan tombol dari keyboard internal maupun eksternal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("📌 **Cara Mengaktifkan:**")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text("1. Klik tombol **Buka Pengaturan Input Monitoring** di bawah.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("2. Jika **Ozone** ada di daftar, aktifkan sakelarnya.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("3. **Jika belum muncul di daftar:** Klik **Tampilkan di Finder**, lalu tekan tombol **'+'** di Pengaturan Sistem dan pilih (atau drag) file **Ozone.app**.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("4. Jika muncul dialog *\"Quit & Reopen\"*, pilih **Quit & Reopen** (atau klik **Restart Ozone** di bawah).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider()
                .opacity(0.5)

            HStack(spacing: 10) {
                Button {
                    keyService.requestInputMonitoringPermission()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                        Text("Buka Pengaturan Input Monitoring")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)

                Button {
                    keyService.revealInFinder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text("Tampilkan di Finder")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    keyService.refreshPermissionStatus()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Periksa Ulang")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    keyService.relaunchApplication()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Restart Ozone")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.orange.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Device Picker

    private var devicePickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pilih Keyboard")
                .font(.headline)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(keyService.allKnownDevices) { keyboard in
                        devicePickerCard(keyboard: keyboard)
                    }
                }
            }
        }
    }

    private func devicePickerCard(keyboard: KeyboardDevice) -> some View {
        let isSelected = keyService.effectiveSelectedDeviceID == keyboard.id

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                keyService.selectedDeviceID = keyboard.id
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: keyboard.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .purple)

                VStack(alignment: .leading, spacing: 1) {
                    Text(keyboard.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)

                    Text(keyboard.isInternal ? "Internal" : "Eksternal")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.purple : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: isSelected ? .purple.opacity(0.3) : .black.opacity(0.03), radius: 5, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        HStack(spacing: 12) {
            summaryCard(
                icon: "keyboard.badge.ellipsis",
                iconColor: .purple,
                label: "Total Ketukan",
                value: keyService.currentTotalPresses.formatted()
            )

            summaryCard(
                icon: "star.fill",
                iconColor: .yellow,
                label: "Key Terbanyak",
                value: keyService.currentTopKeys(limit: 1).first.map { "\($0.label) — \($0.count)x" } ?? "—"
            )

            summaryCard(
                icon: "square.grid.2x2.fill",
                iconColor: .teal,
                label: "Unique Keys",
                value: "\(keyService.currentUniqueKeyCount)"
            )
        }
    }

    private func summaryCard(icon: String, iconColor: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Top Keys Section

    private var topKeysSection: some View {
        let topKeys = keyService.currentTopKeys(limit: 10)
        let maxCount = topKeys.first?.count ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Keys")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Reset buttons
                HStack(spacing: 8) {
                    Button {
                        showResetConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Device")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showResetAllConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Reset Semua")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }

            if topKeys.isEmpty {
                Text("Belum ada data — mulai mengetik di aplikasi mana saja.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 6) {
                    ForEach(topKeys) { entry in
                        keyBarRow(entry: entry, maxCount: maxCount, total: keyService.currentTotalPresses)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private func keyBarRow(entry: KeyPressEntry, maxCount: Int, total: Int) -> some View {
        let percent = total > 0 ? Double(entry.count) / Double(total) : 0
        let barFraction = maxCount > 0 ? Double(entry.count) / Double(maxCount) : 0

        return HStack(spacing: 10) {
            // Key label chip
            Text(entry.label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 42, maxWidth: 42, alignment: .center)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                )

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.purple.opacity(0.08))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.7), .purple],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * barFraction, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: barFraction)
                }
            }
            .frame(height: 8)

            // Count + percent
            HStack(spacing: 4) {
                Text("\(entry.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 40, alignment: .trailing)

                Text(String(format: "%.1f%%", percent * 100))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
        .frame(height: 24)
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Key Frequency Map")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Legend
                heatmapLegend
            }

            keyboardHeatmapView
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private var heatmapLegend: some View {
        HStack(spacing: 6) {
            Text("Jarang")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ForEach([0.15, 0.3, 0.5, 0.7, 1.0], id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(fraction: opacity))
                        .frame(width: 14, height: 10)
                }
            }

            Text("Sering")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // Layout keyboard QWERTY standar
    private let keyboardRows: [[String]] = [
        ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Delete"],
        ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
        ["⇪", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Return"],
        ["⇧", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "⇧"],
        ["⌃", "⌥", "⌘", "Space", "⌘", "⌥", "←", "↓", "↑", "→"]
    ]

    /// Keys yang harus lebih lebar dari key standar
    private let wideKeys: Set<String> = ["Delete", "Tab", "Return", "⇧", "⇪", "Space", "Esc"]

    private var keyboardHeatmapView: some View {
        let maxCount = keyService.currentTotalPresses > 0
            ? (keyService.currentKeyCounts.values.max() ?? 1)
            : 1

        return VStack(alignment: .leading, spacing: 4) {
            // Gunakan enumerated() agar key duplikat (⇧, ⌘, ⌥) punya ID unik berdasarkan posisi
            ForEach(Array(keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, keyLabel in
                        heatmapKey(
                            label: keyLabel,
                            count: keyService.count(for: keyLabel),
                            maxCount: maxCount
                        )
                    }
                }
            }
        }
    }

    private func heatmapKey(label: String, count: Int, maxCount: Int) -> some View {
        let fraction = maxCount > 0 ? Double(count) / Double(maxCount) : 0
        let bgColor = heatColor(fraction: fraction)
        let isWide = wideKeys.contains(label)
        let isSpace = label == "Space"

        return VStack(spacing: 2) {
            Text(label)
                .font(.system(size: isWide && !isSpace ? 8 : 9, weight: .semibold, design: .rounded))
                .foregroundStyle(fraction > 0.5 ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if count > 0 {
                Text(compactCount(count))
                    .font(.system(size: 7, weight: .regular))
                    .foregroundStyle(fraction > 0.5 ? .white.opacity(0.8) : .secondary)
            }
        }
        .frame(
            minWidth: isSpace ? 80 : (isWide ? 44 : 28),
            maxWidth: isSpace ? 100 : (isWide ? 52 : 32),
            minHeight: 34, maxHeight: 34
        )
        .background(bgColor, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.3), value: count)
    }

    /// Hitung warna heatmap berdasarkan fraksi (0.0–1.0)
    private func heatColor(fraction: Double) -> Color {
        if fraction <= 0 {
            return Color.primary.opacity(0.06)
        } else if fraction <= 0.2 {
            return Color.green.opacity(0.25 + fraction * 0.5)
        } else if fraction <= 0.5 {
            return Color.yellow.opacity(0.4 + fraction * 0.6)
        } else if fraction <= 0.8 {
            return Color.orange.opacity(0.5 + fraction * 0.4)
        } else {
            return Color.red.opacity(0.6 + fraction * 0.4)
        }
    }

    /// Format angka besar secara ringkas (contoh: 1234 → "1.2K")
    private func compactCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
