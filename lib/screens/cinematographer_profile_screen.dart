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
import 'photographer_profile_screen.dart' show sectionCard, labeledField, brandDropdown, uploadRow, equipmentLabel, shootTypeLabel;

/// Cinematographer-only supplementary gear profile — same idea as
/// PhotographerProfileScreen but with reel/drone/gimbal/shooting-style fields
/// that only apply to video work. OnboardingService.submitCinemaProfile
/// already existed and posted correctly; this is the first screen that
/// actually calls it.
class CinematographerProfileScreen extends StatefulWidget {
  const CinematographerProfileScreen({super.key});

  @override
  State<CinematographerProfileScreen> createState() => _CinematographerProfileScreenState();
}

const _cameraBrands = ['CANON', 'NIKON', 'SONY', 'FUJIFILM', 'PANASONIC', 'OLYMPUS', 'LEICA', 'HASSELBLAD', 'OTHER'];
const _lensBrands = ['CANON', 'NIKON', 'SONY', 'SIGMA', 'TAMRON', 'TOKINA', 'ZEISS', 'SAMYANG', 'OTHER'];
const _equipmentItems = [
  'TRIPOD', 'MONOPOD', 'GIMBAL', 'DRONE', 'SPEEDLIGHT', 'STUDIO_LIGHT', 'SOFTBOX', 'REFLECTOR',
  'ND_FILTER', 'POLARIZER_FILTER', 'CAMERA_BAG', 'MEMORY_CARD_FAST', 'EXTERNAL_RECORDER', 'SLIDER',
  'FOLLOW_FOCUS', 'MICROPHONE', 'STABILIZER', 'GREEN_SCREEN', 'BACKDROP',
];
const _shootTypeOptions = ['WEDDING', 'DOCUMENTARY', 'PORTRAIT', 'EVENT', 'COMMERCIAL', 'PRODUCT'];

class _LensRow {
  String brand = 'CANON';
  final focalLengthCtrl = TextEditingController();
}

class _CinematographerProfileScreenState extends State<CinematographerProfileScreen> {
  final _sampleDriveCtrl = TextEditingController();
  final _reelCtrl = TextEditingController();
  final _cameraModelCtrl = TextEditingController();
  final _droneModelCtrl = TextEditingController();
  final _gimbalModelCtrl = TextEditingController();
  final _achievementsCtrl = TextEditingController();
  final _styleCtrl = TextEditingController();
  final _softwareCtrl = TextEditingController();
  String _cameraBrand = 'CANON';
  String? _cameraBodyPhotoUrl;
  bool _uploadingCameraPhoto = false;
  final List<_LensRow> _lenses = [];
  final Set<String> _equipment = {};
  final List<String> _shootingStyles = [];
  final List<String> _editingSoftware = [];
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
    _reelCtrl.dispose();
    _cameraModelCtrl.dispose();
    _droneModelCtrl.dispose();
    _gimbalModelCtrl.dispose();
    _achievementsCtrl.dispose();
    _styleCtrl.dispose();
    _softwareCtrl.dispose();
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

