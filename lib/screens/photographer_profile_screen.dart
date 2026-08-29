import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// Photographer-only supplementary gear profile — camera, lenses, equipment,
/// portfolio drive link — which the generic document-upload onboarding flow
/// never captures. OnboardingService.submitPhotographyProfile already existed
/// and posted correctly; this is the first screen that actually calls it.
/// Reachable from the provider dashboard's "My Services" list once the
/// photographer application is approved, same pattern as TutorProfileScreen.
class PhotographerProfileScreen extends StatefulWidget {
  const PhotographerProfileScreen({super.key});

  @override
  State<PhotographerProfileScreen> createState() => _PhotographerProfileScreenState();
}

const _cameraBrands = ['CANON', 'NIKON', 'SONY', 'FUJIFILM', 'PANASONIC', 'OLYMPUS', 'LEICA', 'HASSELBLAD', 'OTHER'];
const _lensBrands = ['CANON', 'NIKON', 'SONY', 'SIGMA', 'TAMRON', 'TOKINA', 'ZEISS', 'SAMYANG', 'OTHER'];
const _equipmentItems = [
  'TRIPOD', 'MONOPOD', 'GIMBAL', 'DRONE', 'SPEEDLIGHT', 'STUDIO_LIGHT', 'SOFTBOX', 'REFLECTOR',
  'ND_FILTER', 'POLARIZER_FILTER', 'CAMERA_BAG', 'MEMORY_CARD_FAST', 'EXTERNAL_RECORDER', 'SLIDER',
  'FOLLOW_FOCUS', 'MICROPHONE', 'STABILIZER', 'GREEN_SCREEN', 'BACKDROP',
];

const _shootTypeOptions = ['WEDDING', 'DOCUMENTARY', 'PORTRAIT', 'EVENT', 'COMMERCIAL', 'PRODUCT'];

String shootTypeLabel(String code, bool isBn) {
  const bn = {
    'WEDDING': 'বিয়ে', 'DOCUMENTARY': 'ডকুমেন্টারি', 'PORTRAIT': 'পোর্ট্রেট',
    'EVENT': 'ইভেন্ট', 'COMMERCIAL': 'কমার্শিয়াল', 'PRODUCT': 'প্রোডাক্ট', 'OTHER': 'অন্যান্য',
  };
  return isBn ? (bn[code] ?? code) : (code[0] + code.substring(1).toLowerCase());
}

