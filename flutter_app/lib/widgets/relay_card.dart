// File: flutter_app/lib/widgets/relay_card.dart
// =============================================================================
// SmartHome Core - RelayCard Widget
// =============================================================================
// Card untuk merender satu komponen bertipe OUTPUT (SWITCH) sesuai
// spesifikasi docs/wireframe_component.md bab 3.A.
//
// Struktur tiga tingkat:
//   Row Atas    : Icon dinamis + label + Switch manual (toggle current_state)
//   Divider     : muncul hanya jika array schedules tidak kosong
//   Sub-List    : ListView.builder schedules ala alarm HP, tiap tile
//                 menampilkan jam "HH:mm - HH:mm" + label + Switch is_active
//                 Tap pada tile memicu showTimePicker untuk edit jam.
//   Footer      : Tombol "+ Tambah Jadwal" (HANYA muncul jika user Owner)
//
// Aturan khusus:
//   - Visual Offline Masking: bila device offline, seluruh Card dibungkus
//     Opacity 0.5 dan AbsorbPointer agar tap di mana pun tidak memicu aksi.
//   - RBAC: tombol tambah jadwal dan ikon edit hilang untuk non-Owner.
//   - Konfirmasi delete pakai AlertDialog (acuan wireframe_component bab 5).
// =============================================================================

import 'package:flutter/material.dart';

import '../models/component_model.dart';
import '../models/schedule_model.dart';
import '../theme/app_colors.dart';
import '../viewmodels/dashboard_viewmodel.dart';

class RelayCard extends StatelessWidget {
  const RelayCard({
    super.key,
    required this.component,
    required this.viewModel,
    required this.deviceIsOffline,
    required this.userIsOwner,
  });

  /// Komponen OUTPUT yang dirender. Cukup satu Card per komponen.
  final ComponentModel component;

  /// ViewModel untuk eksekusi aksi tulis ke RTDB.
  final DashboardViewModel viewModel;

  /// Status offline diturunkan dari [DeviceModel.isOffline] agar widget
  /// tidak perlu memantau stream sendiri.
  final bool deviceIsOffline;

