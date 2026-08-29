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
import '../widgets/liability_disclaimer.dart';
import 'photographer_profile_screen.dart' show sectionCard, labeledField, uploadRow;

/// Household-help (helping_hand / গৃহকর্মী সেবা) supplementary profile —
/// guardian identity + guardian contact, the provider's own current address
/// and phone, free-text work-area tags, rate per task, and the mandatory
/// liability disclaimer checkbox. NID for the provider themself is already
/// collected by the platform-wide generic onboarding flow, so only the
/// "father's/husband's — or if neither, mother's/a trusted guardian's" NID
/// image is captured here, alongside that guardian's name and phone so it is
/// unambiguous whose number it is. Reachable from the provider dashboard's
/// "My Services" list once the household-help application is approved, same
/// pattern as MakeupArtistProfileScreen (tag input) and PhotographerProfileScreen
/// (upload row).
class HouseholdHelpProfileScreen extends StatefulWidget {
  const HouseholdHelpProfileScreen({super.key});

  @override
  State<HouseholdHelpProfileScreen> createState() => _HouseholdHelpProfileScreenState();
}

class _HouseholdHelpProfileScreenState extends State<HouseholdHelpProfileScreen> {
  final _guardianNameCtrl = TextEditingController();
  final _guardianPhoneCtrl = TextEditingController();
  final _ownAddressCtrl = TextEditingController();
  final _ownPhoneCtrl = TextEditingController();
  final _workAreaCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final List<String> _workAreas = [];
  String? _guardianNidUrl;
  bool _uploadingGuardianNid = false;
  bool _liabilityAccepted = false;
  bool _submitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _guardianNameCtrl.dispose();
    _guardianPhoneCtrl.dispose();
    _ownAddressCtrl.dispose();
    _ownPhoneCtrl.dispose();
    _workAreaCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  void _addWorkArea() {
    final s = _workAreaCtrl.text.trim();
    if (s.isEmpty || _workAreas.contains(s)) return;
    setState(() { _workAreas.add(s); _workAreaCtrl.clear(); });
  }

  Future<void> _uploadGuardianNid() async {
    setState(() => _uploadingGuardianNid = true);
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final ext = f.name.split('.').last.toLowerCase();
      final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
      final url = await OnboardingService.instance.uploadFile(fileBase64: base64Encode(bytes), fileName: f.name, mimeType: mime);
      if (mounted) setState(() => _guardianNidUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingGuardianNid = false);
    }
  }

  Future<void> _submit() async {
    if (_guardianNidUrl == null) {
      _snack(_isBn ? 'অভিভাবকের NID এর ছবি আপলোড করুন' : "Upload the guardian's NID photo", error: true);
      return;
    }
    if (_guardianNameCtrl.text.trim().isEmpty || _guardianPhoneCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'অভিভাবকের নাম ও ফোন নম্বর দিন' : "Enter the guardian's name and phone number", error: true);
      return;
    }
    if (_ownAddressCtrl.text.trim().isEmpty || _ownPhoneCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'নিজের ঠিকানা ও ফোন নম্বর দিন' : 'Enter your own address and phone number', error: true);
      return;
    }
    if (_workAreas.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি কাজের এলাকা যোগ করুন' : 'Add at least one work area', error: true);
      return;
    }
    final rate = double.tryParse(_rateCtrl.text.trim());
    if (rate == null || rate < 0) {
      _snack(_isBn ? 'প্রতি কাজের রেট সঠিকভাবে দিন' : 'Enter a valid rate per task', error: true);
      return;
    }
    if (!_liabilityAccepted) {
      _snack(_isBn ? 'এগিয়ে যাওয়ার আগে দায়বদ্ধতার শর্তে সম্মত হন' : 'Agree to the liability terms before continuing', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitHelpingHandProfile(
        guardianNidUrl: _guardianNidUrl!,
        guardianName: _guardianNameCtrl.text.trim(),
        guardianPhone: _guardianPhoneCtrl.text.trim(),
        ownAddress: _ownAddressCtrl.text.trim(),
        ownPhone: _ownPhoneCtrl.text.trim(),
        workAreas: _workAreas,
        ratePerTask: rate,
        liabilityAccepted: _liabilityAccepted,
      );
      if (!mounted) return;
      _snack(_isBn ? 'গৃহকর্মী প্রোফাইল সংরক্ষিত হয়েছে' : 'Household help profile saved');
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
                  Text(_isBn ? 'গৃহকর্মী প্রোফাইল' : 'Household Help Profile', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      title: _isBn ? 'অভিভাবকের NID (বাবা/স্বামী; না থাকলে মা/বিশ্বস্ত অভিভাবক)' : "Guardian's NID (father/husband; or mother/trusted guardian if neither)",
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        uploadRow(
                          label: _guardianNidUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'NID এর ছবি আপলোড করুন' : 'Upload NID photo'),
                          uploaded: _guardianNidUrl != null,
                          loading: _uploadingGuardianNid,
                          onTap: _uploadGuardianNid,
                        ),
                        const SizedBox(height: 10),
                        labeledField(controller: _guardianNameCtrl, hint: _isBn ? 'অভিভাবকের নাম' : "Guardian's name"),
                        const SizedBox(height: 10),
                        labeledField(controller: _guardianPhoneCtrl, hint: _isBn ? 'অভিভাবকের ফোন নম্বর' : "Guardian's phone number", keyboardType: TextInputType.phone),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'নিজের তথ্য' : 'Your details',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        labeledField(controller: _ownAddressCtrl, hint: _isBn ? 'বর্তমান ঠিকানা' : 'Current address'),
                        const SizedBox(height: 10),
                        labeledField(controller: _ownPhoneCtrl, hint: _isBn ? 'ফোন নম্বর' : 'Phone number', keyboardType: TextInputType.phone),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'কাজের এলাকা' : 'Work areas',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _workAreaCtrl,
                              onSubmitted: (_) => _addWorkArea(),
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                              decoration: InputDecoration(hintText: _isBn ? 'যেমন: মিরপুর, ধানমন্ডি' : 'e.g. Mirpur, Dhanmondi'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(onPressed: _addWorkArea, icon: const Icon(Icons.add_rounded)),
                        ]),
                        if (_workAreas.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(spacing: 6, runSpacing: 6, children: _workAreas.map((s) => Chip(
                            label: Text(s, style: const TextStyle(fontSize: 12.5)),
                            onDeleted: () => setState(() => _workAreas.remove(s)),
                            backgroundColor: AppColors.deepBlue.withOpacity(0.08),
                          )).toList()),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'প্রতি কাজের রেট (৳)' : 'Rate per task (৳)',
                      child: labeledField(controller: _rateCtrl, hint: _isBn ? 'যেমন: ৫০০' : 'e.g. 500', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                    ),
                    const SizedBox(height: 14),
                    liabilityDisclaimerCheckbox(
                      value: _liabilityAccepted,
                      onChanged: (v) => setState(() => _liabilityAccepted = v),
                      isBn: _isBn,
                    ),
                    const SizedBox(height: 22),
                    GlassButton(
                      label: _isBn ? 'সংরক্ষণ করুন' : 'Save',
                      isLoading: _submitting,
                      onPressed: (_submitting || !_liabilityAccepted) ? null : _submit,
                    ),
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