String equipmentLabel(String code, bool isBn) {
  const bn = {
    'TRIPOD': 'ট্রাইপড', 'MONOPOD': 'মনোপড', 'GIMBAL': 'জিম্বাল', 'DRONE': 'ড্রোন',
    'SPEEDLIGHT': 'স্পিডলাইট', 'STUDIO_LIGHT': 'স্টুডিও লাইট', 'SOFTBOX': 'সফটবক্স', 'REFLECTOR': 'রিফ্লেক্টর',
    'ND_FILTER': 'ND ফিল্টার', 'POLARIZER_FILTER': 'পোলারাইজার ফিল্টার', 'CAMERA_BAG': 'ক্যামেরা ব্যাগ',
    'MEMORY_CARD_FAST': 'হাই-স্পিড মেমরি কার্ড', 'EXTERNAL_RECORDER': 'এক্সটার্নাল রেকর্ডার', 'SLIDER': 'স্লাইডার',
    'FOLLOW_FOCUS': 'ফলো ফোকাস', 'MICROPHONE': 'মাইক্রোফোন', 'STABILIZER': 'স্ট্যাবিলাইজার',
    'GREEN_SCREEN': 'গ্রিন স্ক্রিন', 'BACKDROP': 'ব্যাকড্রপ',
  };
  return isBn ? (bn[code] ?? code) : code.replaceAll('_', ' ').toLowerCase().split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class _LensRow {
  String brand = 'CANON';
  final focalLengthCtrl = TextEditingController();
}

class _PhotographerProfileScreenState extends State<PhotographerProfileScreen> {
  final _sampleDriveCtrl = TextEditingController();
  final _cameraModelCtrl = TextEditingController();
  final _achievementsCtrl = TextEditingController();
  String _cameraBrand = 'CANON';
  String? _cameraBodyPhotoUrl;
  bool _uploadingCameraPhoto = false;
  final List<_LensRow> _lenses = [];
  final Set<String> _equipment = {};
  bool _submitting = false;
  bool _isBn = true;

  // Years of experience — mandatory
  final _experienceYearsCtrl = TextEditingController();

  // Work locations — mandatory tag list
  final _workLocationCtrl = TextEditingController();
  final List<String> _workLocations = [];

  // Shoot types — mandatory chip multi-select + free-text "Other"
  final Set<String> _shootTypeChips = {};
  bool _showOtherShootType = false;
  final _otherShootTypeCtrl = TextEditingController();
  final List<String> _customShootTypes = [];

  // Team experience — optional
  final _teamFromCtrl = TextEditingController();
  final _teamToCtrl = TextEditingController();
  final _teamNameCtrl = TextEditingController();
  final _teamFbCtrl = TextEditingController();

  // Certificate — optional
  String? _certificateUrl;
  bool _uploadingCertificate = false;

  // Pricing model — mandatory choice, pick one or both
  bool _pricingHourly = false;
  bool _pricingPackage = false;
  final _hourlyMinCtrl = TextEditingController();
  final _hourlyMaxCtrl = TextEditingController();
  final _packageMinCtrl = TextEditingController();
  final _packageMaxCtrl = TextEditingController();

  @override
  void dispose() {
    _sampleDriveCtrl.dispose();
    _cameraModelCtrl.dispose();
    _achievementsCtrl.dispose();
    for (final l in _lenses) {
      l.focalLengthCtrl.dispose();
    }
    _experienceYearsCtrl.dispose();
    _workLocationCtrl.dispose();
    _otherShootTypeCtrl.dispose();
    _teamFromCtrl.dispose();
    _teamToCtrl.dispose();
    _teamNameCtrl.dispose();
    _teamFbCtrl.dispose();
    _hourlyMinCtrl.dispose();
    _hourlyMaxCtrl.dispose();
    _packageMinCtrl.dispose();
    _packageMaxCtrl.dispose();
    super.dispose();
  }

  void _addTag(TextEditingController ctrl, List<String> list) {
    final v = ctrl.text.trim();
    if (v.isEmpty || list.contains(v)) return;
    setState(() { list.add(v); ctrl.clear(); });
  }

  Widget _tagField({required TextEditingController ctrl, required List<String> list, required String hint}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            onSubmitted: (_) => _addTag(ctrl, list),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: () => _addTag(ctrl, list), icon: const Icon(Icons.add_rounded)),
      ]),
      if (list.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: list.map((s) => Chip(
          label: Text(s, style: const TextStyle(fontSize: 12.5)),
          onDeleted: () => setState(() => list.remove(s)),
          backgroundColor: AppColors.deepBlue.withOpacity(0.08),
        )).toList()),
      ],
    ]);
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

  Future<void> _uploadCameraPhoto() async {
    setState(() => _uploadingCameraPhoto = true);
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final ext = f.name.split('.').last.toLowerCase();
      final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
      final url = await OnboardingService.instance.uploadFile(fileBase64: base64Encode(bytes), fileName: f.name, mimeType: mime);
      if (mounted) setState(() => _cameraBodyPhotoUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingCameraPhoto = false);
    }
  }

  Future<void> _submit() async {
    if (_sampleDriveCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'পোর্টফোলিও Drive লিংক দিন' : 'Add your portfolio drive link', error: true);
      return;
    }
    if (_cameraModelCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'ক্যামেরার মডেল লিখুন' : 'Enter your camera model', error: true);
      return;
    }
    if (_cameraBodyPhotoUrl == null) {
      _snack(_isBn ? 'ক্যামেরার ছবি আপলোড করুন' : 'Upload a photo of your camera', error: true);
      return;
    }
    final experienceYears = int.tryParse(_experienceYearsCtrl.text.trim());
    if (experienceYears == null || experienceYears < 0) {
      _snack(_isBn ? 'অভিজ্ঞতার বছর লিখুন' : 'Enter your years of experience', error: true);
      return;
    }
    if (_workLocations.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি কাজের এলাকা যোগ করুন' : 'Add at least one location you can work in', error: true);
      return;
    }
    final shootTypes = [..._shootTypeChips, ..._customShootTypes];
    if (shootTypes.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি শুটের ধরন নির্বাচন করুন' : 'Select at least one shoot type', error: true);
      return;
    }
    if (!_pricingHourly && !_pricingPackage) {
      _snack(_isBn ? 'অন্তত একটি মূল্য মডেল নির্বাচন করুন' : 'Choose at least one pricing model', error: true);
      return;
    }
    double? hourlyRateMin, hourlyRateMax, packageRateMin, packageRateMax;
    if (_pricingHourly) {
      hourlyRateMin = double.tryParse(_hourlyMinCtrl.text.trim());
      hourlyRateMax = double.tryParse(_hourlyMaxCtrl.text.trim());
      if (hourlyRateMin == null || hourlyRateMax == null || hourlyRateMin <= 0 || hourlyRateMax < hourlyRateMin) {
        _snack(_isBn ? 'ঘণ্টাপ্রতি সঠিক মূল্য পরিসীমা দিন' : 'Enter a valid hourly rate range', error: true);
        return;
      }
    }
    if (_pricingPackage) {
      packageRateMin = double.tryParse(_packageMinCtrl.text.trim());
      packageRateMax = double.tryParse(_packageMaxCtrl.text.trim());
      if (packageRateMin == null || packageRateMax == null || packageRateMin <= 0 || packageRateMax < packageRateMin) {
        _snack(_isBn ? 'প্যাকেজ মূল্যের সঠিক পরিসীমা দিন' : 'Enter a valid package rate range', error: true);
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitPhotographyProfile(
        sampleDriveUrl: _sampleDriveCtrl.text.trim(),
        cameraBrand: _cameraBrand,
        cameraModel: _cameraModelCtrl.text.trim(),
        cameraBodyPhotoUrl: _cameraBodyPhotoUrl!,
        achievements: _achievementsCtrl.text.trim(),
        lenses: _lenses
            .where((l) => l.focalLengthCtrl.text.trim().isNotEmpty)
            .map((l) => {'brand': l.brand, 'focalLength': l.focalLengthCtrl.text.trim()})
            .toList(),
        equipment: _equipment.toList(),
        experienceYears: experienceYears,
        workLocations: _workLocations,
        shootTypes: shootTypes,
        teamExperienceFrom: _teamFromCtrl.text.trim().isEmpty ? null : _teamFromCtrl.text.trim(),
        teamExperienceTo: _teamToCtrl.text.trim().isEmpty ? null : _teamToCtrl.text.trim(),
        teamName: _teamNameCtrl.text.trim().isEmpty ? null : _teamNameCtrl.text.trim(),
        teamFacebookUrl: _teamFbCtrl.text.trim().isEmpty ? null : _teamFbCtrl.text.trim(),
        certificateUrl: _certificateUrl,
        pricingHourly: _pricingHourly,
        pricingPackage: _pricingPackage,
        hourlyRateMin: hourlyRateMin,
        hourlyRateMax: hourlyRateMax,
        packageRateMin: packageRateMin,
        packageRateMax: packageRateMax,
      );
      if (!mounted) return;
      _snack(_isBn ? 'গিয়ার প্রোফাইল সংরক্ষিত হয়েছে' : 'Gear profile saved');
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
              _header(_isBn ? 'গিয়ার প্রোফাইল' : 'Gear Profile'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      title: _isBn ? 'পোর্টফোলিও' : 'Portfolio',
                      child: labeledField(
                        controller: _sampleDriveCtrl,
                        hint: _isBn ? 'Google Drive / Dropbox লিংক' : 'Google Drive / Dropbox link',
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'ক্যামেরা' : 'Camera',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        brandDropdown(value: _cameraBrand, options: _cameraBrands, isBn: _isBn, onChanged: (v) => setState(() => _cameraBrand = v)),
                        const SizedBox(height: 10),
                        labeledField(controller: _cameraModelCtrl, hint: _isBn ? 'মডেল (যেমন: EOS R6)' : 'Model (e.g. EOS R6)'),
                        const SizedBox(height: 10),
                        uploadRow(
                          label: _cameraBodyPhotoUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'ক্যামেরার ছবি আপলোড করুন' : 'Upload a photo of your camera'),
                          uploaded: _cameraBodyPhotoUrl != null,
                          loading: _uploadingCameraPhoto,
                          onTap: _uploadCameraPhoto,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'লেন্স (ঐচ্ছিক)' : 'Lenses (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ..._lenses.asMap().entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(children: [
                                Expanded(
                                  flex: 2,
                                  child: brandDropdown(value: e.value.brand, options: _lensBrands, isBn: _isBn, onChanged: (v) => setState(() => e.value.brand = v)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: labeledField(controller: e.value.focalLengthCtrl, hint: _isBn ? 'ফোকাল লেংথ (যেমন: 24-70mm)' : 'Focal length (e.g. 24-70mm)'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                                  onPressed: () => setState(() => _lenses.removeAt(e.key)),
                                ),
                              ]),
                            )),
                        TextButton.icon(
                          onPressed: () => setState(() => _lenses.add(_LensRow())),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(_isBn ? 'লেন্স যোগ করুন' : 'Add a lens'),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'অতিরিক্ত সরঞ্জাম (ঐচ্ছিক)' : 'Additional equipment (optional)',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _equipmentItems.map((code) {
                          final active = _equipment.contains(code);
                          return GestureDetector(
                            onTap: () => setState(() => active ? _equipment.remove(code) : _equipment.add(code)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: active ? AppColors.blueGradient : null,
                                color: active ? null : const Color(0xFFF9F7F0),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                              ),
                              child: Text(equipmentLabel(code, _isBn), style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'অর্জন (ঐচ্ছিক)' : 'Achievements (optional)',
                      child: TextField(
                        controller: _achievementsCtrl,
                        maxLines: 3,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(hintText: _isBn ? 'পুরস্কার, প্রদর্শনী, উল্লেখযোগ্য কাজ...' : 'Awards, exhibitions, notable work...'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'অভিজ্ঞতার বছর' : 'Years of experience',
                      child: labeledField(
                        controller: _experienceYearsCtrl,
                        hint: _isBn ? 'যেমন: ৩' : 'e.g. 3',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'কাজের এলাকা' : 'Locations you can work in',
                      child: _tagField(
                        ctrl: _workLocationCtrl,
                        list: _workLocations,
                        hint: _isBn ? 'যেমন: ঢাকা, গাজীপুর' : 'e.g. Dhaka, Gazipur',
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'শুটের ধরন' : 'Shoot types',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._shootTypeOptions.map((code) {
                              final active = _shootTypeChips.contains(code);
                              return GestureDetector(
                                onTap: () => setState(() => active ? _shootTypeChips.remove(code) : _shootTypeChips.add(code)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: active ? AppColors.blueGradient : null,
                                    color: active ? null : const Color(0xFFF9F7F0),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                                  ),
                                  child: Text(shootTypeLabel(code, _isBn), style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                                ),
                              );
                            }),
                            GestureDetector(
                              onTap: () => setState(() => _showOtherShootType = !_showOtherShootType),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: _showOtherShootType ? AppColors.blueGradient : null,
                                  color: _showOtherShootType ? null : const Color(0xFFF9F7F0),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _showOtherShootType ? AppColors.deepBlue : AppColors.glassBorder, width: _showOtherShootType ? 1.5 : 1),
                                ),
                                child: Text(shootTypeLabel('OTHER', _isBn), style: TextStyle(color: _showOtherShootType ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: _showOtherShootType ? FontWeight.w700 : FontWeight.w500)),
                              ),
                            ),
                          ],
                        ),
                        if (_showOtherShootType) ...[
                          const SizedBox(height: 12),
                          _tagField(
                            ctrl: _otherShootTypeCtrl,
                            list: _customShootTypes,
                            hint: _isBn ? 'নিজের শুটের ধরন লিখুন' : 'Type your own shoot type',
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'টিম অভিজ্ঞতা (ঐচ্ছিক)' : 'Team experience (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _isBn ? 'ঐচ্ছিক — যোগ করলে প্রোফাইল আরও সমৃদ্ধ হবে' : 'Optional — adds more detail to your profile',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: labeledField(controller: _teamFromCtrl, hint: _isBn ? 'কত সাল/মাস থেকে' : 'From (year/month)')),
                          const SizedBox(width: 8),
                          Expanded(child: labeledField(controller: _teamToCtrl, hint: _isBn ? 'কত সাল/মাস পর্যন্ত' : 'To (year/month)')),
                        ]),
                        const SizedBox(height: 10),
                        labeledField(controller: _teamNameCtrl, hint: _isBn ? 'টিমের নাম' : 'Team name'),
                        const SizedBox(height: 10),
                        labeledField(controller: _teamFbCtrl, hint: _isBn ? 'টিমের ফেসবুক পেজ লিংক' : 'Team Facebook page link'),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'সার্টিফিকেট (ঐচ্ছিক)' : 'Certificate (optional)',
                      child: uploadRow(
                        label: _certificateUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'সার্টিফিকেট আপলোড করুন' : 'Upload a certificate'),
                        uploaded: _certificateUrl != null,
                        loading: _uploadingCertificate,
                        onTap: _uploadCertificate,
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'মূল্য মডেল' : 'Pricing model',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CheckboxListTile(
                          value: _pricingHourly,
                          onChanged: (v) => setState(() => _pricingHourly = v ?? false),
                          title: Text(_isBn ? 'ঘণ্টাপ্রতি' : 'Hourly', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        if (_pricingHourly)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              Expanded(child: labeledField(controller: _hourlyMinCtrl, hint: _isBn ? 'সর্বনিম্ন ৳' : 'Min ৳', keyboardType: TextInputType.number)),
                              const SizedBox(width: 8),
                              Expanded(child: labeledField(controller: _hourlyMaxCtrl, hint: _isBn ? 'সর্বোচ্চ ৳' : 'Max ৳', keyboardType: TextInputType.number)),
                            ]),
                          ),
                        CheckboxListTile(
                          value: _pricingPackage,
                          onChanged: (v) => setState(() => _pricingPackage = v ?? false),
                          title: Text(_isBn ? 'প্যাকেজ ভিত্তিক' : 'Package-based', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        if (_pricingPackage)
                          Row(children: [
                            Expanded(child: labeledField(controller: _packageMinCtrl, hint: _isBn ? 'সর্বনিম্ন ৳' : 'Min ৳', keyboardType: TextInputType.number)),
                            const SizedBox(width: 8),
                            Expanded(child: labeledField(controller: _packageMaxCtrl, hint: _isBn ? 'সর্বোচ্চ ৳' : 'Max ৳', keyboardType: TextInputType.number)),
                          ]),
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

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── Shared small widgets, reused by the cinematographer screen too ──────────

Widget sectionCard({required String title, required Widget child}) => GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        child,
      ]),
    );

Widget labeledField({required TextEditingController controller, required String hint, TextInputType? keyboardType}) => TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(hintText: hint),
    );

Widget brandDropdown({required String value, required List<String> options, required bool isBn, required ValueChanged<String> onChanged}) {
  return DropdownButtonFormField<String>(
    initialValue: value,
    items: options.map((o) => DropdownMenuItem(value: o, child: Text(o[0] + o.substring(1).toLowerCase().replaceAll('_', ' ')))).toList(),
    onChanged: (v) { if (v != null) onChanged(v); },
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    decoration: const InputDecoration(isDense: true),
  );
}

Widget uploadRow({required String label, required bool uploaded, required bool loading, required VoidCallback onTap}) => GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F7F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: uploaded ? const Color(0xFF10B981) : AppColors.glassBorder),
        ),
        child: Row(children: [
          if (loading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
          else
            Icon(uploaded ? Icons.check_circle_rounded : Icons.upload_file_rounded, color: uploaded ? const Color(0xFF10B981) : AppColors.textMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: uploaded ? const Color(0xFF10B981) : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
