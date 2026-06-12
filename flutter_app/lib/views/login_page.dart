// File: flutter_app/lib/views/login_page.dart
// =============================================================================
// SmartHome Core - LoginPage
// =============================================================================
// Halaman login + registrasi dengan toggle mode. Mengikuti palet warna
// docs/wireframe_component.md bab 2 dan menerapkan:
//
//   - Dispose semua TextEditingController (skill.md bab 3 - 🔴 Flutter #2)
//   - Loading state agar tombol disable saat request berlangsung
//   - Pesan error via SnackBar dari AuthViewModel.errorMessage
//   - Validasi format email & panjang password minimal 6 karakter
//
// Catatan: PendingApprovalPage akan ditampilkan secara otomatis oleh
// AuthGate setelah register sukses (status Pending), bukan dari halaman ini.
// =============================================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../viewmodels/auth_viewmodel.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.viewModel});

  final AuthViewModel viewModel;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isRegisterMode = false;
  bool _isLoading = false;

  late final VoidCallback _errorListener;

  @override
  void initState() {
    super.initState();
    _errorListener = () {
      final msg = widget.viewModel.state.value.errorMessage;
      if (msg == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      widget.viewModel.acknowledgeError();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    };
    widget.viewModel.state.addListener(_errorListener);
  }

  @override
  void dispose() {
    widget.viewModel.state.removeListener(_errorListener);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _isLoading = true);

    if (_isRegisterMode) {
      await widget.viewModel.register(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } else {
      await widget.viewModel.signIn(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
    }

    // AuthGate akan menavigasi keluar dari LoginPage saat stage berubah,
    // jadi cukup matikan loading bila kita masih mounted (sukses path
    // umumnya unmount sebelum baris ini tercapai).
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        if (_isRegisterMode) ...[
                          _buildNameField(),
                          const SizedBox(height: 16),
                        ],
                        _buildEmailField(),
                        const SizedBox(height: 16),
                        _buildPasswordField(),
                        const SizedBox(height: 24),
                        _buildSubmitButton(),
                        const SizedBox(height: 12),
                        _buildToggleModeButton(),
                      ],
                    ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.home_filled,
            color: AppColors.stateActive, size: 36),
        const SizedBox(height: 12),
        Text(
          _isRegisterMode ? 'Daftar Akun Baru' : 'Masuk ke SmartHome Core',
          style: const TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isRegisterMode
              ? 'Akun baru akan berstatus Pending hingga disetujui Owner.'
              : 'Gunakan email dan kata sandi terdaftar.',
          style: const TextStyle(
            color: AppColors.textSub,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameCtrl,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Nama Lengkap',
        prefixIcon: Icon(Icons.person_outline),
        border: OutlineInputBorder(),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Nama wajib diisi.';
        if (v.trim().length < 2) return 'Nama minimal 2 karakter.';
        return null;
      },
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Email',
        prefixIcon: Icon(Icons.email_outlined),
        border: OutlineInputBorder(),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Email wajib diisi.';
        if (!v.contains('@') || !v.contains('.')) {
          return 'Format email tidak valid.';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordCtrl,
      obscureText: true,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        labelText: 'Kata Sandi',
        prefixIcon: Icon(Icons.lock_outline),
        border: OutlineInputBorder(),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Kata sandi wajib diisi.';
        if (v.length < 6) return 'Minimal 6 karakter.';
        return null;
      },
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.textMain,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: _isLoading ? null : _submit,
      child: _isLoading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              _isRegisterMode ? 'DAFTAR' : 'MASUK',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
    );
  }

  Widget _buildToggleModeButton() {
    return TextButton(
      onPressed: _isLoading
          ? null
          : () {
              setState(() => _isRegisterMode = !_isRegisterMode);
            },
      child: Text(
        _isRegisterMode
            ? 'Sudah punya akun? Masuk di sini.'
            : 'Belum punya akun? Daftar.',
        style: const TextStyle(color: AppColors.textSub),
      ),
    );
  }
}
