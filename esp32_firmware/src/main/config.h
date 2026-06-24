// File: esp32_firmware/src/main/config.h
// Header konfigurasi statis untuk firmware SmartHome Core (Fase 1 MVP).
// Memusatkan kredensial jaringan, alamat pin GPIO, key Preferences, dan
// timing non-blocking agar mudah disesuaikan tanpa menyentuh logika utama.
//
// CATATAN STRUKTUR FOLDER (Arduino IDE):
//   Arduino IDE mewajibkan seluruh header pendamping sketch berada di
//   dalam folder yang sama dengan file `.ino`. Itulah sebabnya file ini
//   berada di `src/main/config.h` (sebelah `main.ino`), bukan di
//   `src/config.h`. Jangan dipindah ke luar folder `main/`.

#ifndef SMARTHOME_CONFIG_H
#define SMARTHOME_CONFIG_H

#include <Arduino.h>

#if defined(__has_include)
  #if __has_include("config.secrets.h")
    #include "config.secrets.h"
  #endif
#endif

#ifndef WIFI_SSID
#define WIFI_SSID                    "YOUR_WIFI_SSID"
#endif

#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD                "YOUR_WIFI_PASSWORD"
#endif

#ifndef FIREBASE_HOST
#define FIREBASE_HOST                "YOUR_FIREBASE_HOST"
#endif

#ifndef FIREBASE_AUTH
#define FIREBASE_AUTH                "YOUR_FIREBASE_AUTH"
#endif

// =============================================================================
// IDENTITAS PERANGKAT (acuan: docs/mock_database_seed.json)
// =============================================================================
// MAC Address ESP32 menjadi Device ID unik pada node RTDB
// /devices/<DEVICE_ID>. Untuk Fase 1, kita kunci ke entri seed pertama.
// Saat produksi, nilai ini wajib di-override dengan WiFi.macAddress() yang
// dibaca pada saat boot (lihat main.ino::buildDeviceIdFromMac()).
#define DEFAULT_DEVICE_ID            "ESP32_MAC_A1B2C3D4E5F6"

// =============================================================================
// KREDENSIAL JARINGAN (nilai aktual diambil dari config.secrets.h saat tersedia)
// =============================================================================

// =============================================================================
// PIN HARDWARE FASE 1 (acuan: docs/PRD.md bab 3.A)
// =============================================================================
// Fase 1 mendukung 2 buah relay output.
// Relay diasumsikan modul aktif HIGH; jika modul Anda aktif LOW,
// balik logika di applyRelayState() pada main.ino.
#define PIN_RELAY_1                  4
#define PIN_RELAY_2                  16
#define RELAY_ACTIVE_LEVEL           LOW
#define RELAY_INACTIVE_LEVEL         HIGH

// =============================================================================
// KEY PREFERENCES (Non-Volatile Storage) - max 15 karakter per key
// =============================================================================
// Namespace utama untuk seluruh state firmware
#define PREF_NAMESPACE               "smarthome"

// Key penyimpanan state relay & checksum (acuan: edge case "Flash Korup"
// pada docs/PRD.md bab 6.D)
#define PREF_KEY_RELAY1_STATE        "r1_state"   // bool: status terakhir
#define PREF_KEY_RELAY1_CHECKSUM     "r1_chksum"  // uint32_t: CRC sederhana
#define PREF_KEY_RELAY2_STATE        "r2_state"   // bool: status terakhir
#define PREF_KEY_RELAY2_CHECKSUM     "r2_chksum"  // uint32_t: CRC sederhana

// Key penyimpanan array schedules (di-serialize sebagai string JSON
// untuk menjaga fidelitas dengan node RTDB)
#define PREF_KEY_SCH1_JSON           "s1_json"
#define PREF_KEY_SCH1_CHECKSUM       "s1_chksum"
#define PREF_KEY_SCH2_JSON           "s2_json"
#define PREF_KEY_SCH2_CHECKSUM       "s2_chksum"

// =============================================================================
// NTP - Sinkronisasi waktu lokal Indonesia (UTC+7)
// =============================================================================
#define NTP_SERVER_PRIMARY           "id.pool.ntp.org"
#define NTP_SERVER_SECONDARY         "pool.ntp.org"
#define NTP_TIMEZONE_OFFSET_SEC      (7 * 3600)   // WIB
#define NTP_DAYLIGHT_OFFSET_SEC      0


// =============================================================================
// TIMING NON-BLOCKING (millis based - acuan: docs/skill.md bab 3 - ESP32)
// =============================================================================
// Buffer debounce 5 detik sebelum menulis state ke flash (mitigasi
// wear-out, docs/PRD.md bab 6.B).
#define FLASH_WRITE_DEBOUNCE_MS      5000UL

// Interval evaluasi schedule pada Task hardware (Core 1).
// Cukup 1x per detik untuk akurasi menit-an tanpa membebani CPU.
#define SCHEDULE_EVAL_INTERVAL_MS    1000UL

// Interval rekoneksi Wi-Fi asinkron (acuan: architecture_flow.md sec.4 -
// "Core 0 Menjalankan Loop Rekoneksi Asinkron Setiap 10 Detik").
#define WIFI_RECONNECT_INTERVAL_MS   10000UL

// Timeout sinkronisasi NTP pertama saat boot. Jika lewat, otomatisasi waktu
// di-suspend (acuan: architecture_flow.md sec.4 - cabang "F -- Tidak").
#define NTP_INITIAL_SYNC_TIMEOUT_MS  15000UL

// =============================================================================
// PARAMETER FreeRTOS
// =============================================================================
#define NETWORK_TASK_NAME            "NetworkTask"
#define NETWORK_TASK_STACK           8192    // RTDB + WiFi butuh stack besar
#define NETWORK_TASK_PRIORITY        1
#define NETWORK_TASK_CORE            0

#define HARDWARE_TASK_NAME           "HardwareTask"
#define HARDWARE_TASK_STACK          4096
#define HARDWARE_TASK_PRIORITY       2       // sedikit lebih tinggi -
                                             // hardware harus responsif
#define HARDWARE_TASK_CORE           1

// =============================================================================
// PATH NODE RTDB (Fase 1: satu device, dua relay)
// =============================================================================
// Sintaks dinamis: composeRelayStatePath() pada main.ino akan menggabung
// DEFAULT_DEVICE_ID + relay component path saat runtime.
#define RTDB_PATH_DEVICES_ROOT       "/devices/"
#define RTDB_PATH_COMPONENTS_ROOT    "/components"
#define RTDB_PATH_RELAY_1_COMPONENT  "/components/relay_1"
#define RTDB_PATH_RELAY_2_COMPONENT  "/components/relay_2"
#define RTDB_PATH_RELAY_STATE_KEY    "current_state"
#define RTDB_PATH_RELAY_SCHEDULES    "schedules"
#define RTDB_PATH_METADATA_STATUS    "/metadata/status"
#define RTDB_PATH_METADATA_LAST_BOOT "/metadata/last_boot_report"

// Batas maksimum jadwal yang disinkronisasi & dievaluasi lokal.
// Membatasi konsumsi heap untuk ArduinoJson dan iterasi array.
#define MAX_LOCAL_SCHEDULES          16

#endif // SMARTHOME_CONFIG_H
