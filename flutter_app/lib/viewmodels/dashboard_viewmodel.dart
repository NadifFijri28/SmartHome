// File: flutter_app/lib/viewmodels/dashboard_viewmodel.dart
// =============================================================================
// SmartHome Core - Dashboard ViewModel (Fase 1 MVP)
// =============================================================================
// Lapisan reactive state-holder antara Firebase Realtime Database dan widget
// DashboardPage. Tugas:
//
//   1. Subscribe stream RTDB pada /devices/<deviceId> untuk perangkat
//      pertama Fase 1 (ESP32_MAC_A1B2C3D4E5F6) dan stream /users/<uid>
//      untuk profil RBAC (acuan: docs/wireframe_component.md bab 5.B).
//   2. Expose state melalui ValueNotifier supaya widget cukup memakai
//      ValueListenableBuilder atau StreamBuilder pada `streamState`.
//   3. Menyediakan action terenkapsulasi: toggleRelay, toggleScheduleActive,
//      upsertSchedule, deleteSchedule. Tiap action divalidasi via getter
//      [canWriteRelay] yang juga memantulkan aturan RBAC + Offline.
//   4. Dispose seluruh StreamSubscription pada [dispose] - mitigasi
//      memory leak (acuan: docs/skill.md bab 3 - 🔴 Flutter rule #2).
//
// Catatan implementasi:
//   - Tidak ada UI di sini. ViewModel ini agnostik widget.
//   - Plugin Firebase yang dipakai: firebase_database ^11.x, firebase_auth ^5.x.
//     Lihat pubspec.yaml di root flutter_app/.
// =============================================================================

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/component_model.dart';
import '../models/device_model.dart';
import '../models/schedule_model.dart';
import '../models/user_model.dart';

/// Snapshot komposit yang dikonsumsi UI lewat satu titik tunggal.
@immutable
class DashboardState {
  final DeviceModel? device;
  final UserModel user;
  final bool isLoading;
  final String? errorMessage;

  const DashboardState({
    required this.device,
    required this.user,
    required this.isLoading,
    required this.errorMessage,
  });

  factory DashboardState.initial() => const DashboardState(
        device: null,
        user: UserModel.anonymous,
        isLoading: true,
        errorMessage: null,
      );

