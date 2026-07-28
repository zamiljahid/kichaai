import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import 'auth_screen.dart';
import 'main_navigation.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // After the splash animation, route by session:
  //  • logged in            → straight into the app (provider toggle preserved)
  //  • seen the intro before → straight to login (no re-watching the carousel)
  //  • first ever launch     → the intro carousel
  Future<void> _bootstrap() async {
    final token = await ApiClient.getAccessToken();
    final seenIntro = await ApiClient.getOnboardingSeen();
    if (token != null && token.isNotEmpty) {
      // Register/refresh the FCM token whenever the app starts logged in —
      // the last-known device may have gone through a token rotation.
      PushService.instance.registerCurrentToken();
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    final Widget next = (token != null && token.isNotEmpty)
        ? const MainNavigation()
        : (seenIntro ? const AuthScreen() : const OnboardingScreen());
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogo(),
              const SizedBox(height: 24),
              _buildTitle(),
              const SizedBox(height: 8),
              _buildTagline(),
              const SizedBox(height: 60),
              _buildLoader(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: AppColors.blueGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withOpacity(0.6),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.deepBlue.withOpacity(0.3),
            blurRadius: 60,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: const Icon(
        Icons.hub_rounded,
        color: AppColors.ivory,
        size: 52,
      ),
    )
        .animate()
        .scale(duration: 600.ms, curve: Curves.elasticOut)
        .fadeIn(duration: 400.ms);
  }

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          'কিচাই',
          style: TextStyle(
            color: AppColors.ivory,
            fontSize: 42,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            shadows: [
              Shadow(
                color: AppColors.deepBlue.withOpacity(0.8),
                blurRadius: 20,
              ),
            ],
          ),
        ).animate(delay: 300.ms).fadeIn(duration: 500.ms).slideY(begin: 0.3),
        Text(
          'Kichaai',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 18,
            fontWeight: FontWeight.w400,
            letterSpacing: 4,
          ),
        ).animate(delay: 500.ms).fadeIn(duration: 500.ms),
      ],
    );
  }

  Widget _buildTagline() {
    return Text(
      'আপনার বিশ্বস্ত সেবা মার্কেটপ্লেস',
      style: TextStyle(
        color: AppColors.textMuted,
        fontSize: 14,
        letterSpacing: 0.5,
      ),
    ).animate(delay: 700.ms).fadeIn(duration: 600.ms);
  }

  Widget _buildLoader() {
    return SizedBox(
      width: 40,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          backgroundColor: AppColors.glassWhite,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.deepBlue),
        ),
      ),
    ).animate(delay: 900.ms).fadeIn(duration: 400.ms);
  }
}
