import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../services/dispatch_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';

/// Provider chooses, per task category they offer, whether to charge the
/// platform's FIXED rate (recommended) or give their own CUSTOM on-site quote.
class ProviderPricingScreen extends StatefulWidget {
  const ProviderPricingScreen({super.key});

  @override
  State<ProviderPricingScreen> createState() => _ProviderPricingScreenState();
}

class _ProviderPricingScreenState extends State<ProviderPricingScreen> {
  final _svc = DispatchService.instance;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rates = [];
  final Map<String, String> _mode = {}; // taskCategory -> FIXED | CUSTOM
  final Set<String> _saving = {};

  // Display names for the 15 task categories.
  static const _labelsBn = {
    'AC_SERVICE': 'এসি সার্ভিসিং',
    'REFRIGERATOR_REPAIR': 'ফ্রিজ মেরামত',
    'WASHING_MACHINE_REPAIR': 'ওয়াশিং মেশিন মেরামত',
    'PLUMBING': 'প্লাম্বিং',
    'ELECTRICAL': 'ইলেকট্রিক কাজ',
    'PAINTING': 'রং করা',
    'CARPENTRY': 'কাঠমিস্ত্রি',
    'TILES_WORK': 'টাইলসের কাজ',
    'COMPUTER_REPAIR': 'কম্পিউটার মেরামত',
    'MOBILE_REPAIR': 'মোবাইল মেরামত',
    'TV_REPAIR': 'টিভি মেরামত',
    'GENERAL_HANDYMAN': 'সাধারণ হ্যান্ডিম্যান',
    'CLEANING': 'পরিষ্কার-পরিচ্ছন্নতা',
    'PEST_CONTROL': 'পেস্ট কন্ট্রোল',
    'BABY_SITTING_SHORT': 'বেবি সিটিং (স্বল্পমেয়াদি)',
    'CAR_REPAIR': 'গাড়ি মেরামত',
    'MOTORCYCLE_REPAIR': 'মোটরসাইকেল মেরামত',
  };
  static const _labelsEn = {
    'AC_SERVICE': 'AC Servicing',
    'REFRIGERATOR_REPAIR': 'Refrigerator Repair',
    'WASHING_MACHINE_REPAIR': 'Washing Machine Repair',
    'PLUMBING': 'Plumbing',
    'ELECTRICAL': 'Electrical',
    'PAINTING': 'Painting',
    'CARPENTRY': 'Carpentry',
    'TILES_WORK': 'Tiles Work',
    'COMPUTER_REPAIR': 'Computer Repair',
    'MOBILE_REPAIR': 'Mobile Repair',
    'TV_REPAIR': 'TV Repair',
    'GENERAL_HANDYMAN': 'General Handyman',
    'CLEANING': 'Cleaning',
    'PEST_CONTROL': 'Pest Control',
    'BABY_SITTING_SHORT': 'Baby Sitting (short)',
    'CAR_REPAIR': 'Car Repair',
    'MOTORCYCLE_REPAIR': 'Motorcycle Repair',
  };
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _svc.getTaskCategoryRates(),
        _svc.getMyPricingPreferences(),
      ]);
      final rates = results[0];
      final prefs = results[1];
      _mode.clear();
      for (final p in prefs) {
        final cat = p['taskCategory'] as String?;
        final mode = p['mode'] as String?;
        if (cat != null && mode != null) _mode[cat] = mode;
      }
      if (mounted) {
        setState(() {
          _rates = rates;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _setMode(String category, String mode) async {
    if (_mode[category] == mode || _saving.contains(category)) return;
    setState(() => _saving.add(category));
    final prev = _mode[category];
    setState(() => _mode[category] = mode); // optimistic
    try {
      await _svc.setPricingPreference(taskCategory: category, mode: mode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              mode == 'FIXED'
                  ? (_isBn ? 'প্ল্যাটফর্ম রেট বেছে নেওয়া হয়েছে' : 'Platform rate selected')
                  : (_isBn ? 'নিজের কোট (CUSTOM) বেছে নেওয়া হয়েছে' : 'Own quote (CUSTOM) selected'),
              style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _mode[category] = prev ?? 'FIXED'); // revert
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString(), style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(category));
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant, width: 1.5),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isBn ? 'মূল্য নির্ধারণ' : 'Pricing', style: TextStyle(color: colors.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
                Text(_isBn ? 'Pricing preference' : 'মূল্য পছন্দ', style: TextStyle(color: colors.outline, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: colors.outline, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.outline)),
              const SizedBox(height: 16),
              TextButton(onPressed: _load, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again')),
            ],
          ),
        ),
      );
    }
    if (_rates.isEmpty) {
      return Center(child: Text(_isBn ? 'কোনো ক্যাটাগরি পাওয়া যায়নি' : 'No categories found', style: TextStyle(color: colors.outline)));
    }
    return RefreshIndicator(
      color: colors.primary,
      backgroundColor: colors.surface,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          _infoBanner(),
          const SizedBox(height: 16),
          ..._rates.asMap().entries.map((e) => _rateCard(e.value, e.key)),
        ],
      ),
    );
  }

  Widget _infoBanner() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.20), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: colors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isBn
                  ? 'FIXED = প্ল্যাটফর্মের নির্ধারিত দাম (সুপারিশকৃত)। CUSTOM = কাজ দেখে আপনি নিজে দাম দেবেন; গ্রাহক অনুমোদন করলে কাজ শুরু হবে।'
                  : 'FIXED = the platform-set price (recommended). CUSTOM = you quote your own price on-site; work starts once the customer approves.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rateCard(Map<String, dynamic> rate, int index) {
    final colors = Theme.of(context).colorScheme;
    final cat = rate['taskCategory'] as String? ?? '';
    final label = (_isBn ? _labelsBn : _labelsEn)[cat] ?? cat;
    final fixed = (rate['fixedPrice'] as num?)?.toStringAsFixed(0) ?? '—';
    final visit = (rate['visitingFee'] as num?)?.toStringAsFixed(0) ?? '—';
    final mode = _mode[cat] ?? 'FIXED';
    final busy = _saving.contains(cat);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (busy)
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _pricePill(Icons.payments_rounded, '${_isBn ? 'দাম' : 'Price'} ৳$fixed'),
                const SizedBox(width: 8),
                _pricePill(Icons.directions_car_rounded, '${_isBn ? 'ভিজিট' : 'Visit'} ৳$visit'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _modeButton(cat, 'FIXED', mode == 'FIXED', _isBn ? 'প্ল্যাটফর্ম রেট' : 'Platform rate')),
                const SizedBox(width: 10),
                Expanded(child: _modeButton(cat, 'CUSTOM', mode == 'CUSTOM', _isBn ? 'নিজের কোট' : 'Own quote')),
              ],
            ),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: 30 * index)).fadeIn(duration: 260.ms).slideY(begin: 0.05);
  }

  Widget _pricePill(IconData icon, String text) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.outline, size: 13),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _modeButton(String cat, String value, bool selected, String label) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _setMode(cat, value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? AppGradients.primary(colors) : null,
          color: selected ? null : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.transparent : colors.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(
              color: selected ? colors.onPrimary.withValues(alpha: 0.85) : colors.outline,
              fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
