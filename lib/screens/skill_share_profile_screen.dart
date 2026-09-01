import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/onboarding_service.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'photographer_profile_screen.dart' show sectionCard, uploadRow;

/// Skill-share-only supplementary profile — university/education ID +
/// additional certificates, which the generic document-upload onboarding
/// flow never captures as structured fields. The backend
/// (nid.submitSkillShareProfile, ProviderSkillShareProfile) already existed
/// and worked correctly; this is the first screen that actually calls it.
/// Reachable from the provider dashboard's "My Services" list once the
/// skill-share application is approved, same pattern as CaregiverProfileScreen.
class SkillShareProfileScreen extends StatefulWidget {
  const SkillShareProfileScreen({super.key});

  @override
  State<SkillShareProfileScreen> createState() => _SkillShareProfileScreenState();
}

class _SkillShareProfileScreenState extends State<SkillShareProfileScreen> {
  String? _universityIdUrl;
  final List<String> _certificateUrls = [];
  bool _uploadingUniversityId = false;
  bool _uploadingCertificate = false;
  bool _submitting = false;
  bool _isBn = true;

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
    if (_universityIdUrl == null) {
      _snack(_isBn ? 'শিক্ষাগত সনদ/আইডি আপলোড করুন' : 'Upload your education certificate/ID', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitSkillShareProfile(
        universityIdUrl: _universityIdUrl!,
        certificatesUrls: _certificateUrls,
      );
      if (!mounted) return;
      _snack(_isBn ? 'স্কিল শেয়ার প্রোফাইল সংরক্ষিত হয়েছে' : 'Skill share profile saved');
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
                  Text(_isBn ? 'স্কিল শেয়ার প্রোফাইল' : 'Skill Share Profile', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      colors: colors,
                      title: _isBn ? 'শিক্ষাগত সনদ / বিশ্ববিদ্যালয় আইডি' : 'Education certificate / University ID',
                      child: uploadRow(colors: colors, 
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
                      colors: colors,
                      title: _isBn ? 'অতিরিক্ত সার্টিফিকেট (ঐচ্ছিক)' : 'Additional certificates (optional)',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        uploadRow(colors: colors, 
                          label: _isBn ? 'সার্টিফিকেট যোগ করুন' : 'Add a certificate',
                          uploaded: false,
                          loading: _uploadingCertificate,
                          onTap: _uploadCertificate,
                        ),
                        if (_certificateUrls.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _isBn ? '${_certificateUrls.length}টি সার্টিফিকেট যোগ হয়েছে' : '${_certificateUrls.length} certificate(s) added',
                            style: TextStyle(color: colors.outline, fontSize: 12),
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
