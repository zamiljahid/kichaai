import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_gradients.dart';
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
  List<Map<String, dynamic>> _services = [];
  final Set<String> _selected = {};
  final Set<String> _selectedServices = {};
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
      final pp = me['providerProfile'];
      final legalRole = pp is Map ? pp['legalRole'] as String? : null;
      final opts = await OnboardingService.instance.getLegalOptions(role: legalRole);
      if (!mounted) return;
      final existingAreas = (pp is Map ? pp['legalAreas'] : null) as List?;
      final existingServices = (pp is Map ? pp['legalServices'] : null) as List?;
      setState(() {
        _areas = (opts['areas'] as List? ?? []).cast<Map<String, dynamic>>();
        _services = (opts['services'] as List? ?? []).cast<Map<String, dynamic>>();
        _selected
          ..clear()
          ..addAll((existingAreas ?? const <dynamic>[]).whereType<String>());
        _selectedServices
          ..clear()
          ..addAll((existingServices ?? const <dynamic>[]).whereType<String>());
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
    if (_selected.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি এরিয়া নির্বাচন করুন' : 'Select at least one area', error: true);
      return;
    }
    if (_selectedServices.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি সেবা নির্বাচন করুন' : 'Select at least one service', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final persistedAreas =
          await AuthService.instance.updateLegalAreas(_selected.toList());
      final persistedServices =
          await AuthService.instance.updateLegalServices(_selectedServices.toList());
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(persistedAreas);
        _selectedServices
          ..clear()
          ..addAll(persistedServices);
        _saving = false;
      });
      _snack(_isBn ? 'সংরক্ষিত হয়েছে' : 'Saved');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(_isBn ? 'সংরক্ষণ ব্যর্থ: ${ApiClient.mapError(e).localized(_isBn)}' : 'Save failed: ${ApiClient.mapError(e).localized(_isBn)}', error: true);
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: colors.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              _isBn ? 'আমার প্র্যাকটিস এরিয়া' : 'My Practice Areas',
              style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
          ),
          if (!_loading && _error == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_selected.length}',
                style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChipWrap(List<Map<String, dynamic>> options, Set<String> selectedSet) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((a) {
        final code = a['code'] as String? ?? '';
        final label = (_isBn ? a['bn'] as String? : a['en'] as String?) ?? a['bn'] as String? ?? a['name'] as String? ?? code;
        final isSelected = selectedSet.contains(code);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSelected) {
              selectedSet.remove(code);
            } else {
              selectedSet.add(code);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: isSelected ? AppGradients.primary(colors) : null,
              color: isSelected ? null : colors.surface,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isSelected ? colors.primary : colors.outlineVariant,
                width: 1.5,
              ),
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
                    color: isSelected ? Colors.white : colors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody() {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: colors.primary));
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
                  style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              GlassButton(
                  label: _isBn ? 'আবার চেষ্টা করুন' : 'Try again', isOutlined: true, onPressed: _load),
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
                    color: colors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.gavel_rounded,
                      color: colors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isBn
                        ? 'যেসব বিষয়ে মামলা/পরামর্শ নেন সেগুলো টিক দিন — শুধু এই বিষয়ের অনুরোধই আপনার কাছে যাবে।'
                        : 'Tick the areas you take cases/consultations in — only requests for these will reach you.',
                    style: TextStyle(
                        color: colors.onSurfaceVariant,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isBn ? 'বিষয় (এরিয়া)' : 'Areas',
                  style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _buildChipWrap(_areas, _selected),
                const SizedBox(height: 22),
                Text(
                  _isBn ? 'নির্দিষ্ট সেবা' : 'Specific services',
                  style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _isBn
                      ? 'শুধু টিক দেওয়া সেবার অনুরোধই আপনার কাছে আসবে (যেমন জামিন আবেদন)।'
                      : 'Only requests for the ticked services will reach you (e.g. bail application).',
                  style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4),
                ),
                const SizedBox(height: 10),
                _buildChipWrap(_services, _selectedServices),
              ],
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
}
