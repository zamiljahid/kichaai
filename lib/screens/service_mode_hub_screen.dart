import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import 'commute_screen.dart';
import 'cook_screen.dart';
import 'job_request_screen.dart';

/// Cook and Ride each kept BOTH of their halves when they moved onto dispatch (2026-08-27):
///
///   • Cook  — "এখনই রাঁধুনি" broadcasts to nearby online cooks (dispatch), while
///             "সময় ঠিক করে বুক" keeps the older post-a-request/cooks-quote/you-pick flow.
///   • Ride  — "এখনই রাইড" is the Uber/Pathao-style instant ride (dispatch), while
///             "কমিউট পার্টনার" keeps the recurring cost-sharing arrangement that is
///             the platform's actual differentiator.
///
/// Rather than dumping the customer straight into one of them and hiding the other, this
/// screen is the fork. It is deliberately generic so a third hybrid kind costs one config
/// entry rather than another screen.
class ServiceModeHubScreen extends StatelessWidget {
  final _HubConfig config;

  const ServiceModeHubScreen._(this.config);

  /// রান্না — instant broadcast vs scheduled bid-and-pick.
  factory ServiceModeHubScreen.cook() => const ServiceModeHubScreen._(_HubConfig(
        titleBn: 'রান্না',
        titleEn: 'Cooking',
        emoji: '🍳',
        instant: _HubOption(
          titleBn: 'এখনই রাঁধুনি চাই',
          titleEn: 'I need a cook now',
          subtitleBn: 'কাছের অনলাইন রাঁধুনিদের কাছে অনুরোধ যাবে — যিনি আগে রাজি হবেন তিনিই আসবেন',
          subtitleEn: 'Sent to nearby online cooks — whoever accepts first takes the job',
          icon: Icons.bolt_rounded,
        ),
        scheduled: _HubOption(
          titleBn: 'সময় ঠিক করে বুক করি',
          titleEn: 'Book for a specific time',
          subtitleBn: 'আপনার সময় ও বাজেট দিন, রাঁধুনিরা দাম বলবেন, আপনি বেছে নেবেন',
          subtitleEn: 'Post your time and budget, cooks quote, you choose',
          icon: Icons.event_note_rounded,
        ),
      ));

  /// যাতায়াত — instant ride vs recurring commute partner.
  factory ServiceModeHubScreen.ride() => const ServiceModeHubScreen._(_HubConfig(
        titleBn: 'যাতায়াত',
        titleEn: 'Rides',
        emoji: '🛵',
        instant: _HubOption(
          titleBn: 'এখনই রাইড চাই',
          titleEn: 'I need a ride now',
          subtitleBn: 'বাইক, সিএনজি বা কার — কাছের ড্রাইভার এসে নিয়ে যাবেন',
          subtitleEn: 'Bike, CNG or car — a nearby driver picks you up',
          icon: Icons.bolt_rounded,
        ),
        scheduled: _HubOption(
          titleBn: 'কমিউট পার্টনার',
          titleEn: 'Commute Partner',
          subtitleBn: 'রোজ একই পথে যাতায়াত? খরচ ভাগ করে নেওয়ার সঙ্গী খুঁজুন',
          subtitleEn: 'Same route every day? Find a partner and share the cost',
          icon: Icons.groups_rounded,
        ),
      ));

  bool get _isRide => config.emoji == '🛵';

  void _openInstant(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRequestScreen(
        serviceKind: _isRide ? 'commute' : 'cook',
        serviceLabel: _isRide ? 'রাইড' : 'রাঁধুনি',
      ),
    ));
  }

  void _openScheduled(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _isRide ? const CommuteScreen() : const CookScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      appBar: AppBar(
        title: Text(isBn ? config.titleBn : config.titleEn),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AnimatedBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(config.emoji, style: const TextStyle(fontSize: 56)),
                ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 8),
                Text(
                  isBn ? 'কীভাবে নিতে চান?' : 'How would you like it?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
                ).animate(delay: 80.ms).fadeIn(),
                const SizedBox(height: 24),
                _buildOption(context, config.instant, isBn, isPrimary: true,
                    onTap: () => _openInstant(context), delayMs: 140),
                const SizedBox(height: 14),
                _buildOption(context, config.scheduled, isBn, isPrimary: false,
                    onTap: () => _openScheduled(context), delayMs: 220),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    _HubOption option,
    bool isBn, {
    required bool isPrimary,
    required VoidCallback onTap,
    required int delayMs,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        glassColor: isPrimary ? AppColors.glassBlue : null,
        borderColor: isPrimary ? AppColors.glassBorderBlue : null,
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: isPrimary ? AppColors.blueGradient : AppColors.fuchsiaGradient,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(option.icon, color: AppColors.ivory, size: 25),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBn ? option.titleBn : option.titleEn,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isBn ? option.subtitleBn : option.subtitleEn,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.deepBlue, size: 15),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: delayMs)).fadeIn().slideY(begin: 0.1);
  }
}

class _HubConfig {
  final String titleBn;
  final String titleEn;
  final String emoji;
  final _HubOption instant;
  final _HubOption scheduled;

  const _HubConfig({
    required this.titleBn,
    required this.titleEn,
    required this.emoji,
    required this.instant,
    required this.scheduled,
  });
}

class _HubOption {
  final String titleBn;
  final String titleEn;
  final String subtitleBn;
  final String subtitleEn;
  final IconData icon;

  const _HubOption({
    required this.titleBn,
    required this.titleEn,
    required this.subtitleBn,
    required this.subtitleEn,
    required this.icon,
  });
}
