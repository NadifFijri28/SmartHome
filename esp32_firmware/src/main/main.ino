// File: esp32_firmware/src/main/main.ino
// =============================================================================
// SmartHome Core - ESP32 Firmware (Fase 1 MVP)
// =============================================================================
// File inisialisasi utama untuk firmware perangkat. Mengimplementasikan:
//   1. Fail-Safe Boot Recovery < 100ms dengan checksum Preferences
//      (acuan: docs/architecture_flow.md sec.1 - Tahap 1).
//   2. Arsitektur dual-core FreeRTOS:
//      - Core 0 (NetworkTask)  -> Wi-Fi reconnect + Firebase RTDB stream
//      - Core 1 (HardwareTask) -> NTP read + GPIO write + schedule eval
//      (acuan: docs/skill.md bab 2.A & docs/architecture_flow.md sec.2.B).
//   3. Debounce 5 detik berbasis millis() sebelum write ke Preferences
//      (acuan: docs/PRD.md bab 6.B - Flash Wear-Out Mitigation).
//   4. Sinkronisasi non-blocking node `schedules` RTDB -> Preferences ->
//      evaluasi alarm waktu HH:mm lokal (acuan: architecture_flow.md sec.2.B).
//
// Dependency Arduino IDE Library Manager (semua tersedia di registry resmi):
//   - WiFi.h                       (built-in ESP32 core)
//   - Preferences.h                (built-in ESP32 core)
//   - time.h / esp_sntp.h          (built-in ESP-IDF)
//   - ArduinoJson           >= 6.21  (Benoit Blanchon)
//   - Firebase ESP Client   >= 4.4   (Mobizt) - sediakan stream realtime
// =============================================================================

#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <time.h>
#include <ArduinoJson.h>
#include <Firebase_ESP_Client.h>
#include <addons/RTDBHelper.h>
#include <addons/TokenHelper.h>

#include "config.h"

// =============================================================================
// GLOBAL STATE (dilindungi mutex jika diakses lintas-task)
// =============================================================================

// --- Firebase objects ----------------------------------------------------
static FirebaseData   fbStream;        // koneksi khusus stream (long-lived)
static FirebaseData   fbWrite;         // koneksi terpisah untuk write
static FirebaseAuth   fbAuth;
static FirebaseConfig fbConfig;

// --- State volatile (RAM) ------------------------------------------------
// State yang sedang berlaku pada hardware. Sumber kebenaran selama runtime.
static volatile bool    g_relayCurrentState[2]      = {false, false};
// Target dari RTDB yang menunggu di-commit ke flash setelah debounce.
static volatile bool    g_relayPendingFlashState[2] = {false, false};
// Timestamp millis() saat perubahan target terakhir terjadi; 0 = tidak ada
// pending. Digunakan oleh HardwareTask untuk hitung mundur 5 detik.
static volatile uint32_t g_relayPendingSinceMs[2]   = {0, 0};

// Penanda bahwa status relay lokal perlu dikirim ke RTDB oleh NetworkTask.
static volatile bool    g_relayPendingRtdbChange[2] = {false, false};
static volatile bool    g_relayPendingRtdbState[2]  = {false, false};
static portMUX_TYPE     g_relayPendingMux           = portMUX_INITIALIZER_UNLOCKED;

// Status sinkronisasi NTP. Jika false, eksekusi schedule ditangguhkan
// (acuan: architecture_flow.md sec.4 - "Tangguhkan Otomatisasi").
static volatile bool    g_ntpSynced                = false;

// Penanda apakah Wi-Fi pernah terhubung sukses minimal sekali. Berguna
// untuk membedakan kondisi "belum pernah online" vs "putus saat operasi".
static volatile bool    g_wifiEverConnected        = false;

// String Device ID yang dibangun dari MAC ESP32 saat boot.
static char             g_deviceId[24]             = {0};

// Mutex untuk akses array schedules (dipakai oleh NetworkTask saat sync
// dan oleh HardwareTask saat iterasi evaluasi).
static SemaphoreHandle_t g_schedulesMutex          = nullptr;

// Struktur ringkas jadwal (mirror dari node RTDB `schedules`).
struct LocalSchedule {
  char     id[24];
  bool     isActive;
  uint8_t  onHour;
  uint8_t  onMinute;
  uint8_t  offHour;
  uint8_t  offMinute;
};

static LocalSchedule   g_schedules[2][MAX_LOCAL_SCHEDULES];
static uint8_t         g_scheduleCount[2]             = {0, 0};

// Penanda menit terakhir yang sudah dievaluasi -> mencegah eksekusi ganda
// pada menit yang sama (HH:mm berlangsung 60 detik, evaluator jalan 1 Hz).
static int             g_lastEvaluatedMinuteKey    = -1;

