// File: flutter_app/lib/views/pending_approval_page.dart
// =============================================================================
// SmartHome Core - PendingApprovalPage
// =============================================================================
// Halaman jeda untuk user dengan status 'Pending' atau user yang baru saja
// di-kick oleh Owner (profil hilang dari /users/<uid>).
//
// Mengikuti semangat docs/PRD.md bab 4.B: user tidak boleh melihat atau
// mengontrol perangkat apa pun hingga Owner men-Approve. Halaman ini hanya
// menampilkan instruksi dan tombol Logout untuk berpindah akun.
//
// Listener real-time pada AuthViewModel akan otomatis mendorong user ke
// DashboardPage segera setelah Owner mengubah status ke 'Approved',
// sehingga tidak perlu tombol "Refresh" manual.
// =============================================================================

import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../theme/app_colors.dart';
import '../viewmodels/auth_viewmodel.dart';

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({
    super.key,
    required this.viewModel,
    required this.profile,
  });

  final AuthViewModel viewModel;
  final UserModel profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryCanvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _buildStatusInfo(),
                      const SizedBox(height: 24),
                      _buildHelpBox(),
                      const SizedBox(height: 24),
                      _buildLogoutButton(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.statusOffline.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hourglass_top,
            color: AppColors.statusOffline,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Menunggu Persetujuan Owner',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusInfo() {
    final displayName = profile.name.isNotEmpty ? profile.name : 'Tamu';
    final email = profile.email.isNotEmpty ? profile.email : '-';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryCanvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Nama', displayName),
          const SizedBox(height: 6),
          _buildInfoRow('Email', email),
          const SizedBox(height: 6),
          _buildInfoRow('Status', 'PENDING'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSub,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHelpBox() {
    return const Text(
      'Akun Anda berhasil dibuat namun belum disetujui oleh Owner rumah. '
      'Halaman ini akan otomatis berpindah ke Dashboard segera setelah '
      'Owner menyetujui akun Anda — tidak perlu refresh manual.',
      style: TextStyle(
        color: AppColors.textSub,
        fontSize: 13,
        height: 1.4,
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.logout, color: AppColors.textMain),
        label: const Text(
          'Keluar',
          style: TextStyle(color: AppColors.textMain),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.dividerSoft),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => viewModel.signOut(),
      ),
    );
  }
}
