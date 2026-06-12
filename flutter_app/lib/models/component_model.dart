// File: flutter_app/lib/models/component_model.dart
// =============================================================================
// Model komponen fisik di bawah satu device (relay, sensor, dll).
// Skema acuan: docs/mock_database_seed.json -> devices.<id>.components.
//
// Mendukung dua varian (OUTPUT/SWITCH dan INPUT/GAUGE_TEXT) supaya UI dapat
// melakukan "Agnostic UI Rendering" (docs/wireframe_component.md bab 3)
// menggunakan satu ListView.builder tunggal.
// =============================================================================

import 'package:flutter/foundation.dart';

import 'schedule_model.dart';

enum ComponentType { output, input, unknown }

enum ComponentUiElement { toggleSwitch, gaugeText, unknown }

@immutable
class ComponentModel {
  /// Key node di RTDB (mis. "relay_1", "sensor_suhu_1"). Bukan label UI.
  final String id;

  /// OUTPUT (relay) atau INPUT (sensor) - menentukan zona di dashboard.
  final ComponentType type;

  /// SWITCH atau GAUGE_TEXT - menentukan widget yang dirender.
  final ComponentUiElement uiElement;

  /// Label human-readable yang ditampilkan pada Card.
  final String label;

  /// Status saklar relay (hanya bermakna untuk OUTPUT).
  final bool currentState;

  /// Nilai pembacaan sensor (hanya bermakna untuk INPUT).
  final double currentValue;

  /// Jenis otomatisasi (TIME_BASED / THRESHOLD_BASED / NONE).
  final String automationType;

  /// Daftar jadwal alarm untuk OUTPUT (kosong untuk INPUT).
  final List<ScheduleModel> schedules;

  const ComponentModel({
    required this.id,
    required this.type,
    required this.uiElement,
    required this.label,
    required this.currentState,
    required this.currentValue,
    required this.automationType,
    required this.schedules,
  });

  /// Parser robust untuk struktur RTDB.
  factory ComponentModel.fromMap(String id, Map<dynamic, dynamic>? raw) {
    final map = raw ?? const {};

    // RTDB merepresentasikan array sebagai List<dynamic> ATAU Map indexed.
    // Tangani keduanya supaya tidak crash saat backend re-order.
    final dynamic schedulesRaw = map['schedules'];
    final List<ScheduleModel> parsedSchedules = <ScheduleModel>[];
    if (schedulesRaw is List) {
      for (var i = 0; i < schedulesRaw.length; i++) {
        final entry = schedulesRaw[i];
        if (entry is Map) {
          parsedSchedules.add(
            ScheduleModel.fromMap(
              (entry['id'] as String?) ?? 'sched_$i',
              entry,
            ),
          );
        }
      }
    } else if (schedulesRaw is Map) {
      schedulesRaw.forEach((key, value) {
        if (value is Map) {
          parsedSchedules.add(
            ScheduleModel.fromMap(key.toString(), value),
          );
        }
      });
    }

    return ComponentModel(
      id: id,
      type: _parseType(map['type'] as String?),
      uiElement: _parseUi(map['ui_element'] as String?),
      label: (map['label'] as String?) ?? id,
      currentState: (map['current_state'] as bool?) ?? false,
      currentValue: _readDouble(map['current_value']),
      automationType: (map['automation_type'] as String?) ?? 'NONE',
      schedules: parsedSchedules,
    );
  }

  bool get isOutput => type == ComponentType.output;
  bool get isInput => type == ComponentType.input;

  static ComponentType _parseType(String? raw) {
    switch (raw) {
      case 'OUTPUT':
        return ComponentType.output;
      case 'INPUT':
        return ComponentType.input;
      default:
        return ComponentType.unknown;
    }
  }

  static ComponentUiElement _parseUi(String? raw) {
    switch (raw) {
      case 'SWITCH':
        return ComponentUiElement.toggleSwitch;
      case 'GAUGE_TEXT':
        return ComponentUiElement.gaugeText;
      default:
        return ComponentUiElement.unknown;
    }
  }

  static double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
