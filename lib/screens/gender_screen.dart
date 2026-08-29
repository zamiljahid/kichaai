import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// caregiver/photographer/cinematographer/makeup_artist provider — "আমার Gender"
/// (set/update after onboarding).
///
/// A customer's gender preference on these 4 services is only a real filter once we
/// actually know the provider's real gender — the backend now also refuses to let a
/// provider go online for these kinds until this is set (see dispatch-service's
/// startLiveSession). Saves via PATCH /auth/provider-profile/gender (JWT); current
/// value comes from GET /auth/me's providerProfile.gender.
class GenderScreen extends StatefulWidget {
  const GenderScreen({super.key});

  @override
  State<GenderScreen> createState() => _GenderScreenState();
}

class _GenderScreenState extends State<GenderScreen> {
  String? _selected;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await AuthService.instance.getMeRaw();
      if (!mounted) return;
      final pp = me['providerProfile'];
      final existing = (pp is Map ? pp['gender'] : null) as String?;
      setState(() {
        _selected = (existing == 'male' || existing == 'female') ? existing : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiClient.mapError(e).localized(_isBn);
        });
      }
    }
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) {
      _snack(_isBn ? 'একটি অপশন নির্বাচন করুন' : 'Select an option', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final persisted = await AuthService.instance.updateGender(selected);
      if (!mounted) return;
      setState(() {
        _selected = persisted;
        _saving = false;
      });
      _snack(_isBn ? 'সংরক্ষিত হয়েছে' : 'Saved');
      Navigator.of(context).pop(persisted);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(_isBn ? 'সংরক্ষণ ব্যর্থ: ${ApiClient.mapError(e).localized(_isBn)}' : 'Save failed: ${ApiClient.mapError(e).localized(_isBn)}', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
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
              _buildAppBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              _isBn ? 'আমার Gender' : 'My Gender',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              GlassButton(label: _isBn ? 'আবার চেষ্টা করুন' : 'Try again', isOutlined: true, onPressed: _load),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.deepBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.wc_rounded, color: AppColors.deepBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isBn
                        ? 'ক্যায়ারগিভার/ফটোগ্রাফার/সিনেমাটোগ্রাফার/মেকআপ আর্টিস্ট সার্ভিসে গ্রাহক Gender পছন্দ উল্লেখ করতে পারেন — এটি সঠিকভাবে সেট না করলে অনলাইন হতে পারবেন না।'
                        : 'Customers on caregiver/photographer/cinematographer/makeup artist can state a gender preference — you can\'t go online for these without setting this.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.topLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _genderChip('male', _isBn ? 'পুরুষ' : 'Male'),
                  _genderChip('female', _isBn ? 'মহিলা' : 'Female'),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: GlassButton(
            label: _isBn ? 'সংরক্ষণ করুন' : 'Save',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }

  Widget _genderChip(String code, String label) {
    final isSelected = _selected == code;
    return GestureDetector(
      onTap: () => setState(() => _selected = code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.blueGradient : null,
          color: isSelected ? null : AppColors.glassWhite,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: isSelected ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