// Preferences instance global (dibuka sekali, ditutup hanya saat reboot).
static Preferences     g_prefs;

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================
static void   buildDeviceIdFromMac();
static uint32_t computeChecksum(const uint8_t* data, size_t len);
static bool   loadRelayStateFromFlash(uint8_t relayIndex, bool& outState);
static void   commitRelayStateToFlash(uint8_t relayIndex, bool state);
static void   applyRelayState(uint8_t relayIndex, bool state);
static void   markRelayChangePending(uint8_t relayIndex, bool newState);
static void   processFlashDebounce(uint32_t nowMs);

static bool   connectWiFiOnce();
static void   ensureWiFiConnected(uint32_t nowMs);
static void   initFirebase();
static String composeRelayStatePath(uint8_t relayIndex);
static String composeSchedulesPath(uint8_t relayIndex);
static String composeMetadataStatusPath();
static String composeMetadataLastBootPath();
static String composeComponentsPath();

static void   startRtdbStream();
static void   handleRtdbStreamData();
static void   onRtdbStreamTimeout(bool timeout);

static void   syncSchedulesFromJson(uint8_t relayIndex, const String& jsonPayload);
static void   loadSchedulesFromFlash();
static void   persistSchedulesToFlash(uint8_t relayIndex, const String& jsonPayload);
static void   enqueueRelayStateWrite(uint8_t relayIndex, bool state);
static bool   consumePendingRelayWrite(uint8_t relayIndex, bool& outState);
static void   processPendingRelayWrite();
static void   evaluateSchedulesNow(const struct tm& nowLocal);

static void   networkTaskEntry(void* arg);
static void   hardwareTaskEntry(void* arg);


// =============================================================================
// SETUP - dipanggil sekali pada boot. WAJIB selesai < 100ms untuk fase
// Fail-Safe Recovery (acuan: architecture_flow.md sec.1 - Tahap 1).
// =============================================================================
void setup() {
  Serial.begin(115200);
  // Tidak menunggu Serial siap -> headless boot harus tetap jalan tanpa USB.

  // --- TAHAP 1: Fail-Safe Recovery (< 100ms) -----------------------------
  // Pin di-init lebih dulu agar tidak floating (mencegah relay click acak).
  pinMode(PIN_RELAY_1, OUTPUT);
  pinMode(PIN_RELAY_2, OUTPUT);
  digitalWrite(PIN_RELAY_1, RELAY_INACTIVE_LEVEL);
  digitalWrite(PIN_RELAY_2, RELAY_INACTIVE_LEVEL);

  if (!g_prefs.begin(PREF_NAMESPACE, /*readOnly=*/false)) {
    // Namespace gagal dibuka -> NVS rusak. Fallback Factory Default OFF,
    // sesuai tabel edge case docs/PRD.md bab 6.D.
    Serial.println(F("[BOOT] Preferences gagal di-mount. Factory Default OFF."));
    g_relayCurrentState[0] = false;
    g_relayCurrentState[1] = false;
    applyRelayState(0, false);
    applyRelayState(1, false);
  } else {
    for (uint8_t relayIndex = 0; relayIndex < 2; ++relayIndex) {
      bool persistedState = false;
      if (loadRelayStateFromFlash(relayIndex, persistedState)) {
        g_relayCurrentState[relayIndex] = persistedState;
        applyRelayState(relayIndex, persistedState);
        Serial.printf("[BOOT] State relay_%u dipulihkan: %s\n",
                      relayIndex + 1,
                      persistedState ? "ON" : "OFF");
      } else {
        Serial.printf("[BOOT] State relay_%u default OFF\n",
                      relayIndex + 1);
        g_relayCurrentState[relayIndex] = false;
        applyRelayState(relayIndex, false);
      }
    }
  }

  // --- TAHAP 2: Persiapan global lintas-task -----------------------------
  buildDeviceIdFromMac();
  g_schedulesMutex = xSemaphoreCreateMutex();
  configASSERT(g_schedulesMutex != nullptr);

  // Muat jadwal yang sebelumnya sudah ter-cache di flash agar otomatisasi
  // tetap berfungsi meski cloud belum reachable.
  loadSchedulesFromFlash();

  // --- TAHAP 3: Spawn dua task FreeRTOS terpisah core --------------------
  // Network di Core 0, Hardware di Core 1 (acuan: skill.md bab 3 - 🔴 ESP32).
  xTaskCreatePinnedToCore(
      networkTaskEntry,
      NETWORK_TASK_NAME,
      NETWORK_TASK_STACK,
      nullptr,
      NETWORK_TASK_PRIORITY,
      nullptr,
      NETWORK_TASK_CORE);

  xTaskCreatePinnedToCore(
      hardwareTaskEntry,
      HARDWARE_TASK_NAME,
      HARDWARE_TASK_STACK,
      nullptr,
      HARDWARE_TASK_PRIORITY,
      nullptr,
      HARDWARE_TASK_CORE);

  Serial.println(F("[BOOT] Setup selesai. Task FreeRTOS berjalan."));
}

