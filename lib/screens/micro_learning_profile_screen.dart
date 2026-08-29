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
import 'photographer_profile_screen.dart' show sectionCard, uploadRow;

/// Micro-learning-only supplementary profile — expertise topics + university
/// ID + additional certificates, which the generic document-upload
/// onboarding flow never captures as structured fields. Uses the
/// 'micro_learning' serviceType (nid.submitMicroLearningProfile,
/// ProviderInstructorProfile) — the dead 'instructor' serviceType/pattern is
/// deliberately not used here. Reachable from the provider dashboard's
/// "My Services" list once the micro-learning application is approved.
class MicroLearningProfileScreen extends StatefulWidget {
  const MicroLearningProfileScreen({super.key});

  @override
  State<MicroLearningProfileScreen> createState() => _MicroLearningProfileScreenState();
}

class _MicroLearningProfileScreenState extends State<MicroLearningProfileScreen> {
  final _topicController = TextEditingController();
  final List<String> _topics = [];
  String? _universityIdUrl;
  final List<String> _certificateUrls = [];
  bool _uploadingUniversityId = false;
  bool _uploadingCertificate = false;
  final _instituteEmailController = TextEditingController();
  // Founder's framing: live is free/preferred and pre-selected; recorded
  // requires explicit consent to a recurring monthly extra fee.
  String _contentFormat = 'live'; // 'live' | 'recorded'
  bool _recordedFeeConsent = false;
  bool _submitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _topicController.dispose();
    _instituteEmailController.dispose();
    super.dispose();
  }

  void _addTopic() {
    final t = _topicController.text.trim();
    if (t.isEmpty || _topics.contains(t)) return;
    setState(() { _topics.add(t); _topicController.clear(); });
  }

  Future<String> _pickAndUpload() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f == null) throw Exception(_isBn ? 'বাতিল করা হয়েছে' : 'Cancelled');
    final bytes = await f.readAsBytes();
    final ext = f.name.split('.').last.toLowerCase();
    final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
    return OnboardingService.instance.uploadFile(fileBase64: base64Encode(bytes), fileName: f.name, mimeType: mime);
  }

  Future<void> _uploadUniversityId() async {
    setState(() => _uploadingUniversityId = true);
    try {
      final url = await _pickAndUpload();
      if (mounted) setState(() => _universityIdUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingUniversityId = false);
    }
  }

  Future<void> _uploadCertificate() async {
    setState(() => _uploadingCertificate = true);
    try {
      final url = await _pickAndUpload();
      if (mounted) setState(() => _certificateUrls.add(url));
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingCertificate = false);
    }
  }

  Future<void> _submit() async {
    if (_topics.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি বিষয়ে দক্ষতা যোগ করুন' : 'Add at least one expertise topic', error: true);
      return;
    }
    if (_universityIdUrl == null) {
      _snack(_isBn ? 'শিক্ষাগত সনদ/আইডি আপলোড করুন' : 'Upload your education certificate/ID', error: true);
      return;
    }
    final email = _instituteEmailController.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _snack(_isBn ? 'সঠিক ইমেইল ঠিকানা দিন' : 'Enter a valid email address', error: true);
      return;
    }
    if (_contentFormat == 'recorded' && !_recordedFeeConsent) {
      _snack(
        _isBn
            ? 'রেকর্ডেড কোর্সের জন্য মাসিক অতিরিক্ত ফি-তে সম্মতি প্রয়োজন'
            : 'Consent to the monthly extra fee is required for recorded courses',
        error: true,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitMicroLearningProfile(
        universityIdUrl: _universityIdUrl!,
        certificatesUrls: _certificateUrls,
        expertiseTopics: _topics,
        instituteEmail: email.isNotEmpty ? email : null,
        contentFormat: _contentFormat,
        recordedFeeConsent: _recordedFeeConsent,
      );
      if (!mounted) return;
      _snack(_isBn ? 'মাইক্রো-লার্নিং প্রোফাইল সংরক্ষিত হয়েছে' : 'Micro-learning profile saved');
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
                  Text(_isBn ? 'মাইক্রো-লার্নিং প্রোফাইল' : 'Micro-Learning Profile', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      title: _isBn ? 'দক্ষতার বিষয়' : 'Expertise topics',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _topicController,
                              onSubmitted: (_) => _addTopic(),
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                              decoration: InputDecoration(hintText: _isBn ? 'যেমন: ওয়েব ডেভেলপমেন্ট' : 'e.g. Web Development'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(onPressed: _addTopic, icon: const Icon(Icons.add_rounded)),
                        ]),
                        if (_topics.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(spacing: 6, runSpacing: 6, children: _topics.map((t) => Chip(
                            label: Text(t, style: const TextStyle(fontSize: 12.5)),
                            onDeleted: () => setState(() => _topics.remove(t)),
                            backgroundColor: AppColors.deepBlue.withOpacity(0.08),
                          )).toList()),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'শিক্ষাগত সনদ / বিশ্ববিদ্যালয় আইডি' : 'Education certificate / University ID',
                      child: uploadRow(
                        label: _universityIdUrl != null
                            ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓')
                            : (_isBn ? 'ছবি আপলোড করুন' : 'Upload a photo'),
                        uploaded: _universityIdUrl != null,
                        loading: _uploadingUniversityId,
                        onTap: _uploadUniversityId,
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'অতিরিক্ত সার্টিফিকেট (ঐচ্ছিক)' : 'Additional certificates (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        uploadRow(
                          label: _isBn ? 'সার্টিফিকেট যোগ করুন' : 'Add a certificate',
                          uploaded: false,
                          loading: _uploadingCertificate,
                          onTap: _uploadCertificate,
                        ),
                        if (_certificateUrls.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _isBn ? '${_certificateUrls.length}টি সার্টিফিকেট যোগ হয়েছে' : '${_certificateUrls.length} certificate(s) added',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'প্রতিষ্ঠানের ইমেইল (ঐচ্ছিক)' : 'Institute email (optional)',
                      child: TextField(
                        controller: _instituteEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(hintText: _isBn ? 'instructor@university.edu' : 'instructor@university.edu'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'ক্লাসের ধরন' : 'Class format',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _formatTab(
                                  'live',
                                  _isBn ? '🔴 লাইভ' : '🔴 Live',
                                  _isBn ? 'অতিরিক্ত ফি নেই' : 'No extra payment',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _formatTab(
                                  'recorded',
                                  _isBn ? '🎬 রেকর্ডেড' : '🎬 Recorded',
                                  _isBn ? 'মাসিক ফি প্রযোজ্য' : 'Monthly fee applies',
                                ),
                              ),
                            ],
                          ),
                          if (_contentFormat == 'recorded') ...[
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () => setState(() => _recordedFeeConsent = !_recordedFeeConsent),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      _recordedFeeConsent ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                      color: _recordedFeeConsent ? AppColors.deepBlue : AppColors.textMuted,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _isBn
                                            ? 'আমি রেকর্ডেড কোর্সের জন্য মাসিক অতিরিক্ত ফি দিতে সম্মত'
                                            : 'I agree to a monthly extra fee for recorded courses',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
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

  Widget _formatTab(String value, String label, String sub) {
    final active = _contentFormat == value;
    return GestureDetector(
      onTap: () => setState(() {
        _contentFormat = value;
        if (value == 'live') _recordedFeeConsent = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: active ? AppColors.blueGradient : null,
          color: active ? null : const Color(0xFFF9F7F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.transparent : AppColors.glassBorder),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: active ? Colors.white : AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: active ? Colors.white70 : AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
