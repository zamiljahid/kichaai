import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'photographer_profile_screen.dart' show sectionCard, labeledField;

/// Quick-help-only supplementary profile — institution/school affiliation
/// (optional context) + a free-text list of tasks the provider can do. The
/// founder explicitly wants 4-5 separate text INPUT BOXES rather than a
/// fixed dropdown, so this is 5 plain TextEditingControllers in a Column;
/// only the non-empty ones are sent as a List<String>, first one mandatory.
/// NID itself is already collected by the platform-wide generic onboarding
/// flow, so it is not repeated here. Reachable from the provider dashboard's
/// "My Services" list once the quick-help application is approved, same
/// pattern as PetCareProfileScreen.
class QuickHelpProfileScreen extends StatefulWidget {
  const QuickHelpProfileScreen({super.key});

  @override
  State<QuickHelpProfileScreen> createState() => _QuickHelpProfileScreenState();
}

class _QuickHelpProfileScreenState extends State<QuickHelpProfileScreen> {
  final _institutionCtrl = TextEditingController();
  final List<TextEditingController> _taskCtrls = List.generate(5, (_) => TextEditingController());
  bool _submitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _institutionCtrl.dispose();
    for (final c in _taskCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final tasks = _taskCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (tasks.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি কাজ উল্লেখ করুন' : 'Add at least one task', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitQuickHelpProfile(
        institution: _institutionCtrl.text.trim(),
        tasks: tasks,
      );
      if (!mounted) return;
      _snack(_isBn ? 'কুইক হেল্প প্রোফাইল সংরক্ষিত হয়েছে' : 'Quick help profile saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(children: [
                  IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary), onPressed: () => Navigator.of(context).pop()),
                  Text(_isBn ? 'কুইক হেল্প প্রোফাইল' : 'Quick Help Profile', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      title: _isBn ? 'কোন ইনস্টিটিউশনে পড়েন/কাজ করেন (ঐচ্ছিক)' : 'Institution / employer affiliation (optional)',
                      child: labeledField(
                        controller: _institutionCtrl,
                        hint: _isBn ? 'যেমন: ঢাকা কলেজ, XYZ কোম্পানি' : 'e.g. Dhaka College, XYZ Company',
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'কোন কোন কাজ করতে পারেন' : 'Tasks you can do',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (var i = 0; i < _taskCtrls.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          labeledField(
                            controller: _taskCtrls[i],
                            hint: i == 0
                                ? (_isBn ? 'কাজ ১ (আবশ্যক)' : 'Task 1 (required)')
                                : (_isBn ? 'কাজ ${i + 1} (ঐচ্ছিক)' : 'Task ${i + 1} (optional)'),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 22),
                    GlassButton(label: _isBn ? 'সংরক্ষণ করুন' : 'Save', isLoading: _submitting, onPressed: _submitting ? null : _submit),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
