import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// Lawyer — "আমার প্র্যাকটিস এরিয়া" (edit after onboarding).
///
/// Consultation broadcasts route by these areas, so a lawyer who stops (or
/// starts) taking family cases must be able to change them without redoing
/// onboarding. Options come from GET /legal/options (never hard-code);
/// saves via PATCH /auth/provider-profile/legal-areas (JWT).
class LawyerAreasScreen extends StatefulWidget {
  const LawyerAreasScreen({super.key});

  @override
  State<LawyerAreasScreen> createState() => _LawyerAreasScreenState();
}

class _LawyerAreasScreenState extends State<LawyerAreasScreen> {
  List<Map<String, dynamic>> _areas = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
      final results = await Future.wait([
        OnboardingService.instance.getLegalOptions(),
        AuthService.instance.getMeRaw(),
      ]);
      if (!mounted) return;
      final opts = results[0];
      final me = results[1];
      final pp = me['providerProfile'];
      final existing = (pp is Map ? pp['legalAreas'] : null) as List?;
      setState(() {
        _areas = (opts['areas'] as List? ?? []).cast<Map<String, dynamic>>();
        _selected
          ..clear()
          ..addAll((existing ?? const <dynamic>[]).whereType<String>());
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      _snack('অন্তত একটি এরিয়া নির্বাচন করুন', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final persisted =
          await AuthService.instance.updateLegalAreas(_selected.toList());
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(persisted);
        _saving = false;
      });
      _snack('সংরক্ষিত হয়েছে — ${persisted.length} টি এরিয়া');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack('সংরক্ষণ ব্যর্থ: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor:
          error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'আমার প্র্যাকটিস এরিয়া',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
          ),
          if (!_loading && _error == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.deepBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_selected.length}',
                style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              GlassButton(
                  label: 'আবার চেষ্টা করুন', isOutlined: true, onPressed: _load),
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
                    color: AppColors.deepBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.gavel_rounded,
                      color: AppColors.deepBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'যেসব বিষয়ে মামলা/পরামর্শ নেন সেগুলো টিক দিন — শুধু এই বিষয়ের অনুরোধই আপনার কাছে যাবে।',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _areas.map((a) {
                final code = a['code'] as String? ?? '';
                final label = a['bn'] as String? ?? a['name'] as String? ?? code;
                final isSelected = _selected.contains(code);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isSelected) {
                      _selected.remove(code);
                    } else {
                      _selected.add(code);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: isSelected ? AppColors.blueGradient : null,
                      color: isSelected ? null : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.deepBlue
                            : AppColors.glassBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          const Icon(Icons.check_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: GlassButton(
            label: 'সংরক্ষণ করুন',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}