// =============================================================================
// LOOP - sengaja kosong. Seluruh pekerjaan didelegasikan ke task FreeRTOS.
// Memberi yield ke idle task agar watchdog tidak trigger di Core 1.
// =============================================================================
void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}

// =============================================================================
// IDENTITAS DEVICE
// =============================================================================
static void buildDeviceIdFromMac() {
  // WiFi.macAddress() membutuhkan WiFi.mode() terlebih dahulu; gunakan
  // esp_efuse-based read untuk dapat dipanggil pra-WiFi.
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  snprintf(g_deviceId, sizeof(g_deviceId),
           "ESP32_MAC_%02X%02X%02X%02X%02X%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  Serial.printf("[ID] Device ID = %s\n", g_deviceId);

  // Untuk Fase 1 MVP, izinkan override paksa ke DEFAULT_DEVICE_ID supaya
  // seed mock_database_seed.json langsung match tanpa migrasi data.
  // Hapus baris ini saat produksi.
  strncpy(g_deviceId, DEFAULT_DEVICE_ID, sizeof(g_deviceId) - 1);
}

// =============================================================================
// PERSISTENCE (Preferences + Checksum)
// =============================================================================
static uint32_t computeChecksum(const uint8_t* data, size_t len) {
  // CRC-32 sederhana ala Adler/FNV-1a 32-bit. Cukup untuk integritas
  // konfigurasi non-keamanan (mendeteksi flash sector korup).
  uint32_t hash = 2166136261UL;
  for (size_t i = 0; i < len; ++i) {
    hash ^= data[i];
    hash *= 16777619UL;
  }
  return hash;
}

static const char* relayStateKey(uint8_t relayIndex) {
  return relayIndex == 0 ? PREF_KEY_RELAY1_STATE : PREF_KEY_RELAY2_STATE;
}

static const char* relayChecksumKey(uint8_t relayIndex) {
  return relayIndex == 0 ? PREF_KEY_RELAY1_CHECKSUM : PREF_KEY_RELAY2_CHECKSUM;
}

static bool loadRelayStateFromFlash(uint8_t relayIndex, bool& outState) {
  // Default value sengaja diberi 0xFF agar bisa dibedakan dari "tertulis 0".
  uint8_t  raw   = g_prefs.getUChar(relayStateKey(relayIndex), 0xFF);
  uint32_t store = g_prefs.getUInt(relayChecksumKey(relayIndex), 0);

  if (raw == 0xFF) {
    // Belum pernah ditulis (perangkat baru). Bukan "korup", tapi tidak
    // ada state untuk dipulihkan -> default OFF.
    return false;
  }
  uint32_t expected = computeChecksum(&raw, sizeof(raw));
  if (expected != store) {
    // Checksum tidak cocok -> data rusak. Lihat docs/PRD.md bab 6.D.
    return false;
  }
  outState = (raw == 1);
  return true;
}

static void commitRelayStateToFlash(uint8_t relayIndex, bool state) {
  uint8_t raw = state ? 1 : 0;
  g_prefs.putUChar(relayStateKey(relayIndex), raw);
  g_prefs.putUInt(relayChecksumKey(relayIndex), computeChecksum(&raw, sizeof(raw)));
  Serial.printf("[FLASH] State relay_%u terkomit: %s\n",
                relayIndex + 1,
                state ? "ON" : "OFF");
}

// =============================================================================
// HARDWARE GPIO + DEBOUNCE FLASH WRITE
// =============================================================================
static void applyRelayState(uint8_t relayIndex, bool state) {
  const uint8_t pin = (relayIndex == 0) ? PIN_RELAY_1 : PIN_RELAY_2;
  digitalWrite(pin,
               state ? RELAY_ACTIVE_LEVEL : RELAY_INACTIVE_LEVEL);
  g_relayCurrentState[relayIndex] = state;
}

static void markRelayChangePending(uint8_t relayIndex, bool newState) {
  // Dipanggil oleh NetworkTask saat menerima push dari RTDB ATAU oleh
  // HardwareTask saat schedule lokal memicu perubahan. Setiap perubahan
  // me-reset timer debounce sehingga osilasi cepat (<5 detik) hanya
  // menyentuh RAM, tidak flash.
  if (newState == g_relayCurrentState[relayIndex] &&
      g_relayPendingSinceMs[relayIndex] == 0) {
    return; // tidak ada perubahan, abaikan
  }
  applyRelayState(relayIndex, newState);
  g_relayPendingFlashState[relayIndex] = newState;
  g_relayPendingSinceMs[relayIndex]   = millis();
  if (g_relayPendingSinceMs[relayIndex] == 0) {
    // Edge case: millis() rollover ke 0 setelah ~49 hari. Geser 1ms ke
    // depan agar sentinel "0 = tidak ada pending" tetap valid.
    g_relayPendingSinceMs[relayIndex] = 1;
  }
}

static void processFlashDebounce(uint32_t nowMs) {
  for (uint8_t relayIndex = 0; relayIndex < 2; ++relayIndex) {
    if (g_relayPendingSinceMs[relayIndex] == 0) continue;
    // Aman terhadap rollover: selisih unsigned tetap benar.
    if ((nowMs - g_relayPendingSinceMs[relayIndex]) >= FLASH_WRITE_DEBOUNCE_MS) {
      commitRelayStateToFlash(relayIndex, g_relayPendingFlashState[relayIndex]);
      g_relayPendingSinceMs[relayIndex] = 0;
    }
  }
}

// =============================================================================
// WIFI MANAGEMENT (Core 0)
// =============================================================================
static bool connectWiFiOnce() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  uint32_t start = millis();
  // Polling non-blocking dengan vTaskDelay agar idle task lain tetap jalan.
  while (WiFi.status() != WL_CONNECTED &&
         (millis() - start) < 15000UL) {
    vTaskDelay(pdMS_TO_TICKS(200));
  }
  if (WiFi.status() == WL_CONNECTED) {
    g_wifiEverConnected = true;
    Serial.printf("[WIFI] Terhubung. IP = %s\n",
                  WiFi.localIP().toString().c_str());
    return true;
  }
  Serial.println(F("[WIFI] Gagal connect dalam 15 detik."));
  return false;
}

