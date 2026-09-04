import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/onboarding_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'photographer_profile_screen.dart' show sectionCard, labeledField, uploadRow;

/// Makeup-artist-only supplementary profile — portfolio drive link, a fixed
/// multi-select specialization chip set (bridal/party/hairstyling etc — no
/// longer free text), optional course certificate, years of experience,
/// achievements, an optional admin-only social media page link, and a
/// mandatory hourly-vs-package pricing mode with a rate range for whichever
/// mode(s) are chosen. Previously the makeup_artist serviceType was wrongly
/// routed to the bare portfolio-image uploader (nid.uploadPortfolioImage) in
/// the gateway's patternMap — no live caller ever depended on that (portfolio
/// uploads are only wired for photography/cinema), so it has been replaced
/// with a proper structured profile (nid.submitMakeupArtistProfile,
/// ProviderMakeupArtistProfile) matching what photographer/cinema already
/// get. Reachable from the provider dashboard's "My Services" list once the
/// makeup-artist application is approved.
class MakeupArtistProfileScreen extends StatefulWidget {
  const MakeupArtistProfileScreen({super.key});

  @override
  State<MakeupArtistProfileScreen> createState() => _MakeupArtistProfileScreenState();
}

/// Fixed set of specializations a makeup artist can offer — replaces the old
/// free-text tag list per the founder's explicit request for a chip
/// multi-select instead of arbitrary text.
const _specializationOptions = [
  'MAKEUP', 'BRIDAL_MAKEUP', 'PARTY_MAKEUP', 'HAIRSTYLING', 'PEDICURE',
  'MANICURE', 'FACIAL', 'SKIN_CARE', 'MEHENDI', 'NAIL_ART',
];

String _specializationLabel(String code, bool isBn) {
  const bn = {
    'MAKEUP': 'মেকআপ',
    'BRIDAL_MAKEUP': 'ব্রাইডাল মেকআপ',
    'PARTY_MAKEUP': 'পার্টি মেকআপ',
    'HAIRSTYLING': 'হেয়ারস্টাইল',
    'PEDICURE': 'পেডিকিউর',
    'MANICURE': 'মেনিকিউর',
    'FACIAL': 'ফেসিয়াল',
    'SKIN_CARE': 'স্কিন কেয়ার',
    'MEHENDI': 'মেহেদী',
    'NAIL_ART': 'নেইল আর্ট',
  };
  const en = {
    'MAKEUP': 'Makeup',
    'BRIDAL_MAKEUP': 'Bridal Makeup',
    'PARTY_MAKEUP': 'Party Makeup',
    'HAIRSTYLING': 'Hairstyling',
    'PEDICURE': 'Pedicure',
    'MANICURE': 'Manicure',
    'FACIAL': 'Facial',
    'SKIN_CARE': 'Skin Care',
    'MEHENDI': 'Mehendi',
    'NAIL_ART': 'Nail Art',
  };
  return isBn ? (bn[code] ?? code) : (en[code] ?? code);
}

