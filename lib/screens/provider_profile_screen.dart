import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/matchmaking_model.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'match_request_screen.dart';

class ProviderProfileScreen extends StatefulWidget {
  final String providerId;
  final String kind;
  const ProviderProfileScreen({super.key, required this.providerId, required this.kind});

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  MatchProviderModel? _provider;
  bool _isLoading = true;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await MatchmakingService.instance.getProvider(widget.providerId);
      if (mounted) setState(() { _provider = p; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              if (_isLoading)
                Expanded(child: Center(child: CircularProgressIndicator(color: colors.primary)))
              else if (_provider == null)
                Expanded(child: Center(child: Text(_isBn ? 'তথ্য পাওয়া যায়নি' : 'Information not found', style: TextStyle(color: colors.outline))))
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(children: [
                      _buildProfileCard(_provider!),
                      const SizedBox(height: 16),
                      if (widget.kind == 'tutor' && (_provider!.subjectsTaught.isNotEmpty || _provider!.teachingLevels.isNotEmpty)) ...[
                        _buildTutorInfoCard(_provider!),
                        const SizedBox(height: 16),
                      ],
                      if (_provider!.bio?.isNotEmpty ?? false) _buildBioCard(_provider!),
                      if (_provider!.specialNote?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 16),
                        _buildSpecialNoteCard(_provider!),
                      ],
                      if (_provider!.portfolioImages.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildPortfolioGrid(_provider!),
                      ],
                      const SizedBox(height: 24),
                      GlassButton(
                        label: _isBn ? 'অনুরোধ পাঠান' : 'Send request',
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MatchRequestScreen(providerId: widget.providerId, kind: widget.kind),
                        )),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.outlineVariant, width: 1.5)),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Text(_isBn ? 'Provider প্রোফাইল' : 'Provider Profile', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildProfileCard(MatchProviderModel p) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(gradient: AppGradients.primary(colors), shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: colors.primary.withOpacity(0.4), blurRadius: 20)]),
            child: Center(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
              style: TextStyle(color: colors.onPrimary, fontSize: 34, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(height: 14),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(p.name, style: TextStyle(color: colors.onSurface, fontSize: 20, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            if (p.nidVerified) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 20),
            ],
          ]),
          if (p.nidVerified) ...[
            const SizedBox(height: 4),
            Text(_isBn ? 'NID যাচাইকৃত' : 'NID Verified', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (p.rating != null) ...[
              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 18),
              const SizedBox(width: 4),
              Text(p.rating!.toStringAsFixed(1), style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
            ],
            if (p.totalReviews != null)
              Text(_isBn ? '(${p.totalReviews} রিভিউ)' : '(${p.totalReviews} reviews)', style: TextStyle(color: colors.outline, fontSize: 12)),
          ]),
          if (p.totalJobs != null) ...[
            const SizedBox(height: 4),
            Text(_isBn ? '${p.totalJobs} কাজ সম্পন্ন' : '${p.totalJobs} jobs completed', style: TextStyle(color: colors.outline, fontSize: 12)),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildTutorInfoCard(MatchProviderModel p) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p.subjectsTaught.isNotEmpty) ...[
          Text(_isBn ? 'যে বিষয়ে পড়ান' : 'Subjects taught', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: p.subjectsTaught.map((s) => _infoChip(s)).toList()),
        ],
        if (p.teachingLevels.isNotEmpty) ...[
          if (p.subjectsTaught.isNotEmpty) const SizedBox(height: 14),
          Text(_isBn ? 'যে লেভেলে পড়ান' : 'Levels taught', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: p.teachingLevels.map((s) => _infoChip(s)).toList()),
        ],
      ]),
    ).animate(delay: 50.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _infoChip(String label) {
    final colors = Theme.of(context).colorScheme;
    return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: colors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
    child: Text(label, style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
  );
  }

  Widget _buildBioCard(MatchProviderModel p) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isBn ? 'পরিচিতি' : 'About', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(p.bio!, style: TextStyle(color: colors.onSurface, fontSize: 14, height: 1.6)),
      ]),
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _buildSpecialNoteCard(MatchProviderModel p) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 16),
          const SizedBox(width: 6),
          Text(_isBn ? 'বিশেষ দক্ষতা' : 'Especially good at', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(p.specialNote!, style: TextStyle(color: colors.onSurface, fontSize: 14, height: 1.6)),
      ]),
    ).animate(delay: 120.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _buildPortfolioGrid(MatchProviderModel p) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isBn ? 'পোর্টফোলিও' : 'Portfolio', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: p.portfolioImages.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(p.portfolioImages[i], fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: colors.surface,
                child: Icon(Icons.image_rounded, color: colors.outline))),
          ),
        ),
      ]),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.05);
  }
}