  DashboardState copyWith({
    DeviceModel? device,
    UserModel? user,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DashboardState(
      device: device ?? this.device,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required this.deviceId,
    required this.currentUserUid,
    FirebaseDatabase? database,
  }) : _database = database ?? FirebaseDatabase.instance;

  /// Device yang dipantau pada Fase 1. Untuk fase multi-device, controller
  /// luar dapat mem-recreate ViewModel ini dengan deviceId berbeda.
  final String deviceId;

  /// UID Firebase Auth dari user yang sedang login. Anonymous = ''.
  final String currentUserUid;

  final FirebaseDatabase _database;

  // --- State publik -------------------------------------------------------
  final ValueNotifier<DashboardState> state =
      ValueNotifier<DashboardState>(DashboardState.initial());

  // --- Subscription internal ---------------------------------------------
  StreamSubscription<DatabaseEvent>? _deviceSub;
  StreamSubscription<DatabaseEvent>? _userSub;

  // --- Lifecycle ----------------------------------------------------------

  /// Mulai berlangganan ke RTDB. Aman dipanggil banyak kali (idempoten).
  void attach() {
    if (_deviceSub != null || _userSub != null) return;
    _bindDeviceStream();
    _bindUserStream();
  }

  void _bindDeviceStream() {
    final ref = _database.ref('devices/$deviceId');
    _deviceSub = ref.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        if (raw == null) {
          // Node belum ada -> tampilkan empty state, jangan crash.
          state.value = state.value.copyWith(
            device: null,
            isLoading: false,
            clearError: true,
          );
          return;
        }
        if (raw is! Map) {
          state.value = state.value.copyWith(
            isLoading: false,
            errorMessage: 'Format payload device tidak dikenali.',
          );
          return;
        }
        try {
          final device = DeviceModel.fromMap(deviceId, raw);
          state.value = state.value.copyWith(
            device: device,
            isLoading: false,
            clearError: true,
          );
        } catch (e, st) {
          // Tangkap exception parser supaya UI tidak blank screen.
          debugPrint('[Dashboard] Parse device gagal: $e\n$st');
          state.value = state.value.copyWith(
            isLoading: false,
            errorMessage: 'Gagal memetakan data perangkat.',
          );
        }
      },
      onError: (Object err) {
        debugPrint('[Dashboard] device stream error: $err');
        state.value = state.value.copyWith(
          isLoading: false,
          errorMessage: 'Koneksi ke RTDB perangkat terganggu.',
        );
      },
    );
  }

  void _bindUserStream() {
    if (currentUserUid.isEmpty) {
      // User anonymous, tidak ada profil yang perlu disinkronkan.
      state.value = state.value.copyWith(user: UserModel.anonymous);
      return;
    }
    final ref = _database.ref('users/$currentUserUid');
    _userSub = ref.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        if (raw is Map) {
          final user = UserModel.fromMap(currentUserUid, raw);
          state.value = state.value.copyWith(user: user);
        } else {
          state.value = state.value.copyWith(user: UserModel.anonymous);
        }
      },
      onError: (Object err) {
        debugPrint('[Dashboard] user stream error: $err');
        // Tetap pertahankan device stream meskipun profil gagal load,
        // user akan terlihat sebagai non-owner (paling aman).
        state.value = state.value.copyWith(user: UserModel.anonymous);
      },
    );
  }

  @override
  void dispose() {
    // WAJIB cancel kedua subscription supaya stream tidak menggantung
    // dan FirebaseDatabase tidak menahan callback ke ChangeNotifier mati.
    _deviceSub?.cancel();
    _userSub?.cancel();
    _deviceSub = null;
    _userSub = null;
    state.dispose();
    super.dispose();
  }

  // --- Getter konvensi RBAC + Offline ------------------------------------

  bool get isDeviceOffline => state.value.device?.isOffline ?? true;

  bool get isOwner => state.value.user.isOwner;

  /// Aturan UI: tombol "+ Tambah Jadwal" hanya muncul untuk Owner
  /// (acuan: docs/wireframe_component.md bab 5.B).
  bool get canManageSchedules => isOwner && !isDeviceOffline;

  /// Aturan UI: User Control Panel hanya muncul untuk Owner.
  bool get canManageUsers => isOwner;

  /// Saklar manual aktif jika user approved dan device online. Member
  /// approved tetap boleh menekan toggle; non-approved diblokir di sisi
  /// security rules (defense-in-depth: UI nonaktif + server 403).
  bool get canWriteRelay =>
      !isDeviceOffline && state.value.user.isApproved;

  // --- Helper akses komponen relay_1 Fase 1 ------------------------------

  /// Komponen relay tunggal pada Fase 1 ("relay_1"). Mengembalikan null
  /// bila belum ada (mis. saat first sync).
  ComponentModel? get primaryRelay {
    final device = state.value.device;
    if (device == null) return null;
    for (final c in device.components) {
      if (c.id == 'relay_1') return c;
    }
    return null;
  }

  // --- Actions ------------------------------------------------------------

  /// Toggle status relay manual dari UI Switch. Mengembalikan future yang
  /// resolve ketika RTDB mengkonfirmasi write atau melempar error.
  Future<void> toggleRelay(String componentId, bool nextState) async {
    if (!canWriteRelay) {
      state.value = state.value.copyWith(
        errorMessage: 'Perangkat offline atau akun belum disetujui.',
      );
      return;
    }
    try {
      await _database
          .ref('devices/$deviceId/components/$componentId/current_state')
          .set(nextState);
    } on FirebaseException catch (e) {
      // Security rules menolak (mis. user dihapus race condition) -> 403.
      // Lihat docs/PRD.md bab 6.A "Mitigasi Race Condition".
      debugPrint('[Dashboard] toggleRelay ditolak: ${e.code} ${e.message}');
      state.value = state.value.copyWith(
        errorMessage: 'Permintaan ditolak server (RBAC).',
      );
    }
  }

  /// Ubah aktivasi salah satu schedule.
  Future<void> toggleScheduleActive({
    required String componentId,
    required String scheduleId,
    required bool nextActive,
  }) async {
    if (!canManageSchedules) return;
    final device = state.value.device;
    if (device == null) return;
    final comp = device.components.firstWhere(
      (c) => c.id == componentId,
      orElse: () => ComponentModel.fromMap(componentId, const {}),
    );
    final updated = comp.schedules.map((s) {
      if (s.id != scheduleId) return s;
      return s.copyWith(isActive: nextActive);
    }).toList();
    await _writeSchedules(componentId, updated);
  }

  /// Tambah atau perbarui satu jadwal. Jika [schedule.id] sudah ada,
  /// menimpa; jika belum, append.
  Future<void> upsertSchedule({
    required String componentId,
    required ScheduleModel schedule,
  }) async {
    if (!canManageSchedules) return;
    final device = state.value.device;
    if (device == null) return;
    final comp = device.components.firstWhere(
      (c) => c.id == componentId,
      orElse: () => ComponentModel.fromMap(componentId, const {}),
    );

    final List<ScheduleModel> next = List<ScheduleModel>.from(comp.schedules);
    final idx = next.indexWhere((s) => s.id == schedule.id);
    if (idx >= 0) {
      next[idx] = schedule;
    } else {
      next.add(schedule);
    }
    await _writeSchedules(componentId, next);
  }

  /// Hapus jadwal berdasarkan id.
  Future<void> deleteSchedule({
    required String componentId,
    required String scheduleId,
  }) async {
    if (!canManageSchedules) return;
    final device = state.value.device;
    if (device == null) return;
    final comp = device.components.firstWhere(
      (c) => c.id == componentId,
      orElse: () => ComponentModel.fromMap(componentId, const {}),
    );
    final next = comp.schedules.where((s) => s.id != scheduleId).toList();
    await _writeSchedules(componentId, next);
  }

  /// Bersihkan pesan error sebelumnya (dipanggil setelah SnackBar tampil).
  void acknowledgeError() {
    if (state.value.errorMessage == null) return;
    state.value = state.value.copyWith(clearError: true);
  }

  // --- Internal helper write schedules -----------------------------------

  Future<void> _writeSchedules(
    String componentId,
    List<ScheduleModel> schedules,
  ) async {
    // RTDB menyimpan schedules sebagai array indexed. Map<int,Map>
    // diserialize sebagai List oleh SDK saat key 0..n-1 berurutan,
    // jadi cukup kirim List<Map>.
    final payload = schedules.map((s) => s.toMap()).toList();
    try {
      await _database
          .ref('devices/$deviceId/components/$componentId/schedules')
          .set(payload);
    } on FirebaseException catch (e) {
      debugPrint('[Dashboard] _writeSchedules ditolak: ${e.code} ${e.message}');
      state.value = state.value.copyWith(
        errorMessage: 'Gagal menyimpan jadwal: ${e.message ?? e.code}',
      );
    }
  }
}
