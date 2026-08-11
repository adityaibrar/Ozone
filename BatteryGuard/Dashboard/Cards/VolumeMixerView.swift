// VolumeMixerView.swift
// BatteryGuard — UI Volume Mixer per-aplikasi

import SwiftUI
import AppKit

// MARK: - VolumeMixerView

struct VolumeMixerView: View {
    @StateObject private var service = VolumeMixerService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── System Volume ──────────────────────────────────────────
                systemVolumeSection

                Divider()
                    .padding(.horizontal, 20)

                // ── Per-App Mixer ──────────────────────────────────────────
                appMixerSection
            }
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            service.checkPermission()
            if service.needsPermission {
                service.requestInitialPermissionIfNeeded()
            }
        }
    }

    // MARK: - System Volume Section

    private var systemVolumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Output")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)

            GroupBox {
                SystemVolumeRow(
                    volume: $service.systemVolume,
                    isMuted: $service.isSystemMuted,
                    onVolumeChange: { service.setSystemVolume($0) },
                    onMuteToggle: { service.toggleSystemMute() }
                )
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - App Mixer Section

    private var appMixerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applications")
                        .font(.title3)
                        .fontWeight(.semibold)

                    if service.needsPermission {
                        Text("Izin audio sistem diperlukan untuk mengatur volume")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                    } else if #available(macOS 14.4, *) {
                        Text("Volume control aktif via Process Tap")
                            .font(.caption2)
                            .foregroundStyle(Color.green)
                    } else {
                        Text("Mute saja (macOS 14.4+ untuk volume control)")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                Button {
                    service.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh app list")
            }
            .padding(.horizontal, 20)

            // Banner izin Screen & System Audio Recording
            if service.needsPermission {
                PermissionNoticeBanner(
                    onRequestPermission: { service.requestPermission() },
                    onRevealInFinder: { service.revealInFinder() },
                    onRestartApp: { service.restartApp() },
                    onRefresh: { service.checkPermission() }
                )
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if service.apps.isEmpty {
                EmptyMixerStateView()
                    .padding(.vertical, 20)
            } else {
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(service.apps.enumerated()), id: \.element.id) { index, app in
                            AppVolumeRow(
                                app: app,
                                onVolumeChange: { newVolume in
                                    service.setVolume(newVolume, for: app.bundleIdentifier)
                                },
                                onMuteToggle: {
                                    service.toggleMute(for: app.bundleIdentifier)
                                }
                            )

                            if index < service.apps.count - 1 {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - SystemVolumeRow

private struct SystemVolumeRow: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    private var volumeIcon: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Speaker icon — animasi ganti icon manual (kompatibel macOS 13+)
            Image(systemName: volumeIcon)
                .font(.title2)
                .foregroundStyle(isMuted ? Color.secondary : Color.blue)
                .frame(width: 28)
                .animation(.easeInOut(duration: 0.2), value: volumeIcon)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Master Volume")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(volume * 100))%")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { onVolumeChange(Float($0)) }
                    ),
                    in: 0...1,
                    step: 0.01
                )
                .tint(isMuted ? Color.secondary : Color.blue)
                .disabled(isMuted)
            }

            // Mute button
            Button {
                onMuteToggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.body)
                    .foregroundStyle(isMuted ? Color.red : Color.secondary)
                    .animation(.easeInOut(duration: 0.15), value: isMuted)
            }
            .buttonStyle(.borderless)
            .help(isMuted ? "Unmute" : "Mute")
        }
        .padding(4)
    }
}

// MARK: - AppVolumeRow

private struct AppVolumeRow: View {
    let app: VolumeApp
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    private var sliderTint: Color {
        if app.isEffectivelyMuted { return Color.secondary }
        if app.isBoosted { return Color.orange }
        return Color.blue
    }

    private var muteIcon: String {
        if app.isEffectivelyMuted { return "speaker.slash.fill" }
        if app.volume < 0.33 { return "speaker.wave.1.fill" }
        if app.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(icon: app.icon, name: app.name)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.name)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    // Badge boost jika >100%
                    if app.isBoosted && !app.isEffectivelyMuted {
                        Text("BOOST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                    }

                    Text(app.isEffectivelyMuted ? "Muted" : app.volumeLabel)
                        .font(.caption)
                        .foregroundStyle(
                            app.isEffectivelyMuted ? Color.red.opacity(0.8) :
                            app.isBoosted ? Color.orange : Color.secondary
                        )
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                        .animation(.easeInOut(duration: 0.15), value: app.isEffectivelyMuted)
                }

                // Slider 0–200%.
                Slider(
                    value: Binding(
                        get: { Double(app.volume) },
                        set: { onVolumeChange(Float($0)) }
                    ),
                    in: 0...2.0,
                    step: 0.01
                )
                .tint(sliderTint)

                // Tick marks: 0%, 100%, 200%
                HStack {
                    Text("0%").font(.system(size: 9)).foregroundStyle(Color.secondary.opacity(0.5))
                    Spacer()
                    Text("100%").font(.system(size: 9)).foregroundStyle(Color.secondary.opacity(0.5))
                    Spacer()
                    Text("200%").font(.system(size: 9)).foregroundStyle(Color.secondary.opacity(0.5))
                }
            }

            Button {
                onMuteToggle()
            } label: {
                Image(systemName: app.isEffectivelyMuted ? "speaker.slash.fill" : muteIcon)
                    .font(.body)
                    .foregroundStyle(app.isEffectivelyMuted ? Color.red : Color.secondary)
                    .animation(.easeInOut(duration: 0.15), value: app.isEffectivelyMuted)
            }
            .buttonStyle(.borderless)
            .help(app.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .opacity(app.isEffectivelyMuted ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: app.isEffectivelyMuted)
    }
}

// MARK: - PermissionNoticeBanner

private struct PermissionNoticeBanner: View {
    let onRequestPermission: () -> Void
    let onRevealInFinder: () -> Void
    let onRestartApp: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Izin Rekaman Audio Diperlukan")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)

                    Text("macOS mewajibkan izin 'Perekaman Layar & Audio Sistem' untuk mengatur volume per aplikasi. Setelah toggle diaktifkan di Pengaturan, aplikasi wajib dimuat ulang (restart).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Petunjuk:")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("1. Klik '1. Buka Pengaturan' dan aktifkan izin perekaman audio untuk **Ozone**.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("2. Jika Ozone belum muncul di daftar, klik '2. Tampilkan di Finder' dan drag icon ke System Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("3. Klik '3. Muat Ulang App' agar perubahan izin terbaca oleh macOS.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button {
                    onRequestPermission()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                        Text("1. Buka Pengaturan")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.blue)
                .controlSize(.small)

                Button {
                    onRevealInFinder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text("2. Tampilkan di Finder")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onRestartApp()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("3. Muat Ulang App")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onRefresh()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("Periksa Ulang")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

// MARK: - AppIconView

private struct AppIconView: View {
    let icon: NSImage?
    let name: String

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Fallback: initial letter avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}

// MARK: - EmptyMixerStateView

private struct EmptyMixerStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "speaker.zzz.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.secondary.opacity(0.5))

            Text("No Audio Playing")
                .font(.headline)
                .foregroundStyle(Color.primary)

            Text("Apps that are currently playing audio will appear here. Try playing music or a video.")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VolumeMixerView()
        .frame(width: 500, height: 500)
}
#endif
