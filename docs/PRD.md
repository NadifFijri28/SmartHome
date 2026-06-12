
---
# PRODUCT REQUIREMENT DOCUMENT (PRD)

**Nama Projek:** SmartHome Core - Dynamic IoT System (Production Ready)

**Target Platform:** Hardware (ESP32), Backend Server (Node.js/Firebase Cloud Functions), Mobile App (Android - Flutter)

**Penulis:** Nadif Fijri Fajar Arifin

---

## 1. Objective & Tujuan Projek

Membentuk ekosistem *smart home* mandiri yang mampu mendeteksi perangkat hardware baru secara otomatis (*auto-discovery*), mengklasifikasikan komponen secara dinamis (Input vs Output), serta menjalankan logika otomatisasi yang andal dan hemat resource.

Sistem ini memprioritaskan keamanan tingkat tinggi melalui integrasi arsitektur Firebase, memberikan kedaulatan penuh kepada Owner melalui sistem autentikasi yang tertanam pada perangkat fisik (*hardware anchor*), serta menerapkan efisiensi pertukaran data untuk meminimalkan beban komputasi cloud maupun batasan fisik *hardware*.

---

## 2. Arsitektur Sistem & Alur Data

Sistem menggunakan pendekatan *Hybrid Serverless Architecture* demi efisiensi resource, ketahanan offline, dan skalabilitas maksimal:

* **Provisioning & Auth Validation:** Saat pertama kali menyala, ESP32 mendaftarkan struktur PIN fisiknya via HTTP POST JSON ke Firebase Cloud Functions. Untuk proses masuk aplikasi oleh Owner, backend akan melakukan jabat tangan (*handshake*) kriptografi ke memori lokal ESP32 untuk memvalidasi kredensial pemilik sah.
* **Real-Time Sync via Dual-Database:** Perubahan status saklar dan kontrol manual dikelola oleh Firebase Realtime Database (RTDB) demi performa transmisi sub-200ms. Sementara itu, data manajemen akses pengguna, kuota, dan arsitektur RBAC disimpan di Firestore demi struktur query yang kaya.
* **Cloud Function Presence Bridge:** Sistem memanfaatkan Firebase Cloud Functions untuk menjembatani status konektivitas. Saat RTDB mendeteksi perubahan status koneksi perangkat secara pasif, Cloud Functions akan menyinkronkan status tersebut ke dokumen Firestore terkait secara otomatis.
* **Otomatisasi Mandiri (Edge Computing):** Logika operasional berbasis waktu disimpan di memori internal ESP32 (`Preferences.h`) dan dicocokkan dengan jam internet melalui NTP Server. Sistem tetap berjalan mandiri meskipun koneksi internet luar atau aplikasi HP mati.

---

## 3. Fitur Utama Per Komponen

### A. ESP32 Firmware (C++ / Arduino IDE)

* **Auto-Discovery:** Membaca alamat fisik MAC Address sebagai ID unik perangkat (*Device ID*).
* **Dynamic Payload:** Menggali status PIN dan mengirim daftar komponen aktif dalam format array JSON ke server saat proses registrasi awal.
* **Root of Trust (Owner Credentials):** Menyimpan data akun username dan `password_hash` milik Owner secara lokal di dalam memori flash (`Preferences.h`). ESP32 bertindak sebagai jangkar autentikasi utama (anti-lockout).
* **Booting Recovery:** Saat kembali menyala pasca mati lampu, ESP32 langsung membaca status terakhir relay di `Preferences.h` dan mengeksekusinya ke PIN fisik *sebelum* mencoba terhubung ke Wi-Fi agar rumah tidak mendadak gelap.
* **NTP Sync:** Melakukan sinkronisasi waktu akurat ke server `id.pool.ntp.org` via Wi-Fi untuk eksekusi jadwal lokal.

### B. Backend Server (Node.js Express / Firebase Cloud Functions)

* **Stateless Device Registry:** Menyediakan endpoint `/api/device/register` untuk menangkap dan memperbarui struktur komponen alat secara dinamis di Firestore. Endpoint ini dilindungi penuh oleh Firebase App Check.
* **Dual-Path Auth Bridge:** Memvalidasi permintaan masuk Owner dengan melempar *challenge* enkripsi ke ESP32 secara real-time, sekaligus mengelola registrasi akun pengguna biasa (non-owner) ke dalam basis data cloud.
* **Firebase App Check Integration:** Memeriksa token integritas dari Google Play Integrity API untuk memastikan tidak ada request ilegal dari luar aplikasi Flutter resmi.

### C. Mobile App (Android - Flutter)