static void ensureWiFiConnected(uint32_t nowMs) {
  static uint32_t lastAttempt = 0;
  if (WiFi.status() == WL_CONNECTED) return;
  if ((nowMs - lastAttempt) < WIFI_RECONNECT_INTERVAL_MS) return;
  lastAttempt = nowMs;
  Serial.println(F("[WIFI] Reconnect attempt..."));
  WiFi.disconnect();
  connectWiFiOnce();
}

// =============================================================================
// FIREBASE INIT + STREAM
// =============================================================================
static void initFirebase() {
  fbConfig.database_url       = FIREBASE_HOST;
  fbConfig.signer.tokens.legacy_token = FIREBASE_AUTH;
  fbConfig.token_status_callback      = tokenStatusCallback;

  Firebase.reconnectWiFi(true);
  Firebase.RTDB.setReadTimeout(&fbStream, 1000 * 60);
  Firebase.RTDB.setwriteSizeLimit(&fbStream, "tiny");

  Firebase.begin(&fbConfig, &fbAuth);
  Serial.println(F("[FB] Firebase client initialized."));
}

static String composeComponentsPath() {
  String p = RTDB_PATH_DEVICES_ROOT;
  p += g_deviceId;
  p += RTDB_PATH_COMPONENTS_ROOT;
  return p;
}

static String composeRelayStatePath(uint8_t relayIndex) {
  String p = RTDB_PATH_DEVICES_ROOT;
  p += g_deviceId;
  p += (relayIndex == 0) ? RTDB_PATH_RELAY_1_COMPONENT
                          : RTDB_PATH_RELAY_2_COMPONENT;
  return p;
}

static String composeSchedulesPath(uint8_t relayIndex) {
  String p = composeRelayStatePath(relayIndex);
  p += "/";
  p += RTDB_PATH_RELAY_SCHEDULES;
  return p;
}

static String composeMetadataStatusPath() {
  String p = RTDB_PATH_DEVICES_ROOT;
  p += g_deviceId;
  p += RTDB_PATH_METADATA_STATUS;
  return p;
}
static String composeMetadataLastBootPath() {
  String p = RTDB_PATH_DEVICES_ROOT;
  p += g_deviceId;
  p += RTDB_PATH_METADATA_LAST_BOOT;
  return p;
}

