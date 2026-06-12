// File: flutter_app/lib/widgets/app_drawer.dart
// =============================================================================
// SmartHome Core - Navigation Drawer
// =============================================================================
// Mengimplementasikan Drawer sesuai docs/wireframe_component.md bab 1.A:
//
//   - Header Drawer    : Profil user aktif + badge (Owner / Approved User)
//   - Body Drawer (Owner-only):
//       * Indikator kuota pengguna (LinearProgressIndicator)
//       * User Control Panel (placeholder list - akan diperluas pada
//         Fase 2 ketika fitur multi-user diaktifkan)
//   - Device Selector  : ListView.builder device + dot indikator status
//                        (Fase 1 hanya 1 device, tetap pakai builder agar
//                         agnostic ke jumlah device di fase berikutnya)
//
// Lebar tetap 304dp via property `width` (acuan: wireframe bab 1.A).
// =============================================================================

import 'package:flutter/material.dart';

import '../models/device_model.dart';
import '../models/user_model.dart';
import '../theme/app_colors.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.user,
    required this.device,
  });

  /// Profil user yang sedang login. Anonymous = tampil sebagai guest.
  final UserModel user;

  /// Device yang dipantau (Fase 1: hanya satu). Bisa null saat belum ada
  /// data dari RTDB.
  final DeviceModel? device;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 304,
      child: Drawer(
        backgroundColor: AppColors.cardBackground,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const Divider(height: 1, color: AppColors.dividerSoft),

              // RBAC: User Control Panel HANYA untuk Owner.
              if (user.isOwner) ...[
                _buildUserQuota(),
                const Divider(height: 1, color: AppColors.dividerSoft),
                Expanded(child: _buildOwnerSections()),
              ] else
                Expanded(child: _buildMemberSections()),

              const Divider(height: 1, color: AppColors.dividerSoft),
              _buildDeviceSelector(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    final displayName = user.isAnonymous ? 'Tamu' : user.name;
    final badgeText = user.isOwner
        ? 'Owner'
        : (user.isApproved ? 'Approved User' : 'Pending');
    final badgeColor = user.isOwner
        ? AppColors.stateActive
        : (user.isApproved ? AppColors.statusOnline : AppColors.statusOffline);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.dividerSoft,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textMain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BAGIAN OWNER: INDIKATOR KUOTA + USER CONTROL PANEL
  // ---------------------------------------------------------------------------
  Widget _buildUserQuota() {
    // Untuk Fase 1, kuota tidak dipantau real-time dari RTDB
    // (akan disambungkan ke /system_configs/user_limit_caps pada fase
    // berikutnya). Ditampilkan sebagai placeholder informatif.
    const int used = 1;
    const int max = 5;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kuota Pengguna',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: used / max,
              minHeight: 6,
              backgroundColor: AppColors.dividerSoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.statusOnline,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$used dari $max slot terpakai',
            style: const TextStyle(
              color: AppColors.textSub,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerSections() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ListTile(
          leading: const Icon(Icons.group, color: AppColors.textMain),
          title: const Text(
            'User Control Panel',
            style: TextStyle(color: AppColors.textMain),
          ),
          subtitle: const Text(
            'Approve / Reject / Kick',
            style: TextStyle(color: AppColors.textSub),
          ),
          onTap: () {
            // Hook navigasi ke halaman manajemen user (Fase 2).
          },
        ),
        ListTile(
          leading: const Icon(Icons.tune, color: AppColors.textMain),
          title: const Text(
            'Pengaturan Perangkat',
            style: TextStyle(color: AppColors.textMain),
          ),
          onTap: () {
            // Hook navigasi ke pengaturan device (Fase 2).
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BAGIAN MEMBER: VIEW-ONLY
  // ---------------------------------------------------------------------------
  Widget _buildMemberSections() {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        ListTile(
          leading: Icon(Icons.info_outline, color: AppColors.textSub),
          title: Text(
            'Mode Pengguna',
            style: TextStyle(color: AppColors.textMain),
          ),
          subtitle: Text(
            'Anda hanya dapat memantau sensor dan menyalakan saklar manual sesuai izin Owner.',
            style: TextStyle(color: AppColors.textSub, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // DEVICE SELECTOR (Fase 1: 1 item)
  // ---------------------------------------------------------------------------
  Widget _buildDeviceSelector() {
    final devices = device != null ? <DeviceModel>[device!] : <DeviceModel>[];
    return Container(
      color: AppColors.primaryCanvas,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Perangkat Terdaftar',
              style: TextStyle(
                color: AppColors.textSub,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Belum ada perangkat',
                style: TextStyle(color: AppColors.textSub),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devices.length,
              itemBuilder: (context, idx) {
                final d = devices[idx];
                final dotColor = d.status == DeviceStatus.online
                    ? AppColors.statusOnline
                    : AppColors.statusOffline;
                return ListTile(
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(
                    d.name,
                    style: const TextStyle(color: AppColors.textMain),
                  ),
                  subtitle: Text(
                    d.id,
                    style: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
