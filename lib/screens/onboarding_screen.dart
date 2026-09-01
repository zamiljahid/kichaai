import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
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

  // A field initializer cannot reach Theme.of(context), and these colours must
  // follow the active seed — so the list is built per access instead. The copy
  // is unchanged.
  List<_OnboardingData> get _pages {
    final colors = Theme.of(context).colorScheme;
    return [
    _OnboardingData(
      icon: Icons.verified_user_rounded,
      title: 'যাচাইকৃত সেবাদাতা',
      titleEn: 'Verified Providers',
      desc: 'সকল সেবাদাতা NID যাচাইকৃত এবং পেশাগতভাবে প্রশিক্ষিত',
      descEn: 'Every provider is NID-verified and professionally trained',
      color: colors.primary,
    ),
    _OnboardingData(
      icon: Icons.flash_on_rounded,
      title: 'দ্রুত সংযোগ',
      titleEn: 'Fast Matching',
      desc: 'আপনার চাহিদা পোস্ট করুন, সেবাদাতা নিজেই আপনার কাছে আসবে',
      descEn: 'Post what you need — providers come to you',
      color: colors.secondary,
    ),
    _OnboardingData(
      icon: Icons.category_rounded,
      title: '১৬টি সেবা বিভাগ',
      titleEn: '16 Categories',
      desc: 'ক্যারগিভার থেকে ফটোগ্রাফার — সব ধরনের সেবা এক প্ল্যাটফর্মে',
      descEn: 'From caregivers to photographers — every service, one platform',
        color: colors.primary,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.watch<LanguageNotifier>().isBengali;
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
                    isBn ? 'এড়িয়ে যান' : 'Skip',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemCount: _pages.length,
                  itemBuilder: (_, i) => _buildPage(_pages[i], isBn),
                ),
              ),
              _buildDots(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: _currentPage == _pages.length - 1
                    ? GlassButton(
                        label: isBn ? 'শুরু করুন' : 'Get Started',
                        onPressed: _goToAuth,
                        icon: Icons.arrow_forward_rounded,
                      )
                    : GlassButton(
                        label: isBn ? 'পরবর্তী' : 'Next',
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

  Widget _buildPage(_OnboardingData data, bool isBn) {
    final colors = Theme.of(context).colorScheme;
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
            child: Icon(data.icon, color: colors.onPrimary, size: 64),
          )
              .animate(key: ValueKey(data.title))
              .scale(duration: 500.ms, curve: Curves.elasticOut)
              .fadeIn(),
          const SizedBox(height: 40),
          GlassCard(
            child: Column(
              children: [
                Text(
                  isBn ? data.title : data.titleEn,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  isBn ? data.desc : data.descEn,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
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
    final colors = Theme.of(context).colorScheme;
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
            color: i == _currentPage ? colors.primary : colors.outline,
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
  final String descEn;
  final Color color;
  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.titleEn,
    required this.desc,
    required this.descEn,
    required this.color,
  });
}
