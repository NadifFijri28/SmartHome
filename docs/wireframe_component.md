Berikut adalah draf lengkap untuk file **`wireframe_component.md`**. File ini dirancang dengan spesifikasi tata letak (*layout layout rules*), struktur hierarki *widget*, kode warna, hingga penanganan *state* visual (seperti kondisi *online/offline* dan pemisahan hak akses RBAC).

Dokumen ini menggunakan format Markdown terstruktur yang sangat mudah dipetakan oleh Agentic AI menjadi susunan komponen UI di Flutter (`Card`, `ListView`, `Dropdown`, dll.).

---

# WIREFRAME COMPONENT & UI RENDERING RULES

Dokumen ini mengatur standar arsitektur antarmuka (*UI/UX Standards*), tata letak responsif, kode warna, dan aturan transformasi komponen dinamis (*Agnostic UI Rendering*) pada aplikasi Android Flutter.

---

## 1. Desain Layout Utama (Shell Architecture)

Aplikasi menggunakan struktur halaman tunggal berbasis `Scaffold` dengan komponen utama berupa **Navigation Drawer** di sisi kiri dan **Main Control Area** di sisi kanan (pusat layar).

```
+--------------------------------------------+
| [=] SmartHome Core                         |
+--------------------------------------------+
|                                            |
|  +--------------------------------------+  |
|  | Device: Hub Utama Ruang Tengah       |  |
|  | Status: Online                       |  |
|  +--------------------------------------+  |
|                                            |
|  ZONA OUTPUT (RELAY)                       |
|  +--------------------------------------+  |
|  | [Icon] Lampu Teras Utama      (Toggle) |  |
|  | . . . . . . . . . . . . . . . . . .  |  |
|  | [Alarm Icon] Otomatisasi Malam Hari  |  |
|  +--------------------------------------+  |
|                                            |
|  ZONA INPUT (SENSOR)                       |
|  +--------------------------------------+  |
|  | Sensor Suhu Kamar Server             |  |
|  | Value: 30.5 °C                       |  |
|  |                        [Atur Logika] |  |
|  +--------------------------------------+  |
|                                            |
+--------------------------------------------+

```

### A. Sisi Kiri: Navigation Drawer (Lebar Tetap: 304dp)

* **Header Drawer:** Profil user aktif (Foto, Nama, dan Badge Status: `Owner` atau `Approved User`).
* **Body Drawer:** * *Indikator Kuota Pengguna (Hanya Terbuka untuk Owner):* Bilah progress dinamis (LinearProgressIndicator) + Slider/Counter untuk mengubah batas kuota.
* *Menu Akses Pengguna (User Control Panel - Hanya Owner):* List user dengan status *Pending* (dilengkapi tombol hijau *Approve* dan tombol merah *Reject*) serta list user aktif (dilengkapi icon sampah/hapus untuk *Kick Mechanism*).
* *Daftar Perangkat (Device Selector):* `ListView.builder` menampilkan nama perangkat ESP32 yang terdaftar + dot indikator warna status koneksi (Hijau = Online, Abu-abu = Offline).



### B. Sisi Kanan: Main Control Area (Responsive Dashboard)

Menampilkan komponen dari perangkat yang dipilih pada Drawer secara dinamis menggunakan `StreamBuilder` yang melanggan ke node komponen RTDB.

---

## 2. Palet Warna Sistem (Strict Color Palette)

AI wajib menggunakan variabel warna berikut untuk menjaga konsistensi visual *state* perangkat:

| Nama Variabel | Hex Code | Peruntukan Elemen |
| --- | --- | --- |
| `PrimaryCanvas` | `#F8F9FA` | Latar belakang aplikasi (*Scaffold Background*) |
| `CardBackground` | `#FFFFFF` | Latar belakang kartu komponen dinamis |
| `StateActive` | `#FFD700` | Warna Icon & Batas Saklar saat Relay **ON** (Kuning Emas) |
| `StateInactive` | `#9E9E9E` | Warna Icon & Batas Saklar saat Relay **OFF** (Abu-abu Tua) |
| `StatusOnline` | `#4CAF50` | Dot indikator perangkat aktif (Hijau) |
| `StatusOffline` | `#757575` | Dot indikator perangkat terputus + Overlay Kartu (Abu-abu) |
| `TextMain` | `#212121` | Judul komponen dan teks utama (Hitam Pekat) |
| `TextSub` | `#757575` | Label sub-informasi, jam alarm, dan satuan unit (Abu-abu) |

---

## 3. Aturan Render Komponen Dinamis (Agnostic UI Rules)

Saat memproses array `components` dari data JSON, AI harus melakukan *looping* dan memisahkan komponen menjadi dua kategori blok vertikal menggunakan `SingleChildScrollView` dan `Column`:

### A. Komponen Tipe `OUTPUT` (Elemen Visual: `SWITCH`)

Render setiap item menjadi sebuah objek `Card` dengan elevasi `2.0`, margin `vertical: 8.0, horizontal: 16.0`. Di dalam kartu wajib memiliki struktur *widget* tiga tingkat:

1. **Row Tingkat Atas (Kontrol Instan):**
* *Leading:* `Icon(Icons.lightbulb)` dengan warna dinamis sesuai status (`current_state == true ? StateActive : StateInactive`).
* *Title:* Teks `label` komponen dengan parameter `TextStyle(fontWeight: FontWeight.bold, color: TextMain)`.
* *Trailing:* `Switch` widget (atau `CupertinoSwitch`). Aksi `onChanged` akan langsung menembak perubahan boolean ke node `current_state` di RTDB.