static void startRtdbStream() {
  String path = composeComponentsPath();
  if (!Firebase.RTDB.beginStream(&fbStream, path.c_str())) {
    Serial.printf("[FB] beginStream gagal: %s\n", fbStream.errorReason().c_str());
    return;
  }
  Serial.printf("[FB] Stream listener aktif pada %s\n", path.c_str());

  // Kirim booting report (event-driven, bukan periodic heartbeat) sesuai
  // docs/PRD.md bab 5.B - "Event-Driven Reporting".
  Firebase.RTDB.setString(&fbWrite,
                          composeMetadataStatusPath().c_str(),
                          "Online");

  // Timestamp boot dalam format ISO 8601 sederhana (UTC=0 jika NTP belum
  // sync, biar tetap monoton; cloud function dapat menormalisasi).
  char isoBuf[32];
  time_t nowEpoch = time(nullptr);
  if (nowEpoch > 1700000000) {
    struct tm utc;
    gmtime_r(&nowEpoch, &utc);
    strftime(isoBuf, sizeof(isoBuf), "%Y-%m-%dT%H:%M:%SZ", &utc);
  } else {
    snprintf(isoBuf, sizeof(isoBuf), "1970-01-01T00:00:00Z");
  }
  Firebase.RTDB.setString(&fbWrite,
                          composeMetadataLastBootPath().c_str(),
                          isoBuf);

  // onDisconnect handler agar status otomatis flip ke "Offline" saat
  // koneksi hilang (acuan: architecture_flow.md sec.4).
  Firebase.RTDB.setString(&fbWrite,
                          (composeMetadataStatusPath() + "/.onDisconnect").c_str(),
                          "Offline");
}

// Helper: convert FirebaseJsonData to boolean (handle bool + string types)
static bool jsonDataToBool(const FirebaseJsonData& fjd) {
  // 1. Jika terdeteksi sebagai boolean murni dari Firebase Console
  if (fjd.typeNum == FirebaseJson::JSON_BOOL) {
    return fjd.boolValue;
  }
  
  // 2. Jika terdeteksi sebagai string dari fungsi update() web JavaScript
  if (fjd.typeNum == FirebaseJson::JSON_STRING) {
    // KUNCI: Gunakan fjd.stringValue karena fjd.stringData kadang kosong pada jenis payload terkompresi
    String str = fjd.stringValue; 
    str.replace("\"", "");
    str.toLowerCase();
    str.trim(); // Bersihkan sisa spasi atau karakter newline gaib
    
    return (str == "true" || str == "1");
  }
  
  return false;
}

static void handleRtdbStreamData() {
  if (!Firebase.RTDB.readStream(&fbStream)) {
    Serial.printf("[FB] readStream error: %s\n",
                  fbStream.errorReason().c_str());
    return;
  }
  if (fbStream.streamTimeout()) {
    onRtdbStreamTimeout(true);
    return;
  }
  if (!fbStream.streamAvailable()) return;

  String dataPath = fbStream.dataPath();   // contoh: "/" atau "/current_state"
  String dataType = fbStream.dataType();   // "boolean", "json", "array", ...

  // Kasus 1: pertama kali subscribe -> dataPath = "/" dan dataType = "json"
  // berisi seluruh objek komponen relay_1. Parse current_state + schedules.
  if (dataPath == "/") {
    if (dataType == "json") {
      FirebaseJson& json = fbStream.jsonObjectPtr() ?
                           *fbStream.jsonObjectPtr() : *(FirebaseJson*)nullptr;
      if (&json != nullptr) {
        FirebaseJsonData fjd;
        if (json.get(fjd, "relay_1/current_state") && 
            (fjd.typeNum == FirebaseJson::JSON_BOOL || fjd.typeNum == FirebaseJson::JSON_STRING)) {
          markRelayChangePending(0, jsonDataToBool(fjd));
        }
        if (json.get(fjd, "relay_2/current_state") && 
            (fjd.typeNum == FirebaseJson::JSON_BOOL || fjd.typeNum == FirebaseJson::JSON_STRING)) {
          markRelayChangePending(1, jsonDataToBool(fjd));
        }
        if (json.get(fjd, "relay_1/schedules") &&
            (fjd.typeNum == FirebaseJson::JSON_ARRAY ||
             fjd.typeNum == FirebaseJson::JSON_OBJECT)) {
          syncSchedulesFromJson(0, fjd.stringValue);
        }
        if (json.get(fjd, "relay_2/schedules") &&
            (fjd.typeNum == FirebaseJson::JSON_ARRAY ||
             fjd.typeNum == FirebaseJson::JSON_OBJECT)) {
          syncSchedulesFromJson(1, fjd.stringValue);
        }
      }
    }
    return;
  }

  // Kasus 1.5: update() dari web ke node komponen (misal: /relay_1)
  // Payload berupa JSON object: {"current_state": true}
  if ((dataPath == "/relay_1" || dataPath == "/relay_2") && dataType == "json") {
    FirebaseJson& json = fbStream.jsonObjectPtr() ?
                         *fbStream.jsonObjectPtr() : *(FirebaseJson*)nullptr;
    if (&json != nullptr) {
      FirebaseJsonData fjd;
      uint8_t relayIndex = (dataPath == "/relay_1") ? 0 : 1;
      
      if (json.get(fjd, "current_state") && 
          (fjd.typeNum == FirebaseJson::JSON_BOOL || fjd.typeNum == FirebaseJson::JSON_STRING)) {
        markRelayChangePending(relayIndex, jsonDataToBool(fjd));
      }
      
      // Jika ternyata web juga melakukan update ke schedules bersamaan dengan current_state
      if (json.get(fjd, "schedules") &&
          (fjd.typeNum == FirebaseJson::JSON_ARRAY ||
           fjd.typeNum == FirebaseJson::JSON_OBJECT)) {
        syncSchedulesFromJson(relayIndex, fjd.stringValue);
      }
    }
    return;
  }

// Kasus 2: hanya current_state yang berubah secara spesifik
  if ((dataPath == "/relay_1/current_state" || dataPath == "/relay_2/current_state") &&
      (dataType == "boolean" || dataType == "string")) {
    
    uint8_t relayIndex = (dataPath == "/relay_1/current_state") ? 0 : 1;
    bool newState = false;

    if (dataType == "boolean") {
      newState = fbStream.boolData();
    } else {
      String strData = fbStream.stringData();
      strData.replace("\"", "");
      strData.toLowerCase();
      strData.trim();
      newState = (strData == "true" || strData == "1");
    }

    markRelayChangePending(relayIndex, newState);
    return;
  }
  
  // Kasus 3: array schedules dimodifikasi (tambah/edit/hapus dari mobile).
  if (dataPath.startsWith("/relay_1/schedules") || dataPath.startsWith("/relay_2/schedules")) {
    uint8_t relayIndex = dataPath.startsWith("/relay_1/") ? 0 : 1;
    if (Firebase.RTDB.getJSON(&fbWrite, composeSchedulesPath(relayIndex).c_str())) {
      syncSchedulesFromJson(relayIndex, fbWrite.payload());
    }
    return;
  }
}

