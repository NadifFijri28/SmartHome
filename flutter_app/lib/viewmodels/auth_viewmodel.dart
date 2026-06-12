// File: flutter_app/lib/viewmodels/auth_viewmodel.dart
// =============================================================================
// SmartHome Core - AuthViewModel
// =============================================================================
// Menggabungkan dua sumber data menjadi satu enum AuthStage yang dapat
// dikonsumsi AuthGate dengan satu ValueListenableBuilder:
//
//   Stream Firebase Auth (User? signed-in/out)
//                +
//   Stream RTDB /users/<uid> (profil + role + status)
//   ────────────────────────────────────────────────
//   = AuthStage (unknown / signedOut / pending / approved / owner)
//
// Memastikan kedua subscription di-cancel pada [dispose] (mitigasi memory
// leak - docs/skill.md bab 3 - 🔴 Flutter #2).
//
// CATATAN: Real-time Kick Mechanism (docs/PRD.md bab 4.B):
// Bila Owner menghapus node /users/<uid>, stream profil emit value null
// -> AuthStage.signedOut -> AuthGate otomatis menendang user ke
// LoginPage. Logout Auth dijalankan paralel agar token tidak menyangkut.
// =============================================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';

/// Klasifikasi state auth untuk routing AuthGate.
enum AuthStage {
  /// Belum tahu - app baru dimulai, stream pertama belum emit.
  unknown,

  /// Tidak ada user yang login.
  signedOut,

  /// Login namun profil RTDB belum di-Approve oleh Owner. Atau profil
  /// hilang (dihapus Owner = real-time kick).
  pending,

  /// Login + profil Approved. Member biasa.
  approved,

  /// Login + Owner sah. Mendapat akses ke User Control Panel + tombol
  /// "+ Tambah Jadwal".
  owner,
}

@immutable
class AuthState {
  final AuthStage stage;
  final UserModel profile;
  final String? errorMessage;

  const AuthState({
    required this.stage,
    required this.profile,
    required this.errorMessage,
  });

  factory AuthState.initial() => const AuthState(
        stage: AuthStage.unknown,
        profile: UserModel.anonymous,
        errorMessage: null,
      );

  AuthState copyWith({
    AuthStage? stage,
    UserModel? profile,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      stage: stage ?? this.stage,
      profile: profile ?? this.profile,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({
    required this.authService,
    FirebaseDatabase? database,
  }) : _database = database ?? FirebaseDatabase.instance;

  final AuthService authService;
  final FirebaseDatabase _database;

  final ValueNotifier<AuthState> state =
      ValueNotifier<AuthState>(AuthState.initial());

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DatabaseEvent>? _profileSub;

  /// Mulai mendengarkan kedua stream. Idempoten.
  void attach() {
    if (_authSub != null) return;
    _authSub = authService.authStateChanges.listen(
      _onAuthChanged,
      onError: (Object err) {
        debugPrint('[Auth] authStateChanges error: $err');
        state.value = state.value.copyWith(
          stage: AuthStage.signedOut,
          profile: UserModel.anonymous,
          errorMessage: 'Stream autentikasi terganggu.',
        );
      },
    );
  }

  void _onAuthChanged(User? user) {
    // Saat user berubah, batalkan listener profil lama agar tidak ada
    // sisa subscription menggantung.
    _profileSub?.cancel();
    _profileSub = null;

    if (user == null) {
      state.value = state.value.copyWith(
        stage: AuthStage.signedOut,
        profile: UserModel.anonymous,
        clearError: true,
      );
      return;
    }

    // Sementara profil belum di-fetch, tahan di unknown supaya UI tampil
    // loading bukan kebablasan ke LoginPage.
    state.value = state.value.copyWith(
      stage: AuthStage.unknown,
      clearError: true,
    );

    final ref = _database.ref('users/${user.uid}');
    _profileSub = ref.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        if (raw == null) {
          // Profil tidak ada -> kemungkinan: (a) baru saja didaftarkan
          // namun write masih in-flight, atau (b) di-kick oleh Owner
          // (real-time kick - PRD bab 4.B). Treat sebagai Pending dengan
          // pesan agar UI bisa redirect logout.
          state.value = state.value.copyWith(
            stage: AuthStage.pending,
            profile: UserModel.anonymous,
          );
          return;
        }
        if (raw is! Map) {
          state.value = state.value.copyWith(
            stage: AuthStage.pending,
            errorMessage: 'Format profil tidak dikenali.',
          );
          return;
        }
        final profile = UserModel.fromMap(user.uid, raw);
        state.value = state.value.copyWith(
          profile: profile,
          stage: _stageFromProfile(profile),
          clearError: true,
        );
      },
      onError: (Object err) {
        debugPrint('[Auth] profile stream error: $err');
        state.value = state.value.copyWith(
          stage: AuthStage.pending,
          errorMessage: 'Gagal memuat profil pengguna.',
        );
      },
    );
  }

  AuthStage _stageFromProfile(UserModel profile) {
    if (profile.isOwner) return AuthStage.owner;
    if (profile.isApproved) return AuthStage.approved;
    return AuthStage.pending;
  }

  // ---------------------------------------------------------------------------
  // ACTIONS - dipanggil oleh LoginPage / PendingApprovalPage
  // ---------------------------------------------------------------------------

  Future<void> signIn(String email, String password) async {
    try {
      await authService.signInWithEmail(email: email, password: password);
      // _onAuthChanged akan dipicu otomatis oleh authStateChanges stream.
    } on AuthFailure catch (e) {
      state.value = state.value.copyWith(errorMessage: e.message);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      await authService.registerNewUser(
        name: name,
        email: email,
        password: password,
      );
    } on AuthFailure catch (e) {
      state.value = state.value.copyWith(errorMessage: e.message);
    }
  }

  Future<void> signOut() async {
    await authService.signOut();
  }

  void acknowledgeError() {
    if (state.value.errorMessage == null) return;
    state.value = state.value.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    _authSub = null;
    _profileSub = null;
    state.dispose();
    super.dispose();
  }
}
