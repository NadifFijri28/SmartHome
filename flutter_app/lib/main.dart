// File: flutter_app/lib/main.dart
// =============================================================================
// Entry point aplikasi SmartHome Core (Fase 1 MVP).
//
// Tanggung jawab file ini:
//   - Inisialisasi Firebase Core (wajib sebelum FirebaseAuth/RTDB).
//   - Membuat instance AuthService + AuthViewModel global selama app
//     hidup (di-dispose otomatis saat root widget unmount).
//   - Mount MaterialApp dengan theme PrimaryCanvas + AuthGate sebagai
//     home (DashboardPage/LoginPage/PendingApprovalPage diatur AuthGate).
//
// Tidak ada logika domain di file ini. Semua routing pasca-Firebase init
// berada di AuthGate untuk menjaga separation of concerns.
// =============================================================================

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'theme/app_colors.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'views/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SmartHomeApp());
}

class SmartHomeApp extends StatefulWidget {
  const SmartHomeApp({super.key});

  @override
  State<SmartHomeApp> createState() => _SmartHomeAppState();
}

class _SmartHomeAppState extends State<SmartHomeApp> {
  late final AuthService _authService;
  late final AuthViewModel _authViewModel;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _authViewModel = AuthViewModel(authService: _authService);
  }

  @override
  void dispose() {
    _authViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartHome Core',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.primaryCanvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.stateActive,
          brightness: Brightness.light,
        ),
        cardTheme: const CardThemeData(
          color: AppColors.cardBackground,
          elevation: 2.0,
          margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: AuthGate(authViewModel: _authViewModel),
    );
  }
}