* **Navigation Drawer Layout:** Sisi kiri menampilkan profil pengguna dan daftar perangkat ESP32 yang aktif. Sisi kanan menampilkan isi komponen dinamis dari perangkat yang dipilih.
* **Agnostic UI Rendering:** Menggunakan looping dinamis (`ListView.builder`) untuk menggambar komponen UI secara otomatis berdasarkan tipe data (Input/Sensor vs Output/Relay) yang dikirim oleh backend.
* **Role-Based Access Control (RBAC) UI Display:**
* *Tampilan Pengguna Biasa:* Hanya menampilkan Zona Input (Sensor) berupa grafik/gauge teks dan Zona Output (Relay) berupa tombol saklar (Switch) untuk kontrol manual.
* *Tampilan Eksklusif Owner:* Terbuka menu tambahan *User Control Panel* di dalam Navigation Drawer untuk manajemen akses rumah pintar.



---

## 4. Spesifikasi Logika Otomatisasi & Manajemen Akses

### A. Otomatisasi Perangkat

| Klasifikasi Perangkat | Fitur Otomatisasi (UI & Sistem) | Target Eksekusi & Proteksi |
| --- | --- | --- |
| **Perangkat Output (Relay)** | **Time-Based Automation:** Mengatur rentang waktu operasional (Jam/Menit ON dan OFF) via Android App. | Jadwal dikirim ke ESP32; chip mengeksekusi secara mandiri berdasarkan waktu NTP lokal (**Offline Resilience**). |
| **Perangkat Input (Sensor)** | **Threshold-Based Automation:** Menetapkan batas angka (misal suhu > 31°C) di HP untuk memicu perangkat output tertentu. | Logika dievaluasi pada aturan database cloud/server. Sistem wajib menerapkan **Histeresis (Rentang Toleransi)** sebesar 1.5°C di server untuk mencegah relay bergetar/rusak akibat nilai sensor yang berosilasi di sekitar angka batas. |

### B. Manajemen Pengguna (User Control Panel - Khusus Owner)

* **User Limit Cap:** Owner dapat melihat indikator kuota pengguna aktif (misal: 3 dari 5 slot terpakai) dan bebas mengubah batas maksimal (*limit*) pengguna melalui komponen counter/slider.
* **Whitelisting & Approval System:** Setiap pengguna baru wajib mendaftar akun dengan username + password. Status awal akun adalah *Pending*. Akun tidak akan bisa melihat atau mengontrol perangkat sampai statusnya diubah menjadi *Approved* oleh Owner.
* **Real-Time Kick Mechanism:** Jika Owner menekan tombol Hapus Akses, dokumen pengguna tersebut di Firestore akan terhapus. Aplikasi Flutter pada HP pengguna tersebut akan otomatis melakukan logout seketika melalui fungsi *Stream Listener*.

---

## 5. Kebutuhan Non-Fungsional & Optimasi Sistem

### A. Data Encryption & Isolation

Komunikasi data dari Flutter ke Firebase wajib dibungkus token HTTPS/JWT, dan komunikasi ke hardware menggunakan protokol aman terenkripsi (AES-128 atau SHA-256 via library `mbedtls` bawaan ESP32). Data antar-user diisolasi ketat di tingkat database.

### B. Sinkronisasi Status & Efisiensi Data (State Synchronization)

* **Lightweight State Synchronization:** Sistem dilarang menggunakan metode *periodic telemetry heartbeat* untuk menjaga efisiensi RAM ESP32 dan menekan biaya komputasi Serverless Cloud.
* **Event-Driven Reporting:** ESP32 hanya mengirimkan status relay ke database cloud pada dua kondisi: Saat pertama kali menyala kembali (*booting report*) dan saat terjadi transisi perubahan logika komponen (*state change event* dari tombol fisik/sensor). Jika tidak ada perubahan, hardware berada dalam mode silent.
* **Passive Offline Detection (onDisconnect):** Memanfaatkan fitur `onDisconnect` pada gerbang Firebase Realtime Database untuk mendeteksi hilangnya koneksi hardware secara pasif di sisi server. Jika perangkat kehilangan koneksi, Firebase server akan otomatis mengubah status device menjadi Offline secara real-time di aplikasi mobile tanpa membebani daya komputasi chip.

### C. Performa & Pengalaman Pengguna (UX)

* **Instant Visual Feedback:** Interaksi saklar manual wajib memberikan umpan balik visual instan kurang dari 200 ms (perubahan warna icon lampu dari abu-abu menjadi kuning emas saat aktif).
* **Android Layout Optimization:** Tata letak responsif untuk layar vertikal smartphone Android, menggunakan batas lebar navigasi drawer yang pas agar tidak memotong ruang kontrol utama pada layar.

---

## 6. Security & Error Handling

Bab ini mengatur mitigasi keamanan tingkat rendah, manajemen siklus hidup memori hardware, serta penanganan kegagalan sistem (*fail-safe mechanisms*) di lingkungan produksi.

### A. Server-Side Security Rules (Firebase Hardening)

Keamanan sistem dilarang keras hanya mengandalkan logika di sisi aplikasi Flutter (UI). Firebase Realtime Database dan Firestore wajib menerapkan aturan keamanan terpusat (*Security Rules*) untuk mencegah bypass request ilegal.

