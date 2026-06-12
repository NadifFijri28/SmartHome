Berikut adalah draf lengkap untuk file **`architecture_flow.md`**. File ini ditulis menggunakan kombinasi penjelasan sekuensial dan diagram berbasis **Mermaid.js** (yang sangat dimengerti oleh Agentic AI seperti Cursor atau Trae) untuk mengunci pemahaman AI mengenai urutan eksekusi sistem saat *booting*, sinkronisasi data, hingga penanganan kondisi *offline*.

---

# ARCHITECTURE FLOW & SYSTEM LIFECYCLE

Dokumen ini mengatur urutan eksekusi (*state lifecycle*), diagram sekuensial, dan percabangan logika untuk ekosistem SmartHome Core. Seluruh komponen (ESP32, Flutter, dan Firebase) wajib mematuhi alur yang didefinisikan di bawah ini.

---

## 1. Booting Sequence (Urutan Inisialisasi Hardware)

Saat ESP32 dinyalakan kembali (*cold boot* atau pasca mati listrik), perangkat wajib mengeksekusi status aman sirkuit terlebih dahulu sebelum membuka soket jaringan. Alur eksekusi dijabarkan dalam diagram berikut:

```mermaid
sequenceDiagram
    autonumber
    participant HW as ESP32 Hardware Pins
    participant Flash as Preferences.h (Flash)
    participant WiFi as Core 0 (WiFi Task)
    participant NTP as NTP Server
    participant RTDB as Firebase RTDB

    Note over HW, Flash: Tahap 1: Fail-Safe Recovery (< 100ms)
    HW->>Flash: Ambil status relay terakhir & Checksum
    alt Checksum Valid
        Flash-->>HW: State Terakhir (Contoh: Relay 1 = ON)
        HW->>HW: Eksekusi HIGH ke Pin Fisik
    else Checksum Corrupt / Kosong
        Flash-->>HW: Gagal Baca / Factory Default
        HW->>HW: Set Semua Pin Relay = LOW (OFF)
    end

    Note over HW, WiFi: Tahap 2: Network & Time Sync (Asinkron Core 0)
    WiFi->>WiFi: Jalankan Auto-Reconnect Loop
    WiFi->>NTP: Request Sinkronisasi Waktu (id.pool.ntp.org)
    NTP-->>WiFi: Kirim Epoch Time / Unix Timestamp
    WiFi->>WiFi: Set Internal Software RTC

    Note over WiFi, RTDB: Tahap 3: Cloud Stream Handshake
    WiFi->>RTDB: Hubungkan Firebase Stream Listener (Node 'components')
    RTDB-->>WiFi: Kirim Payload Konfigurasi Terbaru (JSON)
    WiFi->>Flash: Perbarui buffer Jadwal & Aturan Lokal jika ada perubahan

```

---

## 2. Data Synchronization Flow (Alur Pertukaran Data Real-Time)

### A. Kontrol Manual via Aplikasi Mobile (Flutter $\rightarrow$ RTDB $\rightarrow$ ESP32)

Ketika pengguna menekan tombol saklar pada aplikasi Flutter, urutan pembaruan data harus mengikuti jalur sub-200ms berikut:

```mermaid
sequenceDiagram
    autonumber
    participant App as Flutter Mobile App
    participant Rules as Firebase Security Rules
    participant RTDB as Realtime Database Node
    participant CF as Cloud Functions (Server)
    participant ESP as ESP32 Firmware

    App->>Rules: Tulis data baru: current_state = true (via HTTPS/Websocket)
    Note over Rules: Validasi RBAC & Whitelist Owner
    alt User is Approved & Whitelisted
        Rules->>RTDB: Komit Perubahan ke Node `devices/$device_id/components/$relay_id/current_state`
        RTDB-->>App: Kirim Instant Visual Feedback (< 200ms)
        RTDB->>ESP: Trigger Event Stream (Data Push ke Hardware)
        ESP->>ESP: Ubah status Pin Fisik menjadi HIGH
        ESP->>ESP: Tahan status di RAM (Mulai hitung mundur jeda 5 detik untuk simpan Flash)
    else User Not Approved / Unauthorized
        Rules-->>App: Kembalikan Error 403 (Ditolak Mentah-Mentah)
        App->>App: Revert Tampilan Saklar ke posisi semula
    end

```

### B. Otomatisasi Waktu Lokal (Internal ESP32 Loop)

