import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/matchmaking_model.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';

/// Provider-side "pull" screen for matchmaking — browse open tutor/pet-care/mess
/// requests and respond to them. Previously this half of the pull-based system had
/// no screen at all: customers could create requests but no provider could ever see
/// or respond to one through the app.
class MatchRequestsInboxScreen extends StatefulWidget {
  const MatchRequestsInboxScreen({super.key});

  @override
  State<MatchRequestsInboxScreen> createState() => _MatchRequestsInboxScreenState();
}

class _MatchRequestsInboxScreenState extends State<MatchRequestsInboxScreen> {
  static const _typeFilters = [
    (null, 'সব'),
    ('tutor', 'হোম টিউটর'),
    ('pet_care', 'পেট কেয়ার'),
    ('mess_finder', 'মেস/আবাসন'),
  ];
  static const _typeLabels = {
    'tutor': 'হোম টিউটর',
    'pet_care': 'পেট কেয়ার',
    'mess_finder': 'মেস/আবাসন',
  };

  String? _selectedType;
  List<MatchRequestModel> _requests = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _loadError = null; });
    try {
      final list = await MatchmakingService.instance.listRequests(
        requestType: _selectedType,
        status: 'open',
      );
      if (mounted) setState(() { _requests = list; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _isLoading = false; });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes} মিনিট আগে';
    if (diff.inHours < 24) return '${diff.inHours} ঘণ্টা আগে';
    return '${diff.inDays} দিন আগে';
  }

  void _openResponseSheet(MatchRequestModel request) {
    final coverController = TextEditingController();
    final amountController = TextEditingController();
    String amountType = 'monthly';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.bgMid,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(request.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(request.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
                const SizedBox(height: 18),
                const Text('আপনার বার্তা', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: coverController,
                  maxLines: 3,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(hintText: 'নিজের সম্পর্কে ও অভিজ্ঞতা লিখুন...'),
                ),
                const SizedBox(height: 14),
                const Text('আপনার মূল্য (৳)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'যেমন ৩০০০',
                    prefixIcon: Icon(Icons.currency_exchange_rounded, color: AppColors.textMuted, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ('fixed', 'একবার'),
                    ('hourly', 'প্রতি ঘণ্টা'),
                    ('monthly', 'মাসিক'),
                  ].map((opt) {
                    final active = amountType == opt.$1;
                    return GestureDetector(
                      onTap: () => setSheetState(() => amountType = opt.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: active ? AppColors.blueGradient : null,
                          color: active ? null : AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder),
                        ),
                        child: Text(opt.$2, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                GlassButton(
                  label: 'রেসপন্স পাঠান',
                  isLoading: isSubmitting,
                  onPressed: () async {
                    setSheetState(() => isSubmitting = true);
                    try {
                      await MatchmakingService.instance.createResponse(
                        request.id,
                        coverMessage: coverController.text.trim().isEmpty ? null : coverController.text.trim(),
                        quotedAmount: double.tryParse(amountController.text.trim()),
                        quotedAmountType: amountType,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showInfo('আপনার রেসপন্স পাঠানো হয়েছে!');
                      _load();
                    } catch (e) {
                      setSheetState(() => isSubmitting = false);
                      _showError(e.toString());
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              _buildFilterChips(),
              const SizedBox(height: 10),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ম্যাচ অনুরোধ', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('টিউটর • পেট কেয়ার • মেস', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _typeFilters.map((f) {
          final active = _selectedType == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () { setState(() => _selectedType = f.$1); _load(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: active ? AppColors.blueGradient : null,
                  color: active ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                ),
                child: Text(f.$2, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    if (_loadError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('লোড করা যায়নি: $_loadError', style: const TextStyle(color: AppColors.textMuted, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          TextButton(onPressed: _load, child: const Text('আবার চেষ্টা করুন', style: TextStyle(color: AppColors.deepBlue))),
        ]),
      );
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Text('এই মুহূর্তে কোনো খোলা অনুরোধ নেই', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.deepBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _requests.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _openResponseSheet(_requests[i]),
            child: _buildRequestCard(_requests[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(MatchRequestModel r) {
    final budget = r.budgetMin != null || r.budgetMax != null
        ? '৳${(r.budgetMin ?? r.budgetMax)!.toStringAsFixed(0)}${r.budgetMax != null && r.budgetMin != null && r.budgetMax != r.budgetMin ? '-${r.budgetMax!.toStringAsFixed(0)}' : ''}'
        : null;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.deepBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(_typeLabels[r.requestType] ?? r.requestType, style: const TextStyle(color: AppColors.deepBlue, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            Text(_timeAgo(r.createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Text(r.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          Row(children: [
            if (budget != null) ...[
              const Icon(Icons.currency_exchange_rounded, color: AppColors.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(budget, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
            ],
            const Icon(Icons.people_outline_rounded, color: AppColors.textMuted, size: 14),
            const SizedBox(width: 4),
            Text('${r.responseCount}/${r.maxResponses} রেসপন্স', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}
