// File: flutter_app/lib/views/auth_gate.dart
// =============================================================================
// SmartHome Core - AuthGate
// =============================================================================
// Widget root yang memilih halaman berdasarkan AuthStage. Routing dijaga
// di satu tempat agar:
//
//   - Tidak ada widget yang manual `Navigator.push` antar halaman auth.
//   - Real-time Kick (docs/PRD.md bab 4.B) bekerja otomatis: AuthViewModel
//     emit AuthStage.signedOut -> AuthGate rebuild ke LoginPage.
//   - DashboardViewModel HANYA dibuat ketika stage approved/owner. Selama
//     pending/signed-out, tidak ada stream RTDB device yang ter-attach
//     (hemat resource + menghindari error rules 403).
//
// Lifecycle DashboardViewModel di-handle oleh widget anak StatefulWidget
// (_DashboardBootstrap) sehingga dispose otomatis dipanggil saat user
// logout / di-kick dan AuthGate rebuild ke halaman lain.
// =============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/dashboard_viewmodel.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'pending_approval_page.dart';

/// Device id Fase 1 dipusatkan di sini agar AuthGate dapat menyalurkannya
/// ke DashboardViewModel. Pindahkan ke konfigurasi runtime saat Fase
/// multi-device aktif.
const String kPhaseOneDeviceId = 'ESP32_MAC_A1B2C3D4E5F6';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.authViewModel});

  final AuthViewModel authViewModel;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.authViewModel.attach();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: widget.authViewModel.state,
      builder: (context, state, _) {
        switch (state.stage) {
          case AuthStage.unknown:
            return const _LoadingScaffold();
          case AuthStage.signedOut:
            return LoginPage(viewModel: widget.authViewModel);
          case AuthStage.pending:
            return PendingApprovalPage(
              viewModel: widget.authViewModel,
              profile: state.profile,
            );
          case AuthStage.approved:
          case AuthStage.owner:
            // Key berbasis uid agar saat user berganti akun, State
            // _DashboardBootstrap di-rebuild dari nol (dan ViewModel lama
            // di-dispose) - mencegah kebocoran subscription antar-akun.
            return _DashboardBootstrap(
              key: ValueKey('dashboard_${state.profile.uid}'),
              userUid: state.profile.uid,
            );
        }
      },
    );
  }
}

/// Layar loading minimal saat AuthViewModel masih menentukan stage awal.
class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primaryCanvas,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Sub-tree yang memiliki sendiri instance DashboardViewModel. Dipisah
/// menjadi StatefulWidget khusus supaya [dispose] terpanggil tiap kali
/// AuthGate berpindah keluar dari stage approved/owner.
class _DashboardBootstrap extends StatefulWidget {
  const _DashboardBootstrap({super.key, required this.userUid});

  final String userUid;

  @override
  State<_DashboardBootstrap> createState() => _DashboardBootstrapState();
}

class _DashboardBootstrapState extends State<_DashboardBootstrap> {
  late final DashboardViewModel _dashboardViewModel;

  @override
  void initState() {
    super.initState();
    _dashboardViewModel = DashboardViewModel(
      deviceId: kPhaseOneDeviceId,
      currentUserUid: widget.userUid,
    )..attach();
  }

  @override
  void dispose() {
    _dashboardViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DashboardPage(viewModel: _dashboardViewModel);
  }
}