static void onRtdbStreamTimeout(bool timeout) {
  if (timeout) {
    Serial.println(F("[FB] Stream timeout, akan re-attach otomatis."));
  }
}

// =============================================================================
// SYNC SCHEDULES: RTDB -> Preferences -> Array RAM
// =============================================================================
static void syncSchedulesFromJson(uint8_t relayIndex, const String& jsonPayload) {
  // Gunakan DynamicJsonDocument dengan ukuran yang dibatasi agar tidak
  // meledakkan heap saat payload tidak terduga (acuan: skill.md
  // "String Allocation Guard").
  const size_t kCapacity = JSON_ARRAY_SIZE(MAX_LOCAL_SCHEDULES) +
                           MAX_LOCAL_SCHEDULES * JSON_OBJECT_SIZE(5) +
                           512;
  DynamicJsonDocument doc(kCapacity);
  DeserializationError err = deserializeJson(doc, jsonPayload);
  if (err) {
    Serial.printf("[SYNC] JSON schedules relay_%u invalid: %s\n", relayIndex + 1, err.c_str());
    return;
  }

  // Tangkap mutex untuk hindari race condition dengan HardwareTask iterator.
  if (g_schedulesMutex == nullptr) {
    Serial.println(F("[SYNC] Mutex schedules belum siap, skip sync."));
    return;
  }
  if (xSemaphoreTake(g_schedulesMutex, pdMS_TO_TICKS(200)) != pdTRUE) {
    Serial.println(F("[SYNC] Mutex schedules timeout, skip sync."));
    return;
  }

  g_scheduleCount[relayIndex] = 0;
  JsonArray arr;
  if (doc.is<JsonArray>()) {
    arr = doc.as<JsonArray>();
  } else if (doc.is<JsonObject>()) {
    // Firebase kadang mengirim array bernilai null sebagai object indexed.
    arr = doc.as<JsonObject>().createNestedArray("__compat");
    for (JsonPair kv : doc.as<JsonObject>()) {
      arr.add(kv.value());
    }
  }

  for (JsonObject s : arr) {
    if (g_scheduleCount[relayIndex] >= MAX_LOCAL_SCHEDULES) break;
    LocalSchedule& slot = g_schedules[relayIndex][g_scheduleCount[relayIndex]];
    const char* sid = s["id"] | "";
    strncpy(slot.id, sid, sizeof(slot.id) - 1);
    slot.id[sizeof(slot.id) - 1] = '\0';
    slot.isActive = s["is_active"] | false;

    const char* onStr  = s["on_time"]  | "00:00";
    const char* offStr = s["off_time"] | "00:00";
    int oh = 0, om = 0, fh = 0, fm = 0;
    sscanf(onStr,  "%d:%d", &oh, &om);
    sscanf(offStr, "%d:%d", &fh, &fm);
    slot.onHour   = constrain(oh, 0, 23);
    slot.onMinute = constrain(om, 0, 59);
    slot.offHour  = constrain(fh, 0, 23);
    slot.offMinute= constrain(fm, 0, 59);
    g_scheduleCount[relayIndex]++;
  }

  xSemaphoreGive(g_schedulesMutex);

  persistSchedulesToFlash(relayIndex, jsonPayload);
  Serial.printf("[SYNC] %u jadwal disinkronkan dari RTDB untuk relay_%u.\n", g_scheduleCount[relayIndex], relayIndex + 1);
}