2. **Divider:** `Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE))` jika komponen memiliki array `schedules`.
3. **Expansion / Sub-List (Daftar Alarm):**
* Gunakan `ListView.builder` (dengan `shrinkWrap: true` dan `physics: NeverScrollableScrollPhysics`) untuk merender array `schedules`.
* Setiap jadwal digambar dengan widget `ListTile`:
* *Leading:* Icon jam alarm kecil.
* *Title:* String gabungan `on_time` dan `off_time` (Contoh format besar: **18:00 - 05:30**).
* *Subtitle:* Teks `label` nama jadwal (Contoh: "Otomatisasi Malam Hari").
* *Trailing:* `Switch` kecil khusus untuk mengubah properti boolean `is_active` pada jadwal tersebut.


* *Tombol Tambah Jadwal:* Tampilkan tombol teks "+ Tambah Jadwal" di bagian bawah kartu khusus untuk pengguna berstatus `Owner`.



### B. Komponen Tipe `INPUT` (Elemen Visual: `GAUGE_TEXT`)

Render setiap item menjadi objek `Card` dengan dimensi yang sama. Struktur di dalam kartu:

1. **Layout Utama (Data Telemetri):**
* *Leading:* `Icon(Icons.thermostat)` atau icon sensor yang sesuai.
* *Title:* Teks `label` sensor (Contoh: "Sensor Suhu Kamar Server").
* *Subtitle:* Menampilkan nilai pembacaan `current_value` dengan ukuran font besar (`32sp`), tebal (`FontWeight.bold`), berwarna `TextMain`, dan diakhiri satuan unit (Contoh: **30.5 °C**).


2. **Aksi Kondisional (Tombol Atur Otomatisasi):**
* Di pojok kanan bawah kartu, tampilkan `TextButton_icon` dengan label "Atur Otomatisasi". Tombol ini **hanya muncul jika user yang login adalah Owner**.
* Jika diklik, tombol ini memicu fungsi `showModalBottomSheet()` untuk membuka formulir pembuatan aturan (*rules threshold*).



---

## 4. Spesifikasi Komponen Modal Pop-Up (Automation Rules Form)

Formulir di dalam `showModalBottomSheet()` untuk mengatur otomatisasi sensor wajib memiliki komponen input sebagai berikut secara berurutan:

1. **Header Modal:** Teks judul "Buat Aturan Otomatisasi - [Nama Sensor]" + Tombol tutup (*Close Icon*).
2. **Dropdown Kondisi Logika:** Memilih jenis perbandingan nilai. Pilihan isi dropdown:
* `GREATER_THAN` (Teks UI: "Lebih Besar Dari (>)")
* `LESS_THAN` (Teks UI: "Lebih Kecil Dari (<)")
* `EQUAL` (Teks UI: "Sama Dengan (=)")


3. **Input Field Nilai Batas:** `TextField` dengan parameter `keyboardType: TextInputType.numberWithOptions(decimal: true)` untuk mengisi angka *threshold* (Contoh: `31.0`).
4. **Dropdown Target Output:** Mengambil data list komponen berjenis `OUTPUT` yang ada pada perangkat tersebut (Contoh isi dropdown: "Lampu Teras Utama", "Kipas Exhaust"). User memilih satu sebagai target eksekusi.
5. **Toggle Aksi Target:** `SwitchListTile` untuk menentukan kondisi target saat terpicu (Pilihan: "Nyalakan Perangkat" [`action: true`] atau "Matikan Perangkat" [`action: false`]).
6. **Tombol Eksekusi:** `ElevatedButton` besar di bagian bawah berwarna biru/hijau bertuliskan "Simpan Aturan" yang memicu penulisan peta aturan baru ke node `rules` di database.

---

## 5. Visual State Exception Handling (Aturan Kondisi Khusus)

### A. Perangkat Berstatus `Offline`

Jika parameter `metadata/status == 'Offline'`, AI wajib menerapkan **Visual Overlay Masking** pada seluruh halaman kontrol perangkat:

* Setiap kartu komponen (`INPUT` dan `OUTPUT`) diberi efek opacity sebesar `0.5` (`Opacity(opacity: 0.5)`).
* Semua interaksi saklar (`Switch`) dan tombol aturan wajib diset ke kondisi `enabled: false` (dinonaktifkan total agar tidak bisa diklik).
* Tampilkan banner tipis berwarna abu-abu gelap di bagian atas layar dengan teks *"Koneksi dengan perangkat terputus. Menggunakan mode baca terakhir (Offline Mode)"*.

### B. Proteksi Tampilan Pengguna Biasa (RBAC UI Masking)

Jika user yang masuk memiliki status akreditasi `Approved` tetapi **bukan** `Owner`:

* Sembunyikan menu *User Control Panel* di Navigation Drawer.
* Sembunyikan tombol "+ Tambah Jadwal" pada komponen Output.
* Sembunyikan tombol "Atur Otomatisasi" pada komponen Input.
* Aplikasi hanya bertindak sebagai media monitor sensor dan pengubah saklar manual (jika diizinkan oleh aturan database).

---

### Aturan Tambahan untuk Agentic AI:

* Pastikan tidak ada penggunaan nilai *padding* atau *margin* keras (*hardcoded width/height*) tanpa pembungkus responsif jika layout tersebut berpotensi memicu tanda peringatan garis hitam-kuning (*Yellow Border Layout Overflow*) pada Android dengan resolusi layar kecil (gunakan `Flexible` atau `Expanded` pada struktur `Row`).
* Semua dialog konfirmasi hapus jadwal atau kick user wajib menggunakan komponen `AlertDialog` standar material design dengan tombol aksi tegas ("BATAL" / "HAPUS").