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
import 'photographer_profile_screen.dart' show sectionCard, labeledField, uploadRow;

/// Caregiver-only supplementary certificate profile — which the generic
/// document-upload onboarding flow never captures as structured fields.
/// OnboardingService.submitCaregiverProfile already existed and posted
/// correctly; this is the first screen that actually calls it.
class CaregiverProfileScreen extends StatefulWidget {
  const CaregiverProfileScreen({super.key});

  @override
  State<CaregiverProfileScreen> createState() => _CaregiverProfileScreenState();
}

const _specializationOptions = [
  'বয়স্ক যত্ন', 'শিশু যত্ন', 'প্রসূতি যত্ন', 'অসুস্থ রোগী যত্ন', 'প্রতিবন্ধী সহায়তা',
  'ডিমেনশিয়া/আলঝেইমার', 'পোস্ট-সার্জারি যত্ন', 'ফিজিওথেরাপি সহায়তা',
];

class _CaregiverProfileScreenState extends State<CaregiverProfileScreen> {
  final _certificateTypeCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  String? _certificateUrl;
  bool _uploadingCertificate = false;
  final Set<String> _specializations = {};
  bool _submitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _certificateTypeCtrl.dispose();
    _experienceCtrl.dispose();
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

  Future<void> _submit() async {
    if (_certificateUrl == null) {
      _snack(_isBn ? 'সার্টিফিকেট আপলোড করুন' : 'Upload your certificate', error: true);
      return;
    }
    if (_certificateTypeCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'সার্টিফিকেটের ধরন লিখুন' : 'Enter the certificate type', error: true);
      return;
    }
    final years = int.tryParse(_experienceCtrl.text.trim());
    if (years == null || years < 0) {
      _snack(_isBn ? 'অভিজ্ঞতার বছর সঠিকভাবে দিন' : 'Enter valid years of experience', error: true);
      return;
    }
    if (_specializations.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি বিশেষত্ব বেছে নিন' : 'Choose at least one specialization', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitCaregiverProfile(
        certificateUrl: _certificateUrl!,
        certificateType: _certificateTypeCtrl.text.trim(),
        experienceYears: years,
        specializations: _specializations.toList(),
      );
      if (!mounted) return;
      _snack(_isBn ? 'কেয়ারগিভার প্রোফাইল সংরক্ষিত হয়েছে' : 'Caregiver profile saved');
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
                  Text(_isBn ? 'কেয়ারগিভার প্রোফাইল' : 'Caregiver Profile', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      title: _isBn ? 'সার্টিফিকেট' : 'Certificate',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        labeledField(controller: _certificateTypeCtrl, hint: _isBn ? 'সার্টিফিকেটের ধরন (যেমন: নার্সিং, ফার্স্ট এইড)' : 'Certificate type (e.g. Nursing, First Aid)'),
                        const SizedBox(height: 10),
                        uploadRow(
                          label: _certificateUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'সার্টিফিকেটের ছবি আপলোড করুন' : 'Upload a photo of your certificate'),
                          uploaded: _certificateUrl != null,
                          loading: _uploadingCertificate,
                          onTap: _uploadCertificate,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'অভিজ্ঞতা' : 'Experience',
                      child: labeledField(controller: _experienceCtrl, hint: _isBn ? 'অভিজ্ঞতার বছর' : 'Years of experience', keyboardType: TextInputType.number),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'বিশেষত্ব' : 'Specializations',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _specializationOptions.map((s) {
                          final active = _specializations.contains(s);
                          return GestureDetector(
                            onTap: () => setState(() => active ? _specializations.remove(s) : _specializations.add(s)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: active ? AppColors.blueGradient : null,
                                color: active ? null : const Color(0xFFF9F7F0),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                              ),
                              child: Text(s, style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            ),
                          );
                        }).toList(),
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