static const char* schedulesJsonKey(uint8_t relayIndex) {
  return relayIndex == 0 ? PREF_KEY_SCH1_JSON : PREF_KEY_SCH2_JSON;
}

static const char* schedulesChecksumKey(uint8_t relayIndex) {
  return relayIndex == 0 ? PREF_KEY_SCH1_CHECKSUM : PREF_KEY_SCH2_CHECKSUM;
}

static void loadSchedulesFromFlash() {
  for (uint8_t relayIndex = 0; relayIndex < 2; ++relayIndex) {
    String cached = g_prefs.getString(schedulesJsonKey(relayIndex), "");
    if (cached.length() == 0) {
      Serial.printf("[FLASH] Cache schedules relay_%u kosong.\n", relayIndex + 1);
      continue;
    }
    uint32_t storedChksum = g_prefs.getUInt(schedulesChecksumKey(relayIndex), 0);
    uint32_t actualChksum = computeChecksum(
        reinterpret_cast<const uint8_t*>(cached.c_str()), cached.length());
    if (storedChksum != actualChksum) {
      Serial.printf("[FLASH] Checksum schedules relay_%u korup. Diabaikan.\n", relayIndex + 1);
      continue;
    }
    syncSchedulesFromJson(relayIndex, cached);
  }
}

static void persistSchedulesToFlash(uint8_t relayIndex, const String& jsonPayload) {
  g_prefs.putString(schedulesJsonKey(relayIndex), jsonPayload);
  uint32_t cs = computeChecksum(
      reinterpret_cast<const uint8_t*>(jsonPayload.c_str()),
      jsonPayload.length());
  g_prefs.putUInt(schedulesChecksumKey(relayIndex), cs);
}

static void enqueueRelayStateWrite(uint8_t relayIndex, bool state) {
  portENTER_CRITICAL(&g_relayPendingMux);
  g_relayPendingRtdbState[relayIndex] = state;
  g_relayPendingRtdbChange[relayIndex] = true;
  portEXIT_CRITICAL(&g_relayPendingMux);
}

static bool consumePendingRelayWrite(uint8_t relayIndex, bool& outState) {
  bool pending = false;
  portENTER_CRITICAL(&g_relayPendingMux);
  if (g_relayPendingRtdbChange[relayIndex]) {
    outState = g_relayPendingRtdbState[relayIndex];
    g_relayPendingRtdbChange[relayIndex] = false;
    pending = true;
  }
  portEXIT_CRITICAL(&g_relayPendingMux);
  return pending;
}

static void processPendingRelayWrite() {
  if (WiFi.status() != WL_CONNECTED || !Firebase.ready()) {
    return;
  }
  for (uint8_t relayIndex = 0; relayIndex < 2; ++relayIndex) {
    bool nextState = false;
    if (!consumePendingRelayWrite(relayIndex, nextState)) {
      continue;
    }

    const String path = composeRelayStatePath(relayIndex) + "/" + RTDB_PATH_RELAY_STATE_KEY;
    if (!Firebase.RTDB.setBool(&fbWrite, path.c_str(), nextState)) {
      Serial.printf("[FB] Pending relay_%u write gagal: %s\n",
                    relayIndex + 1,
                    fbWrite.errorReason().c_str());
      enqueueRelayStateWrite(relayIndex, nextState);
      continue;
    }
    Serial.printf("[FB] Relay_%u schedule push: %s -> RTDB\n",
                  relayIndex + 1,
                  nextState ? "ON" : "OFF");
  }
}

