import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'auth_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final isBn = context.read<LanguageNotifier>().isBengali;
    final otp = _otpController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (otp.length < 4) { setState(() => _error = isBn ? 'সঠিক OTP দিন' : 'Enter a valid OTP'); return; }
    if (password.length < 8) { setState(() => _error = isBn ? 'পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে' : 'Password must be at least 8 characters'); return; }
    if (password != confirm) { setState(() => _error = isBn ? 'পাসওয়ার্ড মিলছে না' : 'Passwords do not match'); return; }

    setState(() { _isLoading = true; _error = null; });
    try {
      await ApiClient.instance.dio.post('/auth/reset-password', data: {
        'identifier': widget.email, // the account to reset — backend finds it by email/phone
        'otp': otp,                 // the 6-digit code from forgot-password
        'newPassword': password,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isBn ? 'পাসওয়ার্ড সফলভাবে পরিবর্তিত হয়েছে' : 'Password changed successfully', style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF10B981),
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
      if (mounted) setState(() => _error = ex.localized(isBn));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOtp() async {
    final isBn = context.read<LanguageNotifier>().isBengali;
    try {
      await ApiClient.instance.dio.post('/auth/resend-otp', data: {
        'targetValue': widget.email,
        'targetType': 'email',
        'purpose': 'password_reset',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isBn ? 'OTP পুনরায় পাঠানো হয়েছে' : 'OTP resent', style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF3B82F6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(isBn ? 'পাসওয়ার্ড রিসেট' : 'Reset password', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
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
              Text(
                isBn ? '${widget.email} এ OTP পাঠানো হয়েছে' : 'An OTP has been sent to ${widget.email}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(isBn ? 'OTP কোড' : 'OTP code'),
                    _field(
                      controller: _otpController,
                      hint: isBn ? '6-সংখ্যার OTP' : '6-digit OTP',
                      icon: Icons.key_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _resendOtp,
                        child: Text(isBn ? 'পুনরায় পাঠান' : 'Resend', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12)),
                      ),
                    ),
                    _label(isBn ? 'নতুন পাসওয়ার্ড' : 'New password'),
                    _field(
                      controller: _passwordController,
                      hint: isBn ? 'কমপক্ষে ৮ অক্ষর' : 'At least 8 characters',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePass,
                      toggleObscure: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    const SizedBox(height: 16),
                    _label(isBn ? 'পাসওয়ার্ড নিশ্চিত করুন' : 'Confirm password'),
                    _field(
                      controller: _confirmController,
                      hint: isBn ? 'পাসওয়ার্ড পুনরায় দিন' : 'Re-enter password',
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
                      label: _isLoading
                          ? (isBn ? 'পরিবর্তন হচ্ছে...' : 'Changing...')
                          : (isBn ? 'পাসওয়ার্ড পরিবর্তন করুন' : 'Change password'),
                      onPressed: _isLoading ? null : _submit,
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.2, end: 0),
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
