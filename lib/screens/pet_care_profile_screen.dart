import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'photographer_profile_screen.dart' show sectionCard, labeledField;

/// Pet-care-only supplementary profile — pet types handled + years of
/// experience + bio, which the generic document-upload onboarding flow never
/// captures as structured fields. OnboardingService.submitPetCareProfile
/// already existed and posted correctly; this is the first screen that
/// actually calls it. Reachable from the provider dashboard's "My Services"
/// list once the pet-care application is approved, same pattern as
/// CaregiverProfileScreen.
class PetCareProfileScreen extends StatefulWidget {
  const PetCareProfileScreen({super.key});

  @override
  State<PetCareProfileScreen> createState() => _PetCareProfileScreenState();
}

const _petTypeOptions = ['DOG', 'CAT', 'BIRD', 'RABBIT', 'FISH'];

String petTypeLabel(String code, bool isBn) {
  const bn = {'DOG': 'কুকুর', 'CAT': 'বিড়াল', 'BIRD': 'পাখি', 'RABBIT': 'খরগোশ', 'FISH': 'মাছ'};
  const en = {'DOG': 'Dog', 'CAT': 'Cat', 'BIRD': 'Bird', 'RABBIT': 'Rabbit', 'FISH': 'Fish'};
  return isBn ? (bn[code] ?? code) : (en[code] ?? code);
}

// Services offered — separate from the pet TYPES above. Walking-vs-full-care
// is folded into this same list rather than kept as a second, independent
// field: the "care type" toggle below simply constrains this selection to
// ['walking'] alone or unlocks the full set, so the single `services` array
// the backend stores stays the one source of truth.
const _serviceOptions = ['walking', 'feeding', 'grooming', 'boarding', 'training', 'vet_visits', 'day_care'];

String serviceLabel(String code, bool isBn) {
  const bn = {
    'walking': 'হাঁটানো',
    'feeding': 'খাওয়ানো',
    'grooming': 'গ্রুমিং',
    'boarding': 'বোর্ডিং',
    'training': 'ট্রেনিং',
    'vet_visits': 'ভেট ভিজিট',
    'day_care': 'ডে কেয়ার',
  };
  const en = {
    'walking': 'Walking',
    'feeding': 'Feeding',
    'grooming': 'Grooming',
    'boarding': 'Boarding',
    'training': 'Training',
    'vet_visits': 'Vet Visits',
    'day_care': 'Day Care',
  };
  return isBn ? (bn[code] ?? code) : (en[code] ?? code);
}

class _PetCareProfileScreenState extends State<PetCareProfileScreen> {
  final _experienceCtrl = TextEditingController();
  final _rateMinCtrl = TextEditingController();
  final _rateMaxCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final Set<String> _petTypes = {};
  final Set<String> _services = {};
  // 'walking' = walking-only provider (services locked to ['walking']);
  // 'full' = full-care provider (may pick any combination of services).
  String _careType = 'full';
  bool _submitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _experienceCtrl.dispose();
    _rateMinCtrl.dispose();
    _rateMaxCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _setCareType(String type) {
    setState(() {
      _careType = type;
      if (type == 'walking') {
        _services..clear()..add('walking');
      } else {
        _services.remove('walking');
      }
    });
  }

