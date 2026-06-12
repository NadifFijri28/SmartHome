<!-- File: README.md - Panduan menjalankan SmartHome Core (Fase 1 MVP) -->

# SmartHome Core — Dynamic IoT System

> Ekosistem *smart home* mandiri: **ESP32** (firmware C++/Arduino IDE) +
> **Flutter** (mobile companion Android) + **Firebase** (Realtime Database
> & Auth). Repositori ini berada pada **Fase 1 MVP**: satu hub ESP32 dengan
> satu relay, kontrol manual + jadwal otomatis berbasis waktu lokal NTP.

Penulis: **Nadif Fijri Fajar Arifin**.
Dokumen otoritatif arsitektur ada di folder [`docs/`](./docs/). Bacalah file
tersebut bila membutuhkan latar belakang keputusan desain — README ini hanya
panduan eksekusi.

---

## 1. Struktur Repositori

```
SmartHome/
├── docs/                      # Sumber kebenaran arsitektur (PRD, flow, dsb.)
├── esp32_firmware/
│   └── src/main/
│       ├── main.ino           # Sketch utama (FreeRTOS dual-core)
│       └── config.h           # Kredensial Wi-Fi + Firebase + pin GPIO
├── flutter_app/
│   ├── lib/
│   │   ├── main.dart          # Entry point Flutter
│   │   ├── models/            # DeviceModel, ScheduleModel, UserModel, ...
│   │   ├── services/          # auth_service.dart (Firebase Auth wrapper)
│   │   ├── viewmodels/        # DashboardViewModel (RTDB stream)
│   │   ├── views/             # Halaman Login, Dashboard, ...
│   │   ├── widgets/           # Komponen UI reusable
│   │   └── theme/             # Tema Material 3
│   └── pubspec.yaml
└── firebase_backend/
    ├── firebase.json          # Manifest Firebase CLI
    ├── database.rules.json    # Security rules RTDB (default deny)
    └── seed.json              # Data awal: device, relay, schedule, user
```

---

## 2. Prasyarat (Sekali Pasang)

### 2.1 Akun & Proyek Firebase
1. Buat proyek di <https://console.firebase.google.com> (region disarankan
   **asia-southeast1**, sesuai endpoint default di `config.h`).
2. Aktifkan dua produk berikut:
   - **Realtime Database** → Create Database → mode *Locked* (rules akan
     di-deploy dari repo).
   - **Authentication** → Sign-in method → aktifkan **Email/Password**.
3. Pada *Project Settings → Service Accounts → Database Secrets*, generate
   **Database Secret** (legacy token). Token ini dipakai ESP32 sebagai
   `FIREBASE_AUTH` di `config.h` (Fase 1 sengaja memakai legacy token
   karena lib Mobizt mendukungnya tanpa overhead JWT).
4. Catat URL RTDB Anda — bentuknya:
   `<project-id>-default-rtdb.<region>.firebasedatabase.app`.

### 2.2 ESP32 Toolchain
- **Arduino IDE ≥ 2.x**.
- *Boards Manager* → install **esp32 by Espressif Systems** (≥ 3.0.x).
- *Library Manager* → install:
  - `ArduinoJson` oleh Benoit Blanchon (≥ **6.21**, jangan v7 — API berbeda).
  - `Firebase ESP Client` oleh Mobizt (≥ **4.4**).
- Kabel data USB (bukan kabel charging-only) + driver CP210x / CH340
  tergantung dev board Anda.

### 2.3 Flutter Toolchain
- **Flutter SDK ≥ 3.19** (Dart SDK ≥ 3.3 otomatis terpasang).
- **Android Studio** (dengan Android SDK + platform-tools) atau setidaknya
  Android command-line tools — wajib karena target Fase 1 adalah Android.
- Emulator Android (API 30+) **atau** HP Android fisik dengan
  *USB debugging* aktif.
- Jalankan `flutter doctor` dan pastikan semua centang hijau pada bagian
  *Flutter*, *Android toolchain*, *Connected device*.

### 2.4 Firebase CLI
- Install Node.js LTS lalu:
  ```bash
  npm install -g firebase-tools
  firebase login
  ```
- Verifikasi: `firebase --version`.

---

## 3. Langkah Menjalankan Project

Urutan **wajib**: Firebase backend dulu (rules + seed), lalu ESP32 (supaya
device online), terakhir Flutter (supaya UI punya data live untuk dipakai).

### 3.1 Deploy Firebase Backend

```bash
cd D:/SmartHome/firebase_backend

# Tautkan folder ini ke project Firebase Anda
firebase use --add        # pilih project, beri alias "default"

# Deploy security rules
firebase deploy --only database
```

Import seed (sekali saja):

1. Buka **Firebase Console → Realtime Database → tab Data**.
2. Klik titik-tiga (⋮) di pojok kanan → **Import JSON** → pilih
   `firebase_backend/seed.json`.
3. Setelah berhasil, **hapus node `_meta`** secara manual lewat console
   (parser RTDB ketat, dan node itu hanya penanda).
4. Penting: rules mensyaratkan user berstatus `Approved`. Buka node
   `/users/user_owner_nadif123` lalu set `status: "Approved"` (atau buat
   user baru via Authentication → Users, lalu salin UID-nya menggantikan
   `user_owner_nadif123` di `metadata.owner_uid` agar Anda bisa mengontrol
   device sebagai Owner).