  void _addTag(TextEditingController ctrl, List<String> list) {
    final v = ctrl.text.trim();
    if (v.isEmpty || list.contains(v)) return;
    setState(() { list.add(v); ctrl.clear(); });
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
      await OnboardingService.instance.submitCinemaProfile(
        sampleDriveUrl: _sampleDriveCtrl.text.trim(),
        reelUrl: _reelCtrl.text.trim(),
        cameraBrand: _cameraBrand,
        cameraModel: _cameraModelCtrl.text.trim(),
        cameraBodyPhotoUrl: _cameraBodyPhotoUrl!,
        droneModel: _droneModelCtrl.text.trim(),
        gimbalModel: _gimbalModelCtrl.text.trim(),
        shootingStyles: _shootingStyles,
        editingSoftware: _editingSoftware,
        lenses: _lenses
            .where((l) => l.focalLengthCtrl.text.trim().isNotEmpty)
            .map((l) => {'brand': l.brand, 'focalLength': l.focalLengthCtrl.text.trim()})
            .toList(),
        equipment: _equipment.toList(),
        achievements: _achievementsCtrl.text.trim(),
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

  Widget _tagField({required TextEditingController ctrl, required List<String> list, required String hint}) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            onSubmitted: (_) => _addTag(ctrl, list),
            style: TextStyle(color: colors.onSurface, fontSize: 14),
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
          backgroundColor: colors.primary.withOpacity(0.08),
        )).toList()),
      ],
    ]);
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
                  Text(_isBn ? 'গিয়ার প্রোফাইল' : 'Gear Profile', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
colors: colors,
title: _isBn ? 'পোর্টফোলিও' : 'Portfolio',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        labeledField(colors: colors, controller: _sampleDriveCtrl, hint: _isBn ? 'Google Drive / Dropbox লিংক' : 'Google Drive / Dropbox link'),
                        const SizedBox(height: 10),
                        labeledField(colors: colors, controller: _reelCtrl, hint: _isBn ? 'শোরিল লিংক (ঐচ্ছিক)' : 'Showreel link (optional)'),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'ক্যামেরা' : 'Camera',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        brandDropdown(colors: colors, value: _cameraBrand, options: _cameraBrands, isBn: _isBn, onChanged: (v) => setState(() => _cameraBrand = v)),
                        const SizedBox(height: 10),
                        labeledField(colors: colors, controller: _cameraModelCtrl, hint: _isBn ? 'মডেল (যেমন: FX3)' : 'Model (e.g. FX3)'),
                        const SizedBox(height: 10),
                        uploadRow(colors: colors, 
                          label: _cameraBodyPhotoUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'ক্যামেরার ছবি আপলোড করুন' : 'Upload a photo of your camera'),
                          uploaded: _cameraBodyPhotoUrl != null,
                          loading: _uploadingCameraPhoto,
                          onTap: _uploadCameraPhoto,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'ড্রোন ও জিম্বাল (ঐচ্ছিক)' : 'Drone & Gimbal (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        labeledField(colors: colors, controller: _droneModelCtrl, hint: _isBn ? 'ড্রোন মডেল' : 'Drone model'),
                        const SizedBox(height: 10),
                        labeledField(colors: colors, controller: _gimbalModelCtrl, hint: _isBn ? 'জিম্বাল মডেল' : 'Gimbal model'),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'শুটিং স্টাইল' : 'Shooting styles',
                      child: _tagField(ctrl: _styleCtrl, list: _shootingStyles, hint: _isBn ? 'যেমন: সিনেম্যাটিক, ডকুমেন্টারি' : 'e.g. Cinematic, Documentary'),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'এডিটিং সফটওয়্যার' : 'Editing software',
                      child: _tagField(ctrl: _softwareCtrl, list: _editingSoftware, hint: _isBn ? 'যেমন: Premiere Pro, DaVinci Resolve' : 'e.g. Premiere Pro, DaVinci Resolve'),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'লেন্স (ঐচ্ছিক)' : 'Lenses (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ..._lenses.asMap().entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(children: [
                                Expanded(flex: 2, child: brandDropdown(colors: colors, value: e.value.brand, options: _lensBrands, isBn: _isBn, onChanged: (v) => setState(() => e.value.brand = v))),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: labeledField(colors: colors, controller: e.value.focalLengthCtrl, hint: _isBn ? 'ফোকাল লেংথ' : 'Focal length')),
                                IconButton(icon: Icon(Icons.close_rounded, size: 18, color: colors.outline), onPressed: () => setState(() => _lenses.removeAt(e.key))),
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
colors: colors,
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
                                gradient: active ? AppGradients.primary(colors) : null,
                                color: active ? null : colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: active ? colors.primary : colors.outlineVariant, width: active ? 1.5 : 1),
                              ),
                              child: Text(equipmentLabel(code, _isBn), style: TextStyle(color: active ? Colors.white : colors.onSurfaceVariant, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            ),
                          );
                        }).toList(),
                      ),
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
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'অভিজ্ঞতার বছর' : 'Years of experience',
                      child: labeledField(colors: colors, 
                        controller: _experienceYearsCtrl,
                        hint: _isBn ? 'যেমন: ৩' : 'e.g. 3',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'কাজের এলাকা' : 'Locations you can work in',
                      child: _tagField(
                        ctrl: _workLocationCtrl,
                        list: _workLocations,
                        hint: _isBn ? 'যেমন: ঢাকা, গাজীপুর' : 'e.g. Dhaka, Gazipur',
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
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
                                    gradient: active ? AppGradients.primary(colors) : null,
                                    color: active ? null : colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: active ? colors.primary : colors.outlineVariant, width: active ? 1.5 : 1),
                                  ),
                                  child: Text(shootTypeLabel(code, _isBn), style: TextStyle(color: active ? Colors.white : colors.onSurfaceVariant, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                                ),
                              );
                            }),
                            GestureDetector(
                              onTap: () => setState(() => _showOtherShootType = !_showOtherShootType),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: _showOtherShootType ? AppGradients.primary(colors) : null,
                                  color: _showOtherShootType ? null : colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _showOtherShootType ? colors.primary : colors.outlineVariant, width: _showOtherShootType ? 1.5 : 1),
                                ),
                                child: Text(shootTypeLabel('OTHER', _isBn), style: TextStyle(color: _showOtherShootType ? Colors.white : colors.onSurfaceVariant, fontSize: 12.5, fontWeight: _showOtherShootType ? FontWeight.w700 : FontWeight.w500)),
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
colors: colors,
title: _isBn ? 'টিম অভিজ্ঞতা (ঐচ্ছিক)' : 'Team experience (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _isBn ? 'ঐচ্ছিক — যোগ করলে প্রোফাইল আরও সমৃদ্ধ হবে' : 'Optional — adds more detail to your profile',
                          style: TextStyle(color: colors.outline, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: labeledField(colors: colors, controller: _teamFromCtrl, hint: _isBn ? 'কত সাল/মাস থেকে' : 'From (year/month)')),
                          const SizedBox(width: 8),
                          Expanded(child: labeledField(colors: colors, controller: _teamToCtrl, hint: _isBn ? 'কত সাল/মাস পর্যন্ত' : 'To (year/month)')),
                        ]),
                        const SizedBox(height: 10),
                        labeledField(colors: colors, controller: _teamNameCtrl, hint: _isBn ? 'টিমের নাম' : 'Team name'),
                        const SizedBox(height: 10),
                        labeledField(colors: colors, controller: _teamFbCtrl, hint: _isBn ? 'টিমের ফেসবুক পেজ লিংক' : 'Team Facebook page link'),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'সার্টিফিকেট (ঐচ্ছিক)' : 'Certificate (optional)',
                      child: uploadRow(colors: colors, 
                        label: _certificateUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'সার্টিফিকেট আপলোড করুন' : 'Upload a certificate'),
                        uploaded: _certificateUrl != null,
                        loading: _uploadingCertificate,
                        onTap: _uploadCertificate,
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
colors: colors,
title: _isBn ? 'মূল্য মডেল' : 'Pricing model',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CheckboxListTile(
                          value: _pricingHourly,
                          onChanged: (v) => setState(() => _pricingHourly = v ?? false),
                          title: Text(_isBn ? 'ঘণ্টাপ্রতি' : 'Hourly', style: TextStyle(color: colors.onSurface, fontSize: 13)),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        if (_pricingHourly)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              Expanded(child: labeledField(colors: colors, controller: _hourlyMinCtrl, hint: _isBn ? 'সর্বনিম্ন ৳' : 'Min ৳', keyboardType: TextInputType.number)),
                              const SizedBox(width: 8),
                              Expanded(child: labeledField(colors: colors, controller: _hourlyMaxCtrl, hint: _isBn ? 'সর্বোচ্চ ৳' : 'Max ৳', keyboardType: TextInputType.number)),
                            ]),
                          ),
                        CheckboxListTile(
                          value: _pricingPackage,
                          onChanged: (v) => setState(() => _pricingPackage = v ?? false),
                          title: Text(_isBn ? 'প্যাকেজ ভিত্তিক' : 'Package-based', style: TextStyle(color: colors.onSurface, fontSize: 13)),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        if (_pricingPackage)
                          Row(children: [
                            Expanded(child: labeledField(colors: colors, controller: _packageMinCtrl, hint: _isBn ? 'সর্বনিম্ন ৳' : 'Min ৳', keyboardType: TextInputType.number)),
                            const SizedBox(width: 8),
                            Expanded(child: labeledField(colors: colors, controller: _packageMaxCtrl, hint: _isBn ? 'সর্বোচ্চ ৳' : 'Max ৳', keyboardType: TextInputType.number)),
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
}
