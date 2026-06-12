// File: flutter_app/lib/models/device_model.dart
// =============================================================================
// Model perangkat ESP32 (satu hub). Berisi metadata + map komponen.
// Skema acuan: docs/mock_database_seed.json -> devices.<id>.
// =============================================================================

import 'package:flutter/foundation.dart';

import 'component_model.dart';

/// Status koneksi perangkat sebagaimana dilaporkan oleh onDisconnect RTDB
/// (acuan: docs/PRD.md bab 5.B "Passive Offline Detection").
enum DeviceStatus { online, offline, unknown }

@immutable
class DeviceModel {
  /// MAC-based device id, sekaligus key di node /devices/.
  final String id;

  /// Nama yang diatur owner via aplikasi (mis. "Hub Utama Ruang Tengah").
  final String name;

  final DeviceStatus status;
  final String ownerUid;
  final String hardwareVersion;
  final DateTime? lastBootReport;

  /// Komponen anak diurutkan menurut urutan key untuk stabilitas UI.
  final List<ComponentModel> components;

  const DeviceModel({
    required this.id,
    required this.name,
    required this.status,
    required this.ownerUid,
    required this.hardwareVersion,
    required this.lastBootReport,
    required this.components,
  });

  /// Parser yang menerima keseluruhan node /devices/<id>.
  factory DeviceModel.fromMap(String id, Map<dynamic, dynamic>? raw) {
    final map = raw ?? const {};
    final meta = (map['metadata'] as Map?) ?? const {};
    final compsRaw = (map['components'] as Map?) ?? const {};

    final List<ComponentModel> comps = <ComponentModel>[];
    compsRaw.forEach((key, value) {
      if (value is Map) {
        comps.add(ComponentModel.fromMap(key.toString(), value));
      }
    });
    // Urut: OUTPUT lebih dulu (zona atas dashboard), lalu INPUT.
    comps.sort((a, b) {
      if (a.isOutput && !b.isOutput) return -1;
      if (!a.isOutput && b.isOutput) return 1;
      return a.id.compareTo(b.id);
    });

    return DeviceModel(
      id: id,
      name: (meta['name'] as String?) ?? 'Perangkat Tanpa Nama',
      status: _parseStatus(meta['status'] as String?),
      ownerUid: (meta['owner_uid'] as String?) ?? '',
      hardwareVersion: (meta['hardware_version'] as String?) ?? 'unknown',
      lastBootReport: _parseIso(meta['last_boot_report'] as String?),
      components: List.unmodifiable(comps),
    );
  }

  /// Flag konvensi untuk Visual Offline Masking (docs/wireframe_component.md
  /// bab 5.A): bila true, UI wajib membungkus Card dengan Opacity 0.5 dan
  /// mematikan semua interaksi.
  bool get isOffline => status != DeviceStatus.online;

  static DeviceStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'Online':
        return DeviceStatus.online;
      case 'Offline':
        return DeviceStatus.offline;
      default:
        return DeviceStatus.unknown;
    }
  }

  static DateTime? _parseIso(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
