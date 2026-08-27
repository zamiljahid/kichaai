import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/matchmaking_model.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import 'match_request_screen.dart';
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
  bool _isBn = true;

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

  void _postOpenRequest() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MatchRequestScreen(kind: widget.kind),
    ));
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              // Browsing only lets you book a SPECIFIC provider you can see — a customer whose
              // need doesn't match anyone here (or who'd rather have providers come to them) had
              // no way to just post what they need. The backend already supports an open
              // broadcast (no targetProviderId); this was the only missing entry point to it.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: GestureDetector(
                  onTap: _postOpenRequest,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: AppColors.blueGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: AppColors.deepBlue.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Row(children: [
                      const Icon(Icons.campaign_rounded, color: AppColors.ivory, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isBn ? 'সবাইকে জানিয়ে অনুরোধ পোস্ট করুন — যেকোনো সেবাদাতা সাড়া দিতে পারবেন' : 'Post an open request — any provider can respond',
                          style: const TextStyle(color: AppColors.ivory, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.ivory, size: 14),
                    ]),
                  ),
                ),
              ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08),
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
              Text(
                _isBn ? '${_providers.length} জন সেবাদাতা পাওয়া গেছে' : '${_providers.length} providers found',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ]),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _buildProviderCard(MatchProviderModel p, int index) {
    void openProfile() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProviderProfileScreen(providerId: p.id, kind: widget.kind),
        ));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: openProfile,
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
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
                    Row(children: [
                      Flexible(child: Text(p.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      if (p.nidVerified) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 15),
                      ],
                    ]),
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
                        Text(_isBn ? '(${p.totalReviews} রিভিউ)' : '(${p.totalReviews} reviews)', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      if (p.totalJobs != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.work_outline_rounded, color: AppColors.textMuted, size: 12),
                        const SizedBox(width: 3),
                        Text(_isBn ? '${p.totalJobs} কাজ সম্পন্ন' : '${p.totalJobs} jobs done', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ]),
                  ]),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: openProfile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(10)),
                    child: Text(_isBn ? 'বুক করুন' : 'Book', style: const TextStyle(color: AppColors.ivory, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            if (widget.kind == 'tutor' && (p.subjectsTaught.isNotEmpty || p.teachingLevels.isNotEmpty)) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ...p.subjectsTaught.map((s) => _infoChip(s, AppColors.deepBlue)),
                ...p.teachingLevels.map((l) => _infoChip(l, AppColors.fuchsia)),
              ]),
            ],
          ]),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1);
  }

  Widget _infoChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );


  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_search_rounded, color: AppColors.textMuted, size: 56),
        const SizedBox(height: 16),
        Text(
          _isBn ? '${widget.label} এর জন্য এখনো কোনো সেবাদাতা নেই' : 'No providers for ${widget.label} yet',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _isBn ? 'উপরের বাটন থেকে একটা অনুরোধ পোস্ট করুন — নতুন সেবাদাতা এলে সাড়া দিতে পারবেন।' : 'Post a request using the button above — providers will be able to respond once available.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ]),
    ),
  );
}
