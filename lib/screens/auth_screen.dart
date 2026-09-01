import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';
import 'forgot_password_screen.dart';
import 'main_navigation.dart';
import 'role_selection_screen.dart';
import 'otp_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  // Login controllers
  final _identifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Register controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _registerPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _identifierController.dispose();
    _loginPasswordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _registerPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: colors.onPrimary)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildLangToggle(strings),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      _buildLogo(),
                      const SizedBox(height: 32),
                      _buildTabBar(strings),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 560,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildLoginTab(strings),
                            _buildRegisterTab(strings),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLangToggle(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.read<LanguageNotifier>().toggle(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.outlineVariant, width: 1),
            ),
            child: Text(
              strings.langToggle,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        // The real app logo, not a stand-in Material glyph.
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colors.primary.withValues(alpha: 0.7), width: 3),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'কিচাই',
          style: TextStyle(
            // Was ivory (#FDFBF6) — a near-white sitting directly on the light
            // canvas, so the wordmark was all but invisible. It is not on the
            // gradient; that belongs to the sibling logo above it.
            color: colors.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        Text(
          'আপনার বিশ্বস্ত সেবা মার্কেটপ্লেস',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2);
  }

  Widget _buildTabBar(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant, width: 1.5),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: AppGradients.primary(colors),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withOpacity(0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(4),
            dividerColor: Colors.transparent,
            labelColor: colors.onPrimary,
            unselectedLabelColor: colors.outline,
            labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: strings.loginTab),
              Tab(text: strings.registerTab),
            ],
          ),
        ),
      ),
    ).animate(delay: 200.ms).fadeIn(duration: 400.ms);
  }

  Widget _buildLoginTab(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.welcomeBack,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            strings.loginSubtitle,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _identifierController,
            hint: context.read<LanguageNotifier>().isBengali
                ? 'ইমেইল বা মোবাইল নম্বর'
                : 'Email or mobile number',
            icon: Icons.person_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _loginPasswordController,
            hint: strings.password,
            icon: Icons.lock_rounded,
            obscure: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: colors.outline,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
              child: Text(
                strings.forgotPassword,
                style: TextStyle(color: colors.primary, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassButton(
            label: strings.login,
            isLoading: _isLoading,
            onPressed: () => _handleLogin(strings),
          ),
          const SizedBox(height: 16),
          _buildDivider(strings),
          const SizedBox(height: 16),
          GlassButton(
            label: strings.loginWithGoogle,
            icon: Icons.g_mobiledata_rounded,
            isOutlined: true,
            isLoading: _isGoogleLoading,
            onPressed: (_isLoading || _isGoogleLoading) ? null : () => _handleGoogleLogin(strings),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildRegisterTab(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.createAccount,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            strings.registerSubtitle,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _nameController,
            hint: strings.fullName,
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _emailController,
            hint: context.read<LanguageNotifier>().isBengali ? 'ইমেইল ঠিকানা' : 'Email address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _phoneController,
            hint: strings.phone,
            icon: Icons.phone_android_rounded,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _registerPasswordController,
            hint: strings.password,
            icon: Icons.lock_rounded,
            obscure: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: colors.outline,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 18),
          GlassButton(
            label: strings.register,
            isLoading: _isLoading,
            onPressed: () => _handleRegister(strings),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: colors.onSurface, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: colors.outline, size: 20),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildDivider(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: colors.outlineVariant, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(strings.orDivider, style: TextStyle(color: colors.outline, fontSize: 13)),
        ),
        Expanded(child: Divider(color: colors.outlineVariant, thickness: 1)),
      ],
    );
  }

  // ── Login handler ─────────────────────────────────────────────────

  Future<void> _handleLogin(AppStrings strings) async {
    final identifier = _identifierController.text.trim();
    final password = _loginPasswordController.text;

    if (identifier.isEmpty) {
      _showError(strings.errPhoneRequired);
      return;
    }
    if (password.isEmpty) {
      _showError(strings.errPasswordRequired);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.login(
        identifier: identifier,
        password: password,
      );
      final next = await postLoginDestination();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => next),
            );
          }
        });
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google login handler ──────────────────────────────────────────
  /// Backend nije account create kore — signup ar login same flow.
  Future<void> _handleGoogleLogin(AppStrings strings) async {
    setState(() => _isGoogleLoading = true);
    try {
      final result = await AuthService.instance.googleLogin();
      if (result == null) return; // user cancelled picker — silent
      final next = await postLoginDestination();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => next),
          );
        }
      });
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // ── Register handler ──────────────────────────────────────────────

  Future<void> _handleRegister(AppStrings strings) async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _registerPasswordController.text;

    if (name.isEmpty) {
      _showError(strings.errNameRequired);
      return;
    }
    if (email.isEmpty) {
      _showError(context.read<LanguageNotifier>().isBengali
          ? 'ইমেইল ঠিকানা দিন'
          : 'Enter email address');
      return;
    }
    if (password.isEmpty) {
      _showError(strings.errPasswordRequired);
      return;
    }
    if (password.length < 6) {
      _showError(strings.errPasswordShort);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await AuthService.instance.signup(
        fullName: name,
        email: email,
        password: password,
        phone: phone.isNotEmpty ? phone : null,
        role: 'user',
      );
      if (!mounted) return;
      if (result == null) {
        // Server requires email verification — navigate to OTP screen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => OtpScreen(email: email)),
            );
          }
        });
      } else {
        // Got tokens — navigate using addPostFrameCallback to avoid
        // BackdropFilter removeChild crash on Flutter Web.
        final next = await postLoginDestination();
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => next),
            );
          }
        });
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
