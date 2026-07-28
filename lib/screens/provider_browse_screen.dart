import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/matchmaking_model.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import 'provider_profile_screen.dart';

class ProviderBrowseScreen extends StatefulWidget {
  final String kind;
  final String label;
  const ProviderBrowseScreen({super.key, required this.kind, required this.label});

  @override
  State<ProviderBrowseScreen> createState() => _ProviderBrowseScreenState();
}

class _ProviderBrowseScreenState extends State<ProviderBrowseScreen> {
  List<MatchProviderModel> _providers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; });
    try {
      final list = await MatchmakingService.instance.listProviders(kind: widget.kind);
      if (mounted) setState(() { _providers = list; _isLoading = false; });
    } catch (_) {
      // API not available yet — show empty state instead of error.
      if (mounted) setState(() { _providers = []; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                    : _providers.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                                onRefresh: _load,
                                color: AppColors.deepBlue,
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  itemCount: _providers.length,
                                  itemBuilder: (_, i) => _buildProviderCard(_providers[i], i),
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              Text('${_providers.length} জন Provider পাওয়া গেছে', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _buildProviderCard(MatchProviderModel p, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
              child: Center(
                child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.ivory, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                if (p.bio?.isNotEmpty ?? false)
                  Text(p.bio!, style: TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(children: [
                  if (p.rating != null) ...[
                    const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 14),
                    const SizedBox(width: 3),
                    Text(p.rating!.toStringAsFixed(1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                  ],
                  if (p.totalReviews != null)
                    Text('(${p.totalReviews} রিভিউ)', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProviderProfileScreen(providerId: p.id, kind: widget.kind),
              )),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(10)),
                child: const Text('বই করুন', style: TextStyle(color: AppColors.ivory, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1);
  }


  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_search_rounded, color: AppColors.textMuted, size: 56),
        const SizedBox(height: 16),
        Text(
          '${widget.label} এর জন্য এখনো কোনো Provider নেই',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'শীঘ্রই এই সেবা চালু হবে। আমাদের সাথে থাকুন।',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ]),
    ),
  );
}