class _MakeupArtistProfileScreenState extends State<MakeupArtistProfileScreen> {
  final _sampleDriveCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _achievementsCtrl = TextEditingController();
  final _socialPageCtrl = TextEditingController();
  final _hourlyMinCtrl = TextEditingController();
  final _hourlyMaxCtrl = TextEditingController();
  final _packageMinCtrl = TextEditingController();
  final _packageMaxCtrl = TextEditingController();
  final Set<String> _specializations = {};
  String? _certificateUrl;
  bool _uploadingCertificate = false;
  bool _pricingHourly = false;
  bool _pricingPackage = false;
  bool _submitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _sampleDriveCtrl.dispose();
    _experienceCtrl.dispose();
    _achievementsCtrl.dispose();
    _socialPageCtrl.dispose();
    _hourlyMinCtrl.dispose();
    _hourlyMaxCtrl.dispose();
    _packageMinCtrl.dispose();
    _packageMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _uploadCertificate() async {
    setState(() => _uploadingCertificate = true);
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final ext = f.name.split('.').last.toLowerCase();
      final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
      final url = await OnboardingService.instance.uploadFile(fileBase64: base64Encode(bytes), fileName: f.name, mimeType: mime);
      if (mounted) setState(() => _certificateUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingCertificate = false);
    }
  }

  double? _parseRate(String text) => double.tryParse(text.trim());

  Future<void> _submit() async {
    if (_sampleDriveCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'পোর্টফোলিও Drive লিংক দিন' : 'Add your portfolio drive link', error: true);
      return;
    }
    if (_specializations.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি বিশেষত্ব নির্বাচন করুন' : 'Select at least one specialization', error: true);
      return;
    }
    final years = int.tryParse(_experienceCtrl.text.trim());
    if (years == null || years < 0) {
      _snack(_isBn ? 'অভিজ্ঞতার বছর সঠিকভাবে দিন' : 'Enter valid years of experience', error: true);
      return;
    }
    if (!_pricingHourly && !_pricingPackage) {
      _snack(_isBn ? 'ঘণ্টাভিত্তিক বা প্যাকেজভিত্তিক কাজ — অন্তত একটি নির্বাচন করুন' : 'Select at least one pricing mode — hourly or package', error: true);
      return;
    }
    double? hourlyMin, hourlyMax, packageMin, packageMax;
    if (_pricingHourly) {
      hourlyMin = _parseRate(_hourlyMinCtrl.text);
      hourlyMax = _parseRate(_hourlyMaxCtrl.text);
      if (hourlyMin == null || hourlyMax == null || hourlyMin < 0 || hourlyMax < hourlyMin) {
        _snack(_isBn ? 'ঘণ্টাভিত্তিক সঠিক সর্বনিম্ন ও সর্বোচ্চ রেট দিন' : 'Enter a valid hourly rate range', error: true);
        return;
      }
    }
    if (_pricingPackage) {
      packageMin = _parseRate(_packageMinCtrl.text);
      packageMax = _parseRate(_packageMaxCtrl.text);
      if (packageMin == null || packageMax == null || packageMin < 0 || packageMax < packageMin) {
        _snack(_isBn ? 'প্যাকেজভিত্তিক সঠিক সর্বনিম্ন ও সর্বোচ্চ রেট দিন' : 'Enter a valid package rate range', error: true);
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitMakeupArtistProfile(
        sampleDriveUrl: _sampleDriveCtrl.text.trim(),
        specializations: _specializations.toList(),
        certificateUrl: _certificateUrl,
        experienceYears: years,
        achievements: _achievementsCtrl.text.trim(),
        socialPageUrl: _socialPageCtrl.text.trim().isEmpty ? null : _socialPageCtrl.text.trim(),
        pricingHourly: _pricingHourly,
        pricingPackage: _pricingPackage,
        hourlyRateMin: hourlyMin,
        hourlyRateMax: hourlyMax,
        packageRateMin: packageMin,
        packageRateMax: packageMax,
      );
      if (!mounted) return;
      _snack(_isBn ? 'মেকআপ প্রোফাইল সংরক্ষিত হয়েছে' : 'Makeup profile saved');
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

  Widget _pricingModeChip({required String label, required bool active, required VoidCallback onTap}) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? AppGradients.primary(colors) : null,
            color: active ? null : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? colors.primary : colors.outlineVariant, width: active ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(active ? Icons.check_circle_rounded : Icons.circle_outlined, size: 16, color: active ? Colors.white : colors.outline),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? Colors.white : colors.onSurfaceVariant, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      );
  }

  Widget _rateRangeRow({required String label, required TextEditingController minCtrl, required TextEditingController maxCtrl}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: labeledField(colors: colors, controller: minCtrl, hint: _isBn ? 'সর্বনিম্ন ৳' : 'Min ৳', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 8),
            Expanded(child: labeledField(colors: colors, controller: maxCtrl, hint: _isBn ? 'সর্বোচ্চ ৳' : 'Max ৳', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          ]),
        ]),
      );
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(children: [
                  IconButton(icon: Icon(Icons.arrow_back_rounded, color: colors.onSurface), onPressed: () => Navigator.of(context).pop()),
                  Text(_isBn ? 'মেকআপ প্রোফাইল' : 'Makeup Profile', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'পোর্টফোলিও' : 'Portfolio',
                      child: labeledField(colors: colors, 
                        controller: _sampleDriveCtrl,
                        hint: _isBn ? 'Google Drive / Dropbox লিংক' : 'Google Drive / Dropbox link',
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'বিশেষত্ব' : 'Specializations',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _specializationOptions.map((code) {
                          final active = _specializations.contains(code);
                          return GestureDetector(
                            onTap: () => setState(() => active ? _specializations.remove(code) : _specializations.add(code)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: active ? AppGradients.primary(colors) : null,
                                color: active ? null : colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: active ? colors.primary : colors.outlineVariant, width: active ? 1.5 : 1),
                              ),
                              child: Text(_specializationLabel(code, _isBn), style: TextStyle(color: active ? Colors.white : colors.onSurfaceVariant, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'সার্টিফিকেট (ঐচ্ছিক)' : 'Certificate (optional)',
                      child: uploadRow(colors: colors, 
                        label: _certificateUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'বিউটিশিয়ান/মেকআপ কোর্স সার্টিফিকেট আপলোড করুন' : 'Upload your beautician/makeup course certificate'),
                        uploaded: _certificateUrl != null,
                        loading: _uploadingCertificate,
                        onTap: _uploadCertificate,
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'অভিজ্ঞতা' : 'Experience',
                      child: labeledField(colors: colors, controller: _experienceCtrl, hint: _isBn ? 'অভিজ্ঞতার বছর' : 'Years of experience', keyboardType: TextInputType.number),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'কাজের ধরন — ঘণ্টাভিত্তিক / প্যাকেজ' : 'Pricing mode — hourly / package',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _isBn ? 'আপনি কীভাবে কাজ করেন তা নির্বাচন করুন (একটি বা উভয়ই)' : 'Choose how you work (one or both)',
                          style: TextStyle(color: colors.outline, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _pricingModeChip(
                            label: _isBn ? 'ঘণ্টাভিত্তিক' : 'Hourly',
                            active: _pricingHourly,
                            onTap: () => setState(() => _pricingHourly = !_pricingHourly),
                          ),
                          _pricingModeChip(
                            label: _isBn ? 'প্যাকেজ' : 'Package',
                            active: _pricingPackage,
                            onTap: () => setState(() => _pricingPackage = !_pricingPackage),
                          ),
                        ]),
                        if (_pricingHourly)
                          _rateRangeRow(label: _isBn ? 'ঘণ্টাভিত্তিক রেট (৳)' : 'Hourly rate (৳)', minCtrl: _hourlyMinCtrl, maxCtrl: _hourlyMaxCtrl),
                        if (_pricingPackage)
                          _rateRangeRow(label: _isBn ? 'প্যাকেজ রেট (৳)' : 'Package rate (৳)', minCtrl: _packageMinCtrl, maxCtrl: _packageMaxCtrl),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'সোশ্যাল মিডিয়া পেজ (ঐচ্ছিক, শুধু অ্যাডমিন দেখবে)' : 'Social media page (optional, admin-only)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _isBn ? 'এই লিংক শুধুমাত্র অ্যাডমিন রিভিউতে দেখা যাবে — কাস্টমারদের কাছে কখনো প্রদর্শিত হবে না।' : 'Only visible to KiChaai admins for review — never shown on your customer-facing profile.',
                          style: TextStyle(color: colors.outline, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        labeledField(colors: colors, 
                          controller: _socialPageCtrl,
                          hint: _isBn ? 'Facebook / Instagram পেজ লিংক' : 'Facebook / Instagram page link',
                          keyboardType: TextInputType.url,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'অর্জন (ঐচ্ছিক)' : 'Achievements (optional)',
                      child: TextField(
                        controller: _achievementsCtrl,
                        maxLines: 3,
                        style: TextStyle(color: colors.onSurface, fontSize: 14),
                        decoration: InputDecoration(hintText: _isBn ? 'পুরস্কার, প্রদর্শনী, উল্লেখযোগ্য কাজ...' : 'Awards, exhibitions, notable work...'),
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
}