  Future<void> _submit() async {
    if (_petTypes.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি প্রাণীর ধরন বেছে নিন' : 'Choose at least one pet type', error: true);
      return;
    }
    if (_services.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি সেবা বেছে নিন' : 'Choose at least one service', error: true);
      return;
    }
    final days = int.tryParse(_experienceCtrl.text.trim());
    if (days == null || days < 0) {
      _snack(_isBn ? 'অভিজ্ঞতার দিন সঠিকভাবে দিন' : 'Enter valid days of experience', error: true);
      return;
    }
    final rateMin = double.tryParse(_rateMinCtrl.text.trim());
    final rateMax = double.tryParse(_rateMaxCtrl.text.trim());
    if (rateMin == null || rateMax == null) {
      _snack(_isBn ? 'ঘণ্টাপ্রতি সর্বনিম্ন ও সর্বোচ্চ রেট দিন' : 'Enter minimum and maximum hourly rate', error: true);
      return;
    }
    if (rateMin < 0 || rateMax < 0 || rateMin > rateMax) {
      _snack(_isBn ? 'সর্বনিম্ন রেট সর্বোচ্চ রেটের চেয়ে বেশি হতে পারবে না' : 'Minimum rate cannot exceed maximum rate', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitPetCareProfile(
        petTypes: _petTypes.map((c) => petTypeLabel(c, true)).toList(),
        services: _services.toList(),
        hourlyRateMin: rateMin,
        hourlyRateMax: rateMax,
        experienceYears: days, // days of experience — see field label below
        bio: _bioCtrl.text.trim(),
      );
      if (!mounted) return;
      _snack(_isBn ? 'পেট কেয়ার প্রোফাইল সংরক্ষিত হয়েছে' : 'Pet care profile saved');
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
                  Text(_isBn ? 'পেট কেয়ার প্রোফাইল' : 'Pet Care Profile', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      title: _isBn ? 'কোন প্রাণীর যত্ন নেন' : 'Pet types you handle',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _petTypeOptions.map((code) {
                          final active = _petTypes.contains(code);
                          return GestureDetector(
                            onTap: () => setState(() => active ? _petTypes.remove(code) : _petTypes.add(code)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: active ? AppColors.blueGradient : null,
                                color: active ? null : const Color(0xFFF9F7F0),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                              ),
                              child: Text(petTypeLabel(code, _isBn), style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'সেবার ধরন' : 'Care type',
                      child: Row(
                        children: [
                          Expanded(child: _careTypeTab('walking', _isBn ? '🚶 শুধু হাঁটানো' : '🚶 Walking only')),
                          const SizedBox(width: 10),
                          Expanded(child: _careTypeTab('full', _isBn ? '🏡 সম্পূর্ণ যত্ন' : '🏡 Full care')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'কোন কোন সেবা দেন' : 'Services you offer',
                      child: _careType == 'walking'
                          ? Text(
                              _isBn ? 'শুধু হাঁটানো সেবা নির্বাচিত' : 'Walking-only service selected',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _serviceOptions.map((code) {
                                final active = _services.contains(code);
                                return GestureDetector(
                                  onTap: () => setState(() => active ? _services.remove(code) : _services.add(code)),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                                    decoration: BoxDecoration(
                                      gradient: active ? AppColors.blueGradient : null,
                                      color: active ? null : const Color(0xFFF9F7F0),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                                    ),
                                    child: Text(serviceLabel(code, _isBn), style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'ঘণ্টাপ্রতি রেট (৳)' : 'Hourly rate (৳)',
                      child: Row(
                        children: [
                          Expanded(child: labeledField(controller: _rateMinCtrl, hint: _isBn ? 'সর্বনিম্ন' : 'Minimum', keyboardType: TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: labeledField(controller: _rateMaxCtrl, hint: _isBn ? 'সর্বোচ্চ' : 'Maximum', keyboardType: TextInputType.number)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      // Founder's explicit framing: "কত দিনের" (how many days) —
                      // not years. Backend column is still named experienceYears
                      // to avoid a migration; only this label changed.
                      title: _isBn ? 'অভিজ্ঞতা (দিন)' : 'Experience (days)',
                      child: labeledField(controller: _experienceCtrl, hint: _isBn ? 'কত দিনের অভিজ্ঞতা' : 'How many days of experience', keyboardType: TextInputType.number),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'বায়ো (ঐচ্ছিক)' : 'Bio (optional)',
                      child: TextField(
                        controller: _bioCtrl,
                        maxLines: 3,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(hintText: _isBn ? 'নিজের সম্পর্কে সংক্ষেপে লিখুন...' : 'A short note about yourself...'),
                      ),
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

  Widget _careTypeTab(String type, String label) {
    final active = _careType == type;
    return GestureDetector(
      onTap: () => _setCareType(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: active ? AppColors.blueGradient : null,
          color: active ? null : const Color(0xFFF9F7F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.transparent : AppColors.glassBorder),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
