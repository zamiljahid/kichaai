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

/// Tutor-only supplementary profile — subjects taught + teaching levels, which
/// nothing in the generic document-upload onboarding flow ever captures.
/// OnboardingService.submitTutorProfile already existed and posted correctly;
/// this is the first screen that actually calls it. Reachable from the
/// provider dashboard's "My Services" list once the home-tutor application
/// is approved (see provider_dashboard_screen.dart's _buildMyServicesSection).
///
/// Populating this is also what makes a tutor's subjects visible in the
/// customer-facing browse screen — see matchmaking.service.ts's
/// syncProviderVerification, which mirrors subjectsTaught/teachingLevels here
/// onto matchmaking-service the moment this same application gets approved.
class TutorProfileScreen extends StatefulWidget {
  const TutorProfileScreen({super.key});

  @override
  State<TutorProfileScreen> createState() => _TutorProfileScreenState();
}

const _teachingLevelOptions = [
  'প্লে/নার্সারি', 'কেজি', 'ক্লাস ১-৫', 'ক্লাস ৬-৮', 'ক্লাস ৯-১০', 'HSC', 'ভর্তি পরীক্ষা', 'বিশ্ববিদ্যালয়', 'ভাষা শিক্ষা',
];

class _TutorProfileScreenState extends State<TutorProfileScreen> {
  final _subjectController = TextEditingController();
  final List<String> _subjects = [];
  final Set<String> _levels = {};
  String? _universityIdUrl;
  final List<String> _certificateUrls = [];
  bool _uploadingUniversityId = false;
  bool _uploadingCertificate = false;
  bool _submitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  void _addSubject() {
    final s = _subjectController.text.trim();
    if (s.isEmpty || _subjects.contains(s)) return;
    setState(() { _subjects.add(s); _subjectController.clear(); });
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
    if (_subjects.isEmpty) { _snack(_isBn ? 'অন্তত একটি বিষয় যোগ করুন' : 'Add at least one subject', error: true); return; }
    if (_levels.isEmpty) { _snack(_isBn ? 'অন্তত একটি লেভেল বেছে নিন' : 'Choose at least one level', error: true); return; }
    if (_universityIdUrl == null) { _snack(_isBn ? 'শিক্ষাগত সনদ/আইডি আপলোড করুন' : 'Upload your education certificate/ID', error: true); return; }

    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitTutorProfile(
        subjectsTaught: _subjects,
        teachingLevels: _levels.toList(),
        universityIdUrl: _universityIdUrl!,
        certificatesUrls: _certificateUrls,
      );
      if (!mounted) return;
      _snack(_isBn ? 'টিউটর প্রোফাইল সংরক্ষিত হয়েছে' : 'Tutor profile saved');
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
              _header(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _sectionCard(
                      title: _isBn ? 'যে বিষয়ে পড়ান' : 'Subjects taught',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _subjectController,
                              onSubmitted: (_) => _addSubject(),
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                              decoration: InputDecoration(hintText: _isBn ? 'যেমন: গণিত' : 'e.g. Math'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(onPressed: _addSubject, icon: const Icon(Icons.add_rounded)),
                        ]),
                        if (_subjects.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(spacing: 6, runSpacing: 6, children: _subjects.map((s) => Chip(
                            label: Text(s, style: const TextStyle(fontSize: 12.5)),
                            onDeleted: () => setState(() => _subjects.remove(s)),
                            backgroundColor: AppColors.deepBlue.withOpacity(0.08),
                          )).toList()),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: _isBn ? 'যে লেভেলে পড়ান' : 'Levels taught',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _teachingLevelOptions.map((level) {
                          final active = _levels.contains(level);
                          return GestureDetector(
                            onTap: () => setState(() => active ? _levels.remove(level) : _levels.add(level)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: active ? AppColors.blueGradient : null,
                                color: active ? null : const Color(0xFFF9F7F0),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                              ),
                              child: Text(level, style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: _isBn ? 'শিক্ষাগত সনদ / বিশ্ববিদ্যালয় আইডি' : 'Education certificate / University ID',
                      child: _uploadRow(
                        label: _universityIdUrl != null
                            ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓')
                            : (_isBn ? 'ছবি আপলোড করুন' : 'Upload a photo'),
                        uploaded: _universityIdUrl != null,
                        loading: _uploadingUniversityId,
                        onTap: _uploadUniversityId,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: _isBn ? 'অতিরিক্ত সার্টিফিকেট (ঐচ্ছিক)' : 'Additional certificates (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _uploadRow(
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

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Text(_isBn ? 'টিউটর প্রোফাইল' : 'Tutor Profile', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _sectionCard({required String title, required Widget child}) => GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _uploadRow({required String label, required bool uploaded, required bool loading, required VoidCallback onTap}) => GestureDetector(
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
            Text(label, style: TextStyle(color: uploaded ? const Color(0xFF10B981) : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