* **Firestore Rules (Manajemen Pengguna & Whitelist):**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /devices/{deviceId} {
      // Hanya Owner terdaftar yang bisa mengubah konfigurasi alat dan limit user
      allow write: if request.auth != null && resource.data.ownerUid == request.auth.uid;
      allow read: if request.auth != null;
    }
    match /users/{userId} {
      // User hanya bisa membaca datanya sendiri, Owner bisa mengelola semua user
      allow read, write: if request.auth != null && (request.auth.uid == userId || 
        get(/databases/$(database)/documents/devices/$(request.resource.data.deviceId)).data.ownerUid == request.auth.uid);
    }
  }
}

```



```
*   **Realtime Database Rules (Kontrol Saklar & Status Perangkat):**
    ```json
    {
      "rules": {
        "devices": {
          "$device_id": {
            "controls": {
              ".read": "auth != null && root.child('users').child(auth.uid).child('status').val() === 'Approved'",
              ".write": "auth != null && root.child('users').child(auth.uid).child('status').val() === 'Approved' && root.child('devices').child($device_id).child('whitelist').hasChild(auth.auth.uid)"
            },
            "status": {
              ".read": "auth != null",
              ".write": "auth != null && auth.uid === $device_id" 
            }
          }
        }
      }
    }

```

```
> **Mitigasi Race Condition:** Jika Owner menghapus akses seorang pengguna, meskipun HP pengguna tersebut terlambat melakukan logout otomatis akibat kendala jaringan, setiap instruksi tulis saklar yang dikirim oleh HP-nya akan langsung **ditolak mentah-mentah** di tingkat server oleh aturan database di atas.

```

### B. Hardware Memory Protection (Flash Wear-Out Mitigation)

Memori Flash ESP32 memiliki batasan siklus tulis (*write endurance limit* ~100.000 siklus). Untuk mencegah kerusakan memori (korup) akibat penulisan status relay yang terlalu sering:

* **Firmware Write Buffer & Debounce:** Firmware C++ wajib mengimplementasikan fungsi waktu non-blocking (`millis()`) sebagai *debounce filter*.
* **Aturan Jeda:** Setiap transisi status relay hanya akan ditulis ke `Preferences.h` jika status tersebut bertahan stabil minimal selama **5 detik**. Perubahan cepat di bawah 5 detik hanya akan ditahan pada RAM volatile dan tidak akan berkomitmen ke memori flash fisik.

### C. Network Failure & Connection Recovery

Ketika ESP32 mengalami pemutusan koneksi Wi-Fi secara mendadak saat beroperasi atau gagal mendapatkan jabat tangan saat proses *booting*:

* **Auto-Reconnect Loop:** Firmware tidak boleh masuk ke kondisi *blocking/freeze*. ESP32 wajib menjalankan fungsi reconnect Wi-Fi secara asinkron di latar belakang (*background task* menggunakan FreeRTOS Task pada Core 0).
* **Local Automation Safeguard:** Jika internet mati, otomatisasi berbasis waktu (*Time-Based*) tetap berjalan menggunakan basis waktu internal chip. Namun, jika internet mati saat *booting* sehingga waktu NTP tidak bisa sinkron, seluruh fungsi otomatisasi berbasis waktu akan **ditangguhkan otomatis** untuk menghindari eksekusi saklar pada jam yang salah, sementara kontrol fisik manual via tombol *push-button* lokal tetap diizinkan.

### D. Edge Cases: Simulasi Kegagalan & Fail-Safe State

Sistem wajib merespons skenario kegagalan ekstrem dengan parameter status yang aman (*fail-safe*):

| Skenario Kegagalan | Dampak Langsung | Tindakan Mitigasi Sistem (*Fail-Safe*) |
| --- | --- | --- |
| **Mati Listrik Massal (Hardware Reboots)** | ESP32 kehilangan daya secara mendadak dan menyala kembali. | **Booting Recovery:** Membaca status aman terakhir di `Preferences.h` dalam kurun waktu kurang dari 100ms pasca-booting, mengaktifkan pin relay ke kondisi terakhir sebelum mencoba inisialisasi tumpukan jaringan Wi-Fi. |
| **Osilasi Sensor Ekstrem (*Flapping*)** | Angka sensor berayun cepat di batas threshold (misal suhu naik turun 31°C ↔ 30.9°C). | **Server Histeresis:** Server mengunci perintah aktif jika suhu > 31°C dan hanya akan mengirimkan perintah mati jika suhu telah turun melewati rentang toleransi di bawah 29.5°C. |
| **Memori Flash `Preferences.h` Korup** | ESP32 gagal membaca status terakhir saat *booting*. | **Default State Factory:** Jika *checksum* internal memori gagal dibaca, firmware akan otomatis mengembalikan parameter ke status bawaan (*Factory Default*), yaitu mematikan seluruh relay (OFF) demi alasan keamanan sirkuit, lalu mengirimkan log error darurat ke Firestore saat internet terhubung kembali. |

---