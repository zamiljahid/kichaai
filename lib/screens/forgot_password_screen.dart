import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'auth_screen.dart';

// Direct password reset — no OTP step (founder call, pre-launch: email OTP is log-only since no
// email provider is wired, so email users could never complete a reset). The backend honours
// this only when RESET_PASSWORD_SKIP_OTP=true is set on auth-service; flip that off + restore
// the ResetPasswordScreen (OTP) flow for production. reset_password_screen.dart is kept on disk
// unused for that.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (identifier.isEmpty) { setState(() => _error = 'ইমেইল বা ফোন নম্বর দিন'); return; }
    if (password.length < 8) { setState(() => _error = 'পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে'); return; }
    if (password != confirm) { setState(() => _error = 'পাসওয়ার্ড মিলছে না'); return; }

    setState(() { _isLoading = true; _error = null; });
    try {
      await ApiClient.instance.dio.post('/auth/reset-password', data: {
        'identifier': identifier,
        'newPassword': password,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('পাসওয়ার্ড সফলভাবে পরিবর্তিত হয়েছে', style: TextStyle(color: Colors.white)),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      final ex = ApiClient.mapError(e);
      if (mounted) setState(() => _error = ex.messageBn);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.blueGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 32),
              ).animate().scale(duration: 400.ms),
              const SizedBox(height: 24),
              const Text(
                'পাসওয়ার্ড ভুলে গেছেন?',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800),
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 8),
              const Text(
                'ইমেইল/ফোন ও নতুন পাসওয়ার্ড দিন',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ).animate().fadeIn(delay: 150.ms),
              const SizedBox(height: 40),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('ইমেইল বা ফোন'),
                    _field(
                      controller: _identifierController,
                      hint: 'example@email.com',
                      icon: Icons.person_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _label('নতুন পাসওয়ার্ড'),
                    _field(
                      controller: _passwordController,
                      hint: 'কমপক্ষে ৮ অক্ষর',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePass,
                      toggleObscure: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    _label('পাসওয়ার্ড নিশ্চিত করুন'),
                    _field(
                      controller: _confirmController,
                      hint: 'পাসওয়ার্ড পুনরায় দিন',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscureConfirm,
                      toggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                    ],
                    const SizedBox(height: 24),
                    GlassButton(
                      label: _isLoading ? 'পরিবর্তন হচ্ছে...' : 'পাসওয়ার্ড পরিবর্তন করুন',
                      onPressed: _isLoading ? null : _submit,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 16),
    child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
  );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? toggleObscure,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
        suffixIcon: toggleObscure != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textMuted, size: 18),
                onPressed: toggleObscure,
              )
            : null,
        filled: true,
        fillColor: AppColors.glassWhite,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
