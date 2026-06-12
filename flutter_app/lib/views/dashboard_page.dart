// File: flutter_app/lib/views/dashboard_page.dart
// =============================================================================
// SmartHome Core - Dashboard Page (Halaman Kontrol Utama)
// =============================================================================
// Halaman tunggal yang merender seluruh komponen perangkat aktif menggunakan
// ListView.builder agnostik (docs/wireframe_component.md bab 3).
//
// Struktur:
//   Scaffold
//     ├─ AppBar    : Judul + toggle drawer
//     ├─ Drawer    : AppDrawer (RBAC + device selector)
//     └─ Body
//         ├─ OfflineBanner   (kondisional, status != Online)
//         ├─ DeviceHeader    (nama device + status dot)
//         ├─ Zona OUTPUT     (RelayCard via ListView.builder)
//         └─ Zona INPUT      (placeholder Fase 1: kosong)
//
// Komponen reactive memakai ValueListenableBuilder pada `viewModel.state`
// agar widget tree hanya rebuild ketika DashboardState benar-benar
// berubah. Error transient ditampilkan via SnackBar dan langsung
// di-acknowledge ke ViewModel.
// =============================================================================

import 'package:flutter/material.dart';

import '../models/component_model.dart';
import '../models/device_model.dart';
import '../theme/app_colors.dart';
import '../viewmodels/dashboard_viewmodel.dart';
import '../widgets/app_drawer.dart';
import '../widgets/relay_card.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final VoidCallback _errorListener;

  @override
  void initState() {
    super.initState();
    // Tampilkan SnackBar tiap kali state.errorMessage berubah menjadi
    // non-null. Lalu acknowledge supaya pesan tidak muncul ulang.
    _errorListener = () {
      final msg = widget.viewModel.state.value.errorMessage;
      if (msg == null) return;
      // Pastikan widget masih mounted sebelum showSnackBar (race condition
      // saat user tutup halaman tepat saat error datang).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      widget.viewModel.acknowledgeError();
    };
    widget.viewModel.state.addListener(_errorListener);
  }

  @override
  void dispose() {
    widget.viewModel.state.removeListener(_errorListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DashboardState>(
      valueListenable: widget.viewModel.state,
      builder: (context, state, _) {
        final device = state.device;
        return Scaffold(
          backgroundColor: AppColors.primaryCanvas,
          appBar: AppBar(
            backgroundColor: AppColors.cardBackground,
            elevation: 1,
            iconTheme: const IconThemeData(color: AppColors.textMain),
            title: const Text(
              'SmartHome Core',
              style: TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          drawer: AppDrawer(user: state.user, device: device),
          body: _buildBody(context, state),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BODY
  // ---------------------------------------------------------------------------
  Widget _buildBody(BuildContext context, DashboardState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final device = state.device;
    if (device == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Perangkat belum terdaftar pada cloud.\n'
            'Hubungkan ESP32 ke jaringan agar booting report terkirim.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSub),
          ),
        ),
      );
    }

    // Split komponen menjadi dua zona vertikal (OUTPUT vs INPUT) sesuai
    // docs/wireframe_component.md bab 3.
    final outputs = device.components.where((c) => c.isOutput).toList();
    final inputs = device.components.where((c) => c.isInput).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (device.isOffline) const _OfflineBanner(),
          _buildDeviceHeader(device),
          _buildZoneLabel('ZONA OUTPUT (RELAY)'),
          if (outputs.isEmpty)
            _buildEmptyZone('Belum ada relay aktif pada perangkat ini.')
          else
            // Agnostic UI Rendering - tipe komponen menentukan widget.
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: outputs.length,
              itemBuilder: (context, idx) {
                final comp = outputs[idx];
                // Saat ini hanya SWITCH yang didukung pada Fase 1.
                // Switch statement dipertahankan agar ekstensi mudah.
                switch (comp.uiElement) {
                  case ComponentUiElement.toggleSwitch:
                    return RelayCard(
                      component: comp,
                      viewModel: widget.viewModel,
                      deviceIsOffline: device.isOffline,
                      userIsOwner: state.user.isOwner,
                    );
                  case ComponentUiElement.gaugeText:
                  case ComponentUiElement.unknown:
                    return _buildUnsupportedCard(comp);
                }
              },
            ),
          _buildZoneLabel('ZONA INPUT (SENSOR)'),
          if (inputs.isEmpty)
            _buildEmptyZone(
              'Belum ada sensor terpasang.\nFitur threshold otomatisasi tersedia mulai Fase 2.',
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: inputs.length,
              itemBuilder: (context, idx) {
                return _buildUnsupportedCard(inputs[idx]);
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPER WIDGETS
  // ---------------------------------------------------------------------------
  Widget _buildDeviceHeader(DeviceModel device) {
    final dotColor = device.status == DeviceStatus.online
        ? AppColors.statusOnline
        : AppColors.statusOffline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Status: ${device.status.name.toUpperCase()}',
                    style: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSub,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildEmptyZone(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSub),
        ),
      ),
    );
  }

  Widget _buildUnsupportedCard(ComponentModel comp) {
    // Fallback aman untuk komponen yang skema-nya belum dipetakan ke
    // widget (mis. GAUGE_TEXT pada Fase 1). Mencegah blank tile + memberi
    // umpan balik visual ke developer/tester.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          '${comp.label}\n(Komponen "${comp.uiElement.name}" belum didukung pada Fase 1)',
          style: const TextStyle(color: AppColors.textSub),
        ),
      ),
    );
  }
}

// =============================================================================
// PRIVATE WIDGET: BANNER OFFLINE
// =============================================================================
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.statusOffline,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Text(
        'Koneksi dengan perangkat terputus. Menggunakan mode baca terakhir (Offline Mode).',
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