### 3.2 Build & Flash Firmware ESP32

1. Buka file **`esp32_firmware/src/main/main.ino`** di Arduino IDE
   (membuka `main.ino`, bukan folder `src/`). Arduino IDE akan otomatis
   memuat `config.h` karena berada di folder sketch yang sama.
2. Edit `esp32_firmware/src/main/config.h`:
   ```c
   #define WIFI_SSID        "nama_wifi_anda"
   #define WIFI_PASSWORD    "password_wifi_anda"
   #define FIREBASE_HOST    "your-project-default-rtdb.asia-southeast1.firebasedatabase.app"
   #define FIREBASE_AUTH    "<database_secret_dari_step_2.1.3>"
   ```
   - `DEFAULT_DEVICE_ID` sengaja dipatok ke `ESP32_MAC_A1B2C3D4E5F6`
     supaya cocok dengan `seed.json`. Saat siap produksi, hapus baris
     `strncpy(g_deviceId, DEFAULT_DEVICE_ID, …)` di `main.ino` agar device
     pakai MAC-nya sendiri.
3. Pilih board: **Tools → Board → esp32 → "ESP32 Dev Module"**, partition
   scheme **"Minimal SPIFFS (1.9MB APP / 190KB SPIFFS)"** atau yang lebih
   besar (firmware + Firebase lib cukup gemuk).
4. Pilih port COM yang sesuai → klik **Upload** (Ctrl+U).
5. Buka **Serial Monitor** di baud **115200**. Boot sukses ditandai log:
   ```
   [BOOT] Setup selesai. Task FreeRTOS berjalan.
   [WIFI] Terhubung. IP = 192.168.x.x
   [FB] Stream listener aktif pada /devices/ESP32_MAC_.../components/relay_1
   ```
6. Hardware (opsional untuk uji nyata): relay aktif-HIGH ke **GPIO 12**.
   Tanpa relay, Anda tetap bisa memantau perubahan state via Serial.

### 3.3 Jalankan Flutter App

```bash
cd D:/SmartHome/flutter_app

# Install dependency
flutter pub get
```

Konfigurasi Firebase sisi Flutter (sekali saja). Repo ini **tidak**
menyertakan `firebase_options.dart` / `google-services.json` karena
kredensial bersifat per-proyek. Buat dengan FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<firebase-project-id>
```

CLI akan otomatis:
- Menambahkan `lib/firebase_options.dart`.
- Meletakkan `android/app/google-services.json`.
- Mengonfigurasi gradle plugin `com.google.gms.google-services`.

Jalankan:

```bash
# Cek device terkoneksi
flutter devices

# Jalankan (debug)
flutter run
```

Login pakai email Owner yang Anda buat di langkah 3.1 (pastikan
`status: "Approved"` di RTDB). Setelah masuk, switch relay di UI akan
memantulkan perubahan ke ESP32 dalam < 1 detik. Toggle relay fisik via
hardware akan terlihat real-time di UI lewat stream listener.

---

## 4. Verifikasi End-to-End

Checklist berikut memastikan tiga lapisan saling bicara:

- [ ] ESP32 Serial Monitor menunjukkan `[FB] Stream listener aktif`.
- [ ] Node `/devices/<id>/metadata/status` di Firebase Console = `"Online"`.
- [ ] Flutter Dashboard menampilkan device card dengan label
      *"Lampu Teras Utama"*.
- [ ] Menggeser Switch di app → log ESP32 muncul:
      `[FLASH] State relay_1 terkomit: ON/OFF` (setelah 5 detik debounce).
- [ ] Cabut listrik ESP32 → Console RTDB melihat `metadata.status` flip
      ke `"Offline"` otomatis (handler `onDisconnect`).
- [ ] Reset ESP32 → relay kembali ke state terakhir sebelum < 100 ms
      (Fail-Safe Boot Recovery).

---

## 5. Troubleshooting Singkat

| Gejala | Akar Masalah | Solusi |
| --- | --- | --- |
| `fatal error: ../config.h: No such file or directory` | Arduino IDE tidak mendukung path relatif ke luar folder sketch. | `config.h` sudah dipindah ke `src/main/`. Pastikan Anda membuka `main.ino` dari folder tersebut. |
| `Permission denied` saat toggle relay di app | User Anda berstatus `Pending` atau `owner_uid` tidak match UID Auth. | Update node `/users/<uid>/status` → `"Approved"` dan `/devices/<id>/metadata/owner_uid` → UID Anda. |
| ESP32 reboot loop dengan log `Preferences gagal di-mount` | Partisi NVS korup. | Tools → Erase Flash → "All Flash Contents", lalu re-upload. |
| Flutter `MissingPluginException(firebase_core)` | Lupa menjalankan `flutterfire configure`. | Ulangi langkah 3.3 bagian FlutterFire CLI. |
| Stream RTDB di Flutter tidak update | Security rules menolak baca. | Cek `/users/<uid>/status === "Approved"` (rules butuh ini untuk `.read`). |

---

## 6. Roadmap Singkat

Fase 1 (sekarang) → kontrol manual + schedule waktu untuk 1 relay.
Fase 2 → Cloud Functions presence bridge, histeresis sensor input,
auto-discovery komponen via HTTP register, Firestore RBAC kaya, App Check.

Detail roadmap dan keputusan desain ada di `docs/PRD.md` dan
`docs/architecture_flow.md`.
