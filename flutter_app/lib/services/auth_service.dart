// File: flutter_app/lib/services/auth_service.dart
// =============================================================================
// SmartHome Core - AuthService
// =============================================================================
// Wrapper tipis di atas FirebaseAuth + FirebaseDatabase yang menyatukan tiga
// concern auth menjadi satu kelas dapat diuji:
//
//   1. signInWithEmail(...)  - login email/password.
//   2. registerNewUser(...)  - createUser di Firebase Auth lalu MENULIS
//                              node /users/<uid> dengan role=Member,
//                              status=Pending (acuan: docs/PRD.md bab 4.B
//                              "Whitelisting & Approval System").
//   3. signOut()             - akhiri sesi.
//
// AuthService tidak menyimpan state lokal selain instance Firebase; state
// dipancarkan via [authStateChanges] yang dilanggan AuthViewModel.
//
// Exception domain dikonversi ke [AuthFailure] dengan pesan Bahasa Indonesia
// agar UI tidak perlu menerjemahkan kode error Firebase secara ad-hoc.
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Hasil terstruktur untuk semua aksi auth - lebih predictable ketimbang
/// melempar exception lintas-lapisan.
@immutable
class AuthFailure implements Exception {
  final String code;
  final String message;
  const AuthFailure(this.code, this.message);

  @override
  String toString() => 'AuthFailure($code): $message';
}

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseDatabase? database,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  /// Stream perubahan status login. AuthViewModel mem-pipe ini ke
  /// AuthStage. Emit null saat signed-out.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Login akun yang sudah ada. Throws [AuthFailure].
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw const AuthFailure('null-user', 'Gagal login: user tidak dikenal.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(e.code, _mapAuthErrorMessage(e));
    }
  }

  /// Registrasi user baru. Aksi terdiri dari DUA tahap:
  ///   (a) createUserWithEmailAndPassword pada Firebase Auth.
  ///   (b) Tulis profil ke RTDB /users/<uid> dengan status Pending.
  ///
  /// Jika tahap (b) gagal, sesi tetap signed-in di Auth namun profil di
  /// RTDB belum ada. AuthGate akan menahan user di PendingApprovalPage
  /// (atau LoginPage jika profile betul-betul kosong). Kita TIDAK
  /// melakukan rollback (delete user) karena bisa memicu race condition.
  Future<User> registerNewUser({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw const AuthFailure('null-user', 'Gagal membuat akun.');
      }

      // Tulis profil dasar. Rules memvalidasi role=Member dan status=Pending
      // pada penulisan pertama, jadi tidak ada celah self-promote.
      await _database.ref('users/${user.uid}').set({
        'name': name.trim(),
        'email': email.trim(),
        'role': 'Member',
        'status': 'Pending',
        'registered_at': DateTime.now().toUtc().toIso8601String(),
        // associated_devices sengaja dibiarkan kosong - Owner yang
        // memutuskan device mana yang dapat diakses lewat Cloud Functions
        // di Fase 2. Untuk Fase 1, security rules tidak mengandalkan
        // field ini (cek owner_uid saja).
        'associated_devices': <String>[],
      });

      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(e.code, _mapAuthErrorMessage(e));
    } on FirebaseException catch (e) {
      // RTDB tolak write profil (mis. rules belum dideploy). Beritahukan
      // ke UI namun jangan rollback akun Auth.
      throw AuthFailure(
        e.code,
        'Akun dibuat, namun profil gagal disimpan ke database: '
        '${e.message ?? e.code}. Hubungi Owner untuk verifikasi manual.',
      );
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // Pesan error ramah-pengguna
  // ---------------------------------------------------------------------------
  String _mapAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Format email tidak valid.';
      case 'user-disabled':
        return 'Akun ini dinonaktifkan oleh Owner.';
      case 'user-not-found':
        return 'Email belum terdaftar.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email atau kata sandi salah.';
      case 'email-already-in-use':
        return 'Email sudah terdaftar. Silakan login.';
      case 'weak-password':
        return 'Kata sandi terlalu lemah (minimal 6 karakter).';
      case 'network-request-failed':
        return 'Tidak ada koneksi internet.';
      default:
        return e.message ?? 'Terjadi kesalahan autentikasi (${e.code}).';
    }
  }
}
