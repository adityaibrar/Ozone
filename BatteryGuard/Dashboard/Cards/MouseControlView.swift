// MouseControlView.swift
// BatteryGuard — Dashboard view untuk konfigurasi & live monitoring Mouse Scroll Inverter

import SwiftUI
import AppKit

struct MouseControlView: View {
    @ObservedObject private var mouseService = MouseScrollService.shared
    @EnvironmentObject var prefs: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Header & Master Toggle ──────────────────────────────────
                masterToggleSection

                // ── Permission Notice Banner ────────────────────────────────
                if !mouseService.hasAccessibilityPermission {
                    permissionBanner
                }

                // ── Live Input Visualizer ───────────────────────────────────
                liveVisualizerSection

                // ── Scroll Configuration ────────────────────────────────────
                scrollOptionsSection

                // ── How It Works Info Card ──────────────────────────────────
                howItWorksSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            mouseService.refreshPermissionStatus()
        }
    }

    // MARK: - Master Toggle Section

    private var masterToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Mouse & Trackpad Scroll")
                            .font(.title2)
                            .fontWeight(.bold)

                        statusBadge
                    }

                    Text("Pemisahan otomatis: scroll mouse fisik menjadi standar (kebawah = kebawah), sedangkan trackpad tetap natural gesture.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { prefs.mouseAutoScrollEnabled },
                    set: { newValue in
                        prefs.mouseAutoScrollEnabled = newValue
                        if newValue {
                            mouseService.start(userInitiated: true)
                        } else {
                            mouseService.stop()
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

            Text(statusTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusTitle: String {
        guard prefs.mouseAutoScrollEnabled else { return "Nonaktif" }
        guard mouseService.hasAccessibilityPermission else { return "Perlu Izin" }
        return mouseService.isActive ? "Aktif & Berjalan" : "Siap"
    }

    private var statusColor: Color {
        guard prefs.mouseAutoScrollEnabled else { return .secondary }
        guard mouseService.hasAccessibilityPermission else { return .orange }
        return mouseService.isActive ? .green : .blue
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Izin Aksesibilitas Diperlukan")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("macOS membutuhkan izin Aksesibilitas agar Ozone dapat membedakan event scroll antara mouse fisik dan trackpad di level sistem.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Quick instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("Petunjuk:")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("1. Klik 'Buka Pengaturan Aksesibilitas' dan aktifkan sakelar untuk **Ozone**.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("2. Jika Ozone belum muncul di daftar, klik 'Tampilkan Ozone di Finder' lalu drag icon ke jendela Pengaturan.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("3. Setelah diaktifkan, klik 'Restart Ozone' agar sistem memuat izin baru.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Button {
                    mouseService.requestAccessibilityPermission()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                        Text("1. Buka Pengaturan Aksesibilitas")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)

                Button {
                    mouseService.revealInFinder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text("2. Tampilkan di Finder")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    mouseService.restartApp()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("3. Restart Ozone")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    mouseService.refreshPermissionStatus()
                    if mouseService.hasAccessibilityPermission && prefs.mouseAutoScrollEnabled {
                        mouseService.start()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("Periksa Ulang")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Live Input Visualizer

    private var liveVisualizerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Input Monitor")
                .font(.headline)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                // Card Mouse
                deviceIndicatorCard(
                    device: .mouse,
                    title: "Physical Mouse",
                    subtitle: prefs.mouseInvertVertical ? "Scroll Terbalik (Normal)" : "Scroll Asli",
                    isActive: mouseService.lastDetectedDevice == .mouse,
                    accentColor: .indigo
                )

                // Card Trackpad
                deviceIndicatorCard(
                    device: .trackpad,
                    title: "Trackpad / Gestures",
                    subtitle: "Natural Scroll (Native macOS)",
                    isActive: mouseService.lastDetectedDevice == .trackpad,
                    accentColor: .teal
                )
            }

            if mouseService.invertedEventCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                    Text("\(mouseService.invertedEventCount) scroll events telah disesuaikan pada sesi ini.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    private func deviceIndicatorCard(
        device: ScrollInputDevice,
        title: String,
        subtitle: String,
        isActive: Bool,
        accentColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                    .frame(width: 44, height: 44)

                Image(systemName: device.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accentColor, in: RoundedRectangle(cornerRadius: 4))
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: isActive ? accentColor.opacity(0.08) : Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? accentColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: isActive ? 1.5 : 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }

    // MARK: - Scroll Options Section

    private var scrollOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pengaturan Arah Scroll")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 0) {
                // ── Invert Vertical ─────────────────────────────────────────
                scrollOptionRow(
                    title: "Balikkan Arah Vertikal (Y-Axis)",
                    subtitle: "Putar scroll wheel ke bawah → halaman bergulir ke bawah (standar Windows/Linux).",
                    icon: "arrow.up.arrow.down",
                    iconColor: .indigo,
                    isOn: $prefs.mouseInvertVertical
                )

                Divider()
                    .padding(.horizontal, 16)

                // ── Invert Horizontal ────────────────────────────────────────
                scrollOptionRow(
                    title: "Balikkan Arah Horizontal (X-Axis)",
                    subtitle: "Balikkan arah scroll horizontal untuk mouse dengan side wheel atau tilt wheel.",
                    icon: "arrow.left.arrow.right",
                    iconColor: .teal,
                    isOn: $prefs.mouseInvertHorizontal
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .opacity(prefs.mouseAutoScrollEnabled ? 1.0 : 0.5)
        }
        .disabled(!prefs.mouseAutoScrollEnabled)
    }

    /// Row individual untuk setiap opsi scroll inverter.
    /// Menggunakan HStack manual agar toggle tidak terpotong pada berbagai lebar window.
    private func scrollOptionRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Label
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Toggle — selalu di ujung kanan, tidak akan terpotong
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.wrappedValue.toggle()
        }
    }


    // MARK: - How It Works Section

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text("Bagaimana Fitur Ini Bekerja?")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                stepRow(number: "1", text: "macOS secara default menerapkan 1 opsi 'Natural Scrolling' untuk seluruh perangkat sekaligus.")
                stepRow(number: "2", text: "BatteryGuard mencegat hardware HID scroll wheel mouse secara real-time dan membalikkan vektor arahnya.")
                stepRow(number: "3", text: "Trackpad tetap menggunakan gestur natural dan momentum native macOS tanpa terganggu.")
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.secondary)
                .frame(width: 16, height: 16)
                .background(Color.primary.opacity(0.08), in: Circle())

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
