# Ozone v1.2.0 — Polish & Stability Update

Rilis fokus pada perbaikan bug, optimasi performa scroll, dan peningkatan kualitas UI secara menyeluruh. Tidak ada fitur baru besar — semua energi dicurahkan untuk memastikan pengalaman yang halus, responsif, dan bebas error di seluruh aplikasi.

---

## ✨ Perubahan di v1.2.0

### 🏗️ Perubahan Arsitektur (Breaking Internal)

- **Dashboard dimigrasi ke `NSWindowController`**
  Dashboard tidak lagi dikelola sebagai SwiftUI `Window` scene. Kini dikontrol penuh oleh `AppDelegate` via `NSWindowController`, memungkinkan kontrol penuh atas kapan window ditampilkan atau disembunyikan — tanpa gangguan dari SwiftUI scene lifecycle.

- **Menghapus SwiftUI `Window` scene dari `BatteryGuardApp`**
  Hanya `Settings` scene yang tersisa. Dashboard dibuat secara *lazy* (on-demand) hanya saat user pertama kali membukanya, sehingga tidak ada overhead saat launch.

---

### 🐛 Bug Fixes

#### Dashboard — Tidak Lagi Auto-Terbuka Saat Launch
- **Root cause:** SwiftUI `Window` scene selalu menampilkan window-nya saat launch, dan secara aktif melawan panggilan `orderOut()` dari luar — menciptakan loop tak terbatas.
- **Fix:** Hapus `Window` scene, ganti dengan `NSWindowController`. Dashboard hanya muncul saat user secara eksplisit memintanya (klik ⊞ di popover atau klik icon Dock).

#### About Tab — Icon App & Versi Hardcoded
- **Fix:** Icon app sekarang menggunakan `NSApp.applicationIconImage` — otomatis sinkron dengan `Assets.xcassets`, tidak perlu update manual.
- **Fix:** Versi membaca dari `Bundle.main.infoDictionary["CFBundleShortVersionString"]` dan build number dari `CFBundleVersion` — selalu sinkron dengan Xcode project settings.
- **Fix:** Nama app membaca dari `CFBundleDisplayName` / `CFBundleName` secara dinamis.

#### About Tab — SF Symbol Tidak Valid
- **Fix:** `battery.75.bolt` tidak ada di SF Symbols — dihapus, digantikan oleh app icon asli.

#### Settings — `SettingsLink` vs Deprecated `sendAction`
- **Fix:** Migrasi dari `NSApp.sendAction("showSettingsWindow:")` (deprecated di macOS 14+) ke `SettingsLink` dengan `#available(macOS 14.0, *)` guard dan fallback `sendAction` untuk macOS 13.
- **Fix:** Tambah `settingsIconLabel` sebagai shared computed property agar tidak duplikasi kode antara kedua branch availability.

#### MenuBar — `openWindow` Environment Dependency Dihapus
- **Fix:** Tombol Dashboard di `MenuBarView` tidak lagi menggunakan `@Environment(\.openWindow)`. Kini mengirim `Notification.Name.openDashboardRequest` ke `AppDelegate` yang mengelola window secara langsung.

#### Volume Mixer — Audio Output Berbeda di Background
- **Root cause:** `VolumeMixerService` di-inisialisasi sebagai `@StateObject` di dalam `VolumeMixerView`. Hal ini menyebabkan service di-*deallocate* (dihancurkan) setiap kali dashboard ditutup, yang berakibat pada matinya *Process Tap CoreAudio* sehingga volume kembali ke default passthrough.
- **Fix:** Siklus hidup (lifecycle) dipindahkan ke `SystemStatsViewModel` agar berumur sama dengan aplikasi (app lifetime). View sekarang menggunakan pola *Wrapper* dengan `@EnvironmentObject` dan meneruskan instance ke inner view yang menggunakan `@ObservedObject` (mempertahankan dukungan syntax `$service` pada view tanpa mengorbankan stabilitas background).

#### PowerAdapterCard — SF Symbol Tidak Valid
- **Fix:** Symbol `powerplug.slash` tidak ada — diganti dengan kombinasi `powerplug` + `xmark` overlay yang valid.

#### KeyboardMonitorView — Duplicate `ForEach` ID Warning
- **Fix:** Migrasi dari `id: \.self` ke `enumerated()` + index-based ID untuk heatmap keys, menghilangkan warning duplikat ID di console.

---

### ⚡ Performance

- **`DashboardCardView` — Scroll Lebih Halus**
  Dihapus: hover state animation, material blur background, dan redundant shadow layers yang menyebabkan stuttering saat scroll `LazyVGrid`. Kini lebih ringan dan konsisten di 60fps.

---

### 🎨 UI/UX

- **MenuBar Popover — "Quick Stats" Row**
  Ditambahkan baris ringkas di bagian atas popover yang menampilkan: Battery Health, Cycle Count, CPU Temp, RAM Usage, dan Download Speed — tanpa perlu membuka Dashboard.

- **AppDelegate — Popover Size Disesuaikan**
  Ukuran popover ditingkatkan untuk mengakomodasi Quick Stats row yang baru ditambahkan.

- **About Tab — Tampilan Lebih Akurat**
  Icon app sekarang tampil nyata (bukan placeholder hijau), versi dan build number selalu sinkron otomatis.

---

### 🔧 Developer / Internal

- Tambah `Notification.Name.openDashboardRequest` extension untuk komunikasi bersih antara SwiftUI views dan AppDelegate.
- Tambah `UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")` untuk mencegah window restoration yang tidak diinginkan saat launch berikutnya.
- Semua debug log `[AppDelegate]` yang ditambahkan saat sesi debugging telah dibersihkan dari production build path.

---

## 📁 File yang Diubah

| File | Perubahan |
|------|-----------|
| `App/BatteryGuardApp.swift` | Hapus `Window` scene, pertahankan `Settings` scene saja |
| `App/AppDelegate.swift` | Migrasi ke `NSWindowController`, tambah `Notification.Name`, hapus suppress logic |
| `MenuBar/MenuBarView.swift` | Ganti `openWindow` → `NotificationCenter`, hapus `@Environment(\.openWindow)`, tambah Quick Stats |
| `Settings/SettingsView.swift` | Fix About tab: app icon asli, versi dinamis, hapus SF Symbol invalid |
| `Dashboard/Cards/DashboardCardView.swift` | Hapus hover animation & material blur untuk performa scroll |
| `Dashboard/Cards/PowerAdapterCard.swift` | Fix SF Symbol `powerplug.slash` |
| `Dashboard/Cards/KeyboardMonitorView.swift` | Fix duplicate ForEach ID |

---

## 💻 Requirements

- macOS 13 (Ventura) atau lebih baru
- Apple Silicon (M1/M2/M3/M4) atau Intel Mac