Logika eksekusi alarm jadwal dilakukan sepenuhnya di dalam internal chip tanpa memantulkan request ke internet:

```mermaid
graph TD
    A[Mulai Setiap Menit: FreeRTOS Task 2] --> B[Baca Internal Software RTC Jam Sekarang HH:mm]
    B --> C[Looping Array schedules dari Preferences.h]
    C --> D{Apakah schedule.is_active == true?}
    D -- Tidak --> E[Lewati ke Schedule Berikutnya]
    D -- Ya --> F{Apakah Jam Sekarang == on_time?}
    F -- Ya --> G[Set Pin Relay = HIGH / ON]
    F -- Tidak --> H{Apakah Jam Sekarang == off_time?}
    H -- Ya --> I[Set Pin Relay = LOW / OFF]
    H -- Tidak --> E
    G --> J[Kirim Event-Driven Report ke RTDB: current_state = true]
    I --> K[Kirim Event-Driven Report ke RTDB: current_state = false]

```

---

## 3. Server-Side Hysteresis Logic (Sensor Telemetry Function)

Untuk mencegah kerusakan kumparan relay akibat pembacaan sensor yang berosilasi secara cepat di titik ambang batas (*flapping*), Cloud Functions wajib mengevaluasi aturan berbasis rumus toleransi $1.5^\circ\text{C}$ sebelum memanipulasi *state* database:

```mermaid
graph TD
    A[ESP32 Kirim current_value Sensor Baru ke RTDB] --> B[Cloud Function Terpicu via OnWrite Event]
    B --> C[Parsing Aturannya: Contoh Threshold = 31.0°C, Kondisi = GREATER_THAN]
    C --> D{Apakah current_value > 31.0°C?}
    D -- Ya --> E{Apakah Relay saat ini OFF?}
    E -- Ya --> F[Set current_state Target Relay = true / ON]
    E -- Tidak --> G[Abaikan / Tetap ON]
    
    D -- Tidak --> H{Apakah current_value <= 29.5°C?}
    Note over H: Rumus Deaktivasi Histeresis:<br>Threshold - 1.5°C = 29.5°C
    H -- Ya --> I{Apakah Relay saat ini ON?}
    I -- Ya --> J[Set current_state Target Relay = false / OFF]
    I -- Tidak --> K[Abaikan / Tetap OFF]
    H -- Tidak --> L[Abaikan: Suhu berada dalam rentang toleransi flapping]

```

---

## 4. Offline State Handling & Connection Loss

Sistem harus menangani kehilangan koneksi internet atau kegagalan sinkronisasi waktu (*NTP timeout*) dengan parameter aman (*fail-safe*) sebagai berikut:

```mermaid
graph TD
    A[ESP32 Terputus dari Wi-Fi / Cloud] --> B[Firebase Server Mendeteksi via onDisconnect]
    B --> C[Server Otomatis Mengubah Node status = 'Offline']
    C --> D[Flutter App Menerima Stream & Menampilkan Label Perangkat Offline]
    
    A --> E[ESP32 Masuk ke Mode Offline Resilience]
    E --> F{Apakah Waktu NTP Sempat Sinkron Sebelum Putus?}
    F -- Ya --> G[Otomatisasi Waktu / Alarm Tetap Berjalan di Latar Belakang]
    F -- Tidak --> H[Tangguhkan Seluruh Otomatisasi Berbasis Waktu]
    H --> I[Nyalakan Indikator Error / Izinkan Kontrol Fisik Push-Button Lokal]
    
    E --> J[Core 0 Menjalankan Loop Rekoneksi Asinkron Setiap 10 Detik]
    J --> K{Wi-Fi Terhubung Kembali?}
    K -- Ya --> L[Kirim Booting Report Baru + Ambil Sinkronisasi State Terbaru dari Cloud]
    K -- Tidak --> J

```

---

### Aturan Tambahan untuk Agentic AI:

* Ketika mengimplementasikan kode program, pastikan struktur *percabangan kondisional* (`if-else`) pada blok kode Anda merefleksikan diagram alur di atas secara presisi.
* Jangan pernah menyisipkan fungsi pembersihan memori flash (`Preferences.clear()`) secara otomatis pada alur penanganan error koneksi internet. Data lokal harus dipertahankan dalam kondisi apa pun kecuali saat *hardware factory reset* dipicu secara fisik.