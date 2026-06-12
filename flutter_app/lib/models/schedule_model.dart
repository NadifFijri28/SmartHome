// File: flutter_app/lib/models/schedule_model.dart
// =============================================================================
// Model satu entri jadwal alarm waktu pada relay output.
// Skema acuan: docs/mock_database_seed.json -> components.relay_1.schedules[].
//
// Mengikuti aturan Strict Null Safety (docs/skill.md bab 3 - 🔴 Flutter):
// setiap field punya default fallback agar payload RTDB yang tidak lengkap
// tidak melumpuhkan UI.
// =============================================================================

import 'package:flutter/foundation.dart';

@immutable
class ScheduleModel {
  /// ID unik jadwal di RTDB (mis. "sched_01"). Wajib stabil agar update
  /// per-jadwal dapat menulis ke node spesifik tanpa menyentuh array
  /// secara keseluruhan.
  final String id;

  /// Nama jadwal yang ditampilkan sebagai subtitle ListTile (mis.
  /// "Otomatisasi Malam Hari").
  final String label;

  /// Toggle aktif/tidak. Saat false, evaluator schedule di firmware
  /// akan skip entri ini meski waktunya cocok.
  final bool isActive;

  /// Waktu ON dalam format "HH:mm" 24 jam.
  final String onTime;

  /// Waktu OFF dalam format "HH:mm" 24 jam.
  final String offTime;

  const ScheduleModel({
    required this.id,
    required this.label,
    required this.isActive,
    required this.onTime,
    required this.offTime,
  });

  /// Parser yang toleran terhadap payload null / partial yang sering
  /// terjadi saat node RTDB baru pertama kali dibuat.
  factory ScheduleModel.fromMap(String id, Map<dynamic, dynamic>? raw) {
    final map = raw ?? const {};
    return ScheduleModel(
      id: (map['id'] as String?) ?? id,
      label: (map['label'] as String?) ?? 'Tanpa Nama',
      isActive: (map['is_active'] as bool?) ?? false,
      onTime: (map['on_time'] as String?) ?? '00:00',
      offTime: (map['off_time'] as String?) ?? '00:00',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'is_active': isActive,
        'on_time': onTime,
        'off_time': offTime,
      };

  ScheduleModel copyWith({
    String? id,
    String? label,
    bool? isActive,
    String? onTime,
    String? offTime,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      label: label ?? this.label,
      isActive: isActive ?? this.isActive,
      onTime: onTime ?? this.onTime,
      offTime: offTime ?? this.offTime,
    );
  }
}
