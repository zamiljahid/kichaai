import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_OnboardingData> _pages = const [
    _OnboardingData(
      icon: Icons.verified_user_rounded,
      title: 'যাচাইকৃত সেবাদাতা',
      titleEn: 'Verified Providers',
      desc: 'সকল সেবাদাতা NID যাচাইকৃত এবং পেশাগতভাবে প্রশিক্ষিত',
      color: AppColors.deepBlue,
    ),
    _OnboardingData(
      icon: Icons.flash_on_rounded,
      title: 'দ্রুত সংযোগ',
      titleEn: 'Fast Matching',
      desc: 'আপনার চাহিদা পোস্ট করুন, সেবাদাতা নিজেই আপনার কাছে আসবে',
      color: AppColors.fuchsia,
    ),
    _OnboardingData(
      icon: Icons.category_rounded,
      title: '১৬টি সেবা বিভাগ',
      titleEn: '16 Categories',
      desc: 'ক্যারগিভার থেকে ফটোগ্রাফার — সব ধরনের সেবা এক প্ল্যাটফর্মে',
      color: AppColors.deepBlue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _goToAuth,
                  child: Text(
                    'এড়িয়ে যান',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemCount: _pages.length,
                  itemBuilder: (_, i) => _buildPage(_pages[i]),
                ),
              ),
              _buildDots(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: _currentPage == _pages.length - 1
                    ? GlassButton(
                        label: 'শুরু করুন',
                        onPressed: _goToAuth,
                        icon: Icons.arrow_forward_rounded,
                      )
                    : GlassButton(
                        label: 'পরবর্তী',
                        onPressed: () => _controller.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        ),
                        icon: Icons.arrow_forward_rounded,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [data.color, data.color.withOpacity(0.6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: data.color.withOpacity(0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Icon(data.icon, color: AppColors.ivory, size: 64),
          )
              .animate(key: ValueKey(data.title))
              .scale(duration: 500.ms, curve: Curves.elasticOut)
              .fadeIn(),
          const SizedBox(height: 40),
          GlassCard(
            child: Column(
              children: [
                Text(
                  data.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  data.titleEn,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  data.desc,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
              .animate(key: ValueKey('card_${data.title}'))
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.2),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _pages.length,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == _currentPage ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == _currentPage ? AppColors.deepBlue : AppColors.textMuted,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  void _goToAuth() {
    // Remember the intro was shown so returning users skip straight to login.
    ApiClient.setOnboardingSeen();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }
}

class _OnboardingData {
  final IconData icon;
  final String title;
  final String titleEn;
  final String desc;
  final Color color;
  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.titleEn,
    required this.desc,
    required this.color,
  });
}