// =============================================================================
// SCHEDULE EVALUATOR (Core 1)
// =============================================================================
static void evaluateSchedulesNow(const struct tm& nowLocal) {
  // Encode HH*60+MM menjadi satu int unik per menit dalam sehari.
  int minuteKey = nowLocal.tm_hour * 60 + nowLocal.tm_min;
  if (minuteKey == g_lastEvaluatedMinuteKey) {
    return; // sudah dievaluasi pada menit yang sama
  }
  g_lastEvaluatedMinuteKey = minuteKey;

  if (xSemaphoreTake(g_schedulesMutex, pdMS_TO_TICKS(50)) != pdTRUE) {
    return; // jangan blokir hardware task lama
  }

  for (uint8_t relayIndex = 0; relayIndex < 2; ++relayIndex) {
    bool fired = false;
    bool target = g_relayCurrentState[relayIndex];
    for (uint8_t i = 0; i < g_scheduleCount[relayIndex]; ++i) {
      const LocalSchedule& s = g_schedules[relayIndex][i];
      if (!s.isActive) continue;
      int onKey  = s.onHour  * 60 + s.onMinute;
      int offKey = s.offHour * 60 + s.offMinute;
      if (minuteKey == onKey) {
        target = true;
        fired  = true;
        break;
      }
      if (minuteKey == offKey) {
        target = false;
        fired  = true;
        break;
      }
    }

    if (fired && target != g_relayCurrentState[relayIndex]) {
      Serial.printf("[SCHED] Eksekusi alarm -> relay_%u = %s\n",
                    relayIndex + 1, target ? "ON" : "OFF");
      markRelayChangePending(relayIndex, target);
      // Jangan tulis RTDB langsung dari Core 1. Queue ke NetworkTask agar
      // library Firebase hanya diakses dari satu task saja.
      enqueueRelayStateWrite(relayIndex, target);
    }
  }
  xSemaphoreGive(g_schedulesMutex);
}

// =============================================================================
// TASK 1 (CORE 0) - NETWORK
// =============================================================================
static void networkTaskEntry(void* /*arg*/) {
  Serial.println(F("[TASK0] NetworkTask started on core 0."));

  // Coba connect Wi-Fi pertama kali (boleh blokir task ini, Core 1 tetap jalan).
  connectWiFiOnce();

  // Init NTP setelah Wi-Fi ON. Ini async di balik layar; cek hasil di Core 1.
  configTime(NTP_TIMEZONE_OFFSET_SEC, NTP_DAYLIGHT_OFFSET_SEC,
             NTP_SERVER_PRIMARY, NTP_SERVER_SECONDARY);

  initFirebase();

  bool streamStarted = false;

  for (;;) {
    uint32_t nowMs = millis();
    ensureWiFiConnected(nowMs);

    if (WiFi.status() == WL_CONNECTED) {
      if (!streamStarted && Firebase.ready()) {
        startRtdbStream();
        streamStarted = true;
      } else if (streamStarted) {
        handleRtdbStreamData();
      }
      processPendingRelayWrite();
    } else {
      streamStarted = false;
    }

    // Yield 50 ms supaya Firebase RTDB lib bisa proses internal queue
    // dan idle task watchdog tidak terpicu.
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

// =============================================================================
// TASK 2 (CORE 1) - HARDWARE
// =============================================================================
static void hardwareTaskEntry(void* /*arg*/) {
  Serial.println(F("[TASK1] HardwareTask started on core 1."));
  uint32_t lastScheduleEval = 0;
  uint32_t ntpWaitStart     = millis();

  for (;;) {
    uint32_t nowMs = millis();

    // 1) Pantau status sinkronisasi NTP (one-shot).
    if (!g_ntpSynced) {
      time_t epoch = time(nullptr);
      if (epoch > 1700000000) {  // > 2023-11 ~ tanda NTP sukses
        g_ntpSynced = true;
        Serial.println(F("[TIME] NTP tersinkron."));
      } else if ((nowMs - ntpWaitStart) > NTP_INITIAL_SYNC_TIMEOUT_MS &&
                 !g_wifiEverConnected) {
        // Suspend otomatisasi waktu karena NTP gagal & belum pernah online
        // (acuan: architecture_flow.md sec.4).
        Serial.println(F("[TIME] NTP timeout & offline -> otomatisasi waktu suspended."));
      }
    }

    // 2) Debounce flash write 5 detik.
    processFlashDebounce(nowMs);

    // 3) Evaluasi schedules tiap 1 detik (hemat siklus CPU).
    if (g_ntpSynced && (nowMs - lastScheduleEval) >= SCHEDULE_EVAL_INTERVAL_MS) {
      lastScheduleEval = nowMs;
      time_t epoch = time(nullptr);
      struct tm local;
      localtime_r(&epoch, &local);
      evaluateSchedulesNow(local);
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }
}