  /// Hasil getter [UserModel.isOwner] - menentukan visibility tombol
  /// manajemen jadwal.
  final bool userIsOwner;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopRow(context),
            if (component.schedules.isNotEmpty)
              const Divider(
                height: 1,
                thickness: 0.5,
                color: AppColors.dividerSoft,
              ),
            if (component.schedules.isNotEmpty)
              _buildSchedulesList(context),
            if (userIsOwner) _buildAddScheduleButton(context),
          ],
        ),
      ),
    );

    // Visual Offline Masking - wajib (docs/wireframe_component.md bab 5.A).
    if (!deviceIsOffline) return card;
    return Opacity(
      opacity: 0.5,
      child: AbsorbPointer(absorbing: true, child: card),
    );
  }

  // ---------------------------------------------------------------------------
  // ROW ATAS (Saklar manual)
  // ---------------------------------------------------------------------------
  Widget _buildTopRow(BuildContext context) {
    final activeColor = component.currentState
        ? AppColors.stateActive
        : AppColors.stateInactive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          Icon(Icons.lightbulb, color: activeColor, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              component.label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textMain,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          Switch(
            value: component.currentState,
            activeColor: AppColors.stateActive,
            // Interaksi dinonaktifkan saat offline. Property `onChanged: null`
            // adalah cara resmi Flutter menon-aktifkan Switch (mirror dari
            // `enabled: false` di spek wireframe).
            onChanged: deviceIsOffline
                ? null
                : (next) => viewModel.toggleRelay(component.id, next),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LIST JADWAL (alarm HP-like)
  // ---------------------------------------------------------------------------
  Widget _buildSchedulesList(BuildContext context) {
    // shrinkWrap + NeverScrollableScrollPhysics agar inner-list tidak
    // bersaing dengan parent ListView.builder DashboardPage.
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: component.schedules.length,
      itemBuilder: (context, index) {
        final s = component.schedules[index];
        return _ScheduleTile(
          schedule: s,
          showOwnerActions: userIsOwner,
          onToggleActive: (next) => viewModel.toggleScheduleActive(
            componentId: component.id,
            scheduleId: s.id,
            nextActive: next,
          ),
          onTap: userIsOwner
              ? () => _openEditScheduleDialog(context, s)
              : null,
          onDelete: userIsOwner
              ? () => _confirmAndDelete(context, s)
              : null,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER (+ Tambah Jadwal) - hanya Owner
  // ---------------------------------------------------------------------------
  Widget _buildAddScheduleButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        icon: const Icon(Icons.add, color: AppColors.textMain),
        label: const Text(
          '+ Tambah Jadwal',
          style: TextStyle(color: AppColors.textMain),
        ),
        onPressed: () => _openCreateScheduleDialog(context),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOG: TAMBAH JADWAL BARU
  // ---------------------------------------------------------------------------
  Future<void> _openCreateScheduleDialog(BuildContext context) async {
    final onTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
      helpText: 'Pilih Jam Nyala',
    );
    if (onTime == null || !context.mounted) return;

    final offTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 5, minute: 30),
      helpText: 'Pilih Jam Mati',
    );
    if (offTime == null || !context.mounted) return;

    final label = await _promptLabel(context, initial: 'Jadwal Baru');
    if (label == null || label.isEmpty || !context.mounted) return;

    final schedule = ScheduleModel(
      id: 'sched_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      isActive: true,
      onTime: _formatTimeOfDay(onTime),
      offTime: _formatTimeOfDay(offTime),
    );
    await viewModel.upsertSchedule(
      componentId: component.id,
      schedule: schedule,
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOG: EDIT JADWAL EXISTING
  // ---------------------------------------------------------------------------
  Future<void> _openEditScheduleDialog(
    BuildContext context,
    ScheduleModel existing,
  ) async {
    final parsedOn = _parseHHmm(existing.onTime);
    final parsedOff = _parseHHmm(existing.offTime);

    final onTime = await showTimePicker(
      context: context,
      initialTime: parsedOn,
      helpText: 'Edit Jam Nyala',
    );
    if (onTime == null || !context.mounted) return;

    final offTime = await showTimePicker(
      context: context,
      initialTime: parsedOff,
      helpText: 'Edit Jam Mati',
    );
    if (offTime == null || !context.mounted) return;

    final label = await _promptLabel(context, initial: existing.label);
    if (label == null || label.isEmpty || !context.mounted) return;

    final updated = existing.copyWith(
      label: label,
      onTime: _formatTimeOfDay(onTime),
      offTime: _formatTimeOfDay(offTime),
    );
    await viewModel.upsertSchedule(
      componentId: component.id,
      schedule: updated,
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOG: PROMPT LABEL (digunakan oleh create & edit)
  // ---------------------------------------------------------------------------
  Future<String?> _promptLabel(
    BuildContext context, {
    required String initial,
  }) async {
    // TextEditingController WAJIB di-dispose (skill.md bab 3 - 🔴 Flutter #2).
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text(
              'Nama Jadwal',
              style: TextStyle(color: AppColors.textMain),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Mis. Otomatisasi Malam Hari',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('BATAL'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: const Text('SIMPAN'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // DIALOG: KONFIRMASI HAPUS
  // ---------------------------------------------------------------------------
  Future<void> _confirmAndDelete(
    BuildContext context,
    ScheduleModel s,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Hapus Jadwal?'),
          content: Text(
            'Jadwal "${s.label}" (${s.onTime} - ${s.offTime}) akan dihapus permanen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('BATAL'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'HAPUS',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await viewModel.deleteSchedule(
        componentId: component.id,
        scheduleId: s.id,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // HELPER: format TimeOfDay <-> "HH:mm"
  // ---------------------------------------------------------------------------
  static String _formatTimeOfDay(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static TimeOfDay _parseHHmm(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 0, minute: 0);
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }
}

// =============================================================================
// PRIVATE WIDGET: SATU BARIS JADWAL (mirip alarm HP)
// =============================================================================
class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    required this.schedule,
    required this.showOwnerActions,
    required this.onToggleActive,
    required this.onTap,
    required this.onDelete,
  });

  final ScheduleModel schedule;
  final bool showOwnerActions;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final timeText = '${schedule.onTime} - ${schedule.offTime}';
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.alarm, color: AppColors.stateInactive),
      title: Text(
        timeText,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
      ),
      subtitle: Text(
        schedule.label,
        style: const TextStyle(color: AppColors.textSub),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Switch kecil untuk is_active.
          Switch(
            value: schedule.isActive,
            activeColor: AppColors.stateActive,
            onChanged: showOwnerActions
                ? (next) => onToggleActive(next)
                : null,
          ),
          if (showOwnerActions)
            IconButton(
              tooltip: 'Hapus jadwal',
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.statusOffline,
              ),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
