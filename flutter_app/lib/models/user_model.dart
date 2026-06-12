// File: flutter_app/lib/models/user_model.dart
// =============================================================================
// Model profil pengguna SmartHome Core. Skema acuan:
// docs/mock_database_seed.json -> users.<uid>.
//
// Penting untuk RBAC UI Masking (docs/wireframe_component.md bab 5.B):
// ViewModel akan membaca [role] & [status] untuk memutuskan apakah
// menyembunyikan tombol "+ Tambah Jadwal", User Control Panel, dsb.
// =============================================================================

import 'package:flutter/foundation.dart';

enum UserRole { owner, member, unknown }

enum UserStatus { approved, pending, unknown }

@immutable
class UserModel {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final UserStatus status;
  final DateTime? registeredAt;
  final List<String> associatedDevices;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.registeredAt,
    required this.associatedDevices,
  });

  /// Sentinel untuk state "belum login / data belum dimuat". Hindari
  /// nullable UserModel di seluruh ViewModel agar code branching lebih
  /// sederhana dan tidak boilerplate `?.`.
  static const UserModel anonymous = UserModel(
    uid: '',
    name: '',
    email: '',
    role: UserRole.unknown,
    status: UserStatus.unknown,
    registeredAt: null,
    associatedDevices: <String>[],
  );

  bool get isOwner => role == UserRole.owner && status == UserStatus.approved;
  bool get isApproved => status == UserStatus.approved;
  bool get isAnonymous => uid.isEmpty;

  factory UserModel.fromMap(String uid, Map<dynamic, dynamic>? raw) {
    final map = raw ?? const {};
    final assocRaw = map['associated_devices'];
    final List<String> assoc = <String>[];
    if (assocRaw is List) {
      for (final v in assocRaw) {
        if (v is String) assoc.add(v);
      }
    } else if (assocRaw is Map) {
      assocRaw.forEach((_, v) {
        if (v is String) assoc.add(v);
      });
    }

    return UserModel(
      uid: uid,
      name: (map['name'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      role: _parseRole(map['role'] as String?),
      status: _parseStatus(map['status'] as String?),
      registeredAt: _parseIso(map['registered_at'] as String?),
      associatedDevices: List.unmodifiable(assoc),
    );
  }

  static UserRole _parseRole(String? raw) {
    switch (raw) {
      case 'Owner':
        return UserRole.owner;
      case 'Member':
        return UserRole.member;
      default:
        return UserRole.unknown;
    }
  }

  static UserStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'Approved':
        return UserStatus.approved;
      case 'Pending':
        return UserStatus.pending;
      default:
        return UserStatus.unknown;
    }
  }

  static DateTime? _parseIso(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
