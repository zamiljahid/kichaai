import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'main_navigation.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: colors.onPrimary)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _verify() async {
    final isBn = context.read<LanguageNotifier>().isBengali;
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      _showError(isBn ? 'সঠিক OTP কোড দিন' : 'Enter a valid OTP code');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final client = ApiClient.instance.dio;
      await client.post('/auth/verify-otp', data: {
        'targetValue': widget.email,
        'targetType': 'email',
        'otpCode': otp,
        'purpose': 'email_verification',
      });
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
          );
        }
      });
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(isBn));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary(colors),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withOpacity(0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(Icons.mark_email_read_rounded, color: colors.onPrimary, size: 36),
                ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.8, 0.8)),
                const SizedBox(height: 20),
                Text(
                  isBn ? 'ইমেইল যাচাই করুন' : 'Verify your email',
                  style: TextStyle(color: colors.onSurface, fontSize: 24, fontWeight: FontWeight.w700),
                ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                const SizedBox(height: 8),
                Text(
                  isBn ? '${widget.email} ঠিকানায় পাঠানো OTP কোডটি দিন' : 'Enter the OTP code sent to ${widget.email}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: 400.ms, delay: 150.ms),
                const SizedBox(height: 32),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isBn ? 'OTP কোড' : 'OTP code',
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 12,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '------',
                          hintStyle: TextStyle(color: colors.outline, fontSize: 28, letterSpacing: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GlassButton(
                        label: isBn ? 'যাচাই করুন' : 'Verify',
                        isLoading: _isLoading,
                        onPressed: _verify,
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    isBn ? 'ফিরে যান' : 'Go back',
                    style: TextStyle(color: colors.outline, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
