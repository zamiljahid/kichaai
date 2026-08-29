import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// Two-tier legal provider onboarding (advocate / legal assistant).
/// Collects role, legal areas, offered services, experience, proposed fee,
/// cases-won (advocate) or LLB details (assistant), plus an optional profile
/// photo. Backend: GET /legal/options, POST /onboarding/legal-profile,
/// POST /auth/provider/profile-photo.
class LegalOnboardingScreen extends StatefulWidget {
  const LegalOnboardingScreen({super.key});

  @override
  State<LegalOnboardingScreen> createState() => _LegalOnboardingScreenState();
}

class _ConsultMode {
  final String code;
  final String bn;
  final String en;
  const _ConsultMode(this.code, this.bn, this.en);
}

const _modes = [
  _ConsultMode('video', 'ভিডিও কল', 'Video call'),
  _ConsultMode('phone', 'ফোন কল', 'Phone call'),
  _ConsultMode('chat', 'চ্যাট', 'Chat'),
  _ConsultMode('in_person', 'সরাসরি', 'In person'),
];

class _LegalOnboardingScreenState extends State<LegalOnboardingScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  String _role = 'advocate';
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _services = []; // filtered by role

  final _selectedAreas = <String>{};
  final _selectedServices = <String>{};
  final _selectedModes = <String>{'video'};

  final _experienceCtl = TextEditingController();
  final _feeCtl = TextEditingController();
  final _casesWonCtl = TextEditingController();
  final _barNoCtl = TextEditingController();
  final _llbUniCtl = TextEditingController();
  final _instituteFromCtl = TextEditingController();
  final _instituteToCtl = TextEditingController();
  String _llbStatus = 'graduate';

  String? _photoBase64;
  bool _photoBusy = false;

  // Advocate-only mandatory certificate uploads — real files, uploaded via the
  // generic OnboardingService.uploadFile endpoint (same as the document-upload
  // flow in provider_onboarding_screen.dart), unlike the bar-certificate field
  // above which is currently a placeholder pending a dedicated upload step.
  Uint8List? _hscPreview;
  String? _hscUrl;
  bool _hscUploading = false;
  Uint8List? _bachelorPreview;
  String? _bachelorUrl;
  bool _bachelorUploading = false;

  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _experienceCtl.dispose();
    _feeCtl.dispose();
    _casesWonCtl.dispose();
    _barNoCtl.dispose();
    _llbUniCtl.dispose();
    _instituteFromCtl.dispose();
    _instituteToCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Make sure a provider profile exists before submitting the legal profile.
      try { await AuthService.instance.becomeProvider(); } catch (_) {}
      await _loadOptions();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = ApiClient.mapError(e).localized(_isBn); });
    }
  }

  Future<void> _loadOptions() async {
    final opts = await OnboardingService.instance.getLegalOptions(role: _role);
    final areas = (opts['areas'] as List? ?? []).cast<Map<String, dynamic>>();
    final services = (opts['services'] as List? ?? []).cast<Map<String, dynamic>>();
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _services = services;
      // Drop any selected service the new role can't offer.
      final allowed = services.map((s) => s['code'] as String).toSet();
      _selectedServices.removeWhere((s) => !allowed.contains(s));
    });
  }

  Future<void> _onRoleChanged(String role) async {
    if (role == _role) return;
    setState(() => _role = role);
    await _loadOptions();
  }

  Future<void> _pickPhoto() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _photoBase64 = base64Encode(bytes));
    } catch (e) {
      _snack(_isBn ? 'ছবি বাছাই ব্যর্থ হয়েছে' : 'Failed to pick photo', error: true);
    }
  }

  Future<void> _pickHscCertificate() => _pickAndUploadCertificate(isHsc: true);
  Future<void> _pickBachelorCertificate() => _pickAndUploadCertificate(isHsc: false);

  Future<void> _pickAndUploadCertificate({required bool isHsc}) async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        if (isHsc) { _hscPreview = bytes; _hscUploading = true; } else { _bachelorPreview = bytes; _bachelorUploading = true; }
      });
      final ext = x.name.split('.').last.toLowerCase();
      final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
      final url = await OnboardingService.instance.uploadFile(
        fileBase64: base64Encode(bytes),
        fileName: x.name,
        mimeType: mime,
      );
      if (!mounted) return;
      setState(() {
        if (isHsc) { _hscUrl = url; } else { _bachelorUrl = url; }
      });
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) {
        setState(() {
          if (isHsc) { _hscUploading = false; } else { _bachelorUploading = false; }
        });
      }
    }
  }

  Future<void> _submit() async {
    // Validation
    if (_selectedAreas.isEmpty) return _snack(_isBn ? 'অন্তত একটি বিষয় বাছুন' : 'Choose at least one area', error: true);
    if (_selectedServices.isEmpty) return _snack(_isBn ? 'অন্তত একটি সেবা বাছুন' : 'Choose at least one service', error: true);
    final exp = int.tryParse(_experienceCtl.text.trim());
    if (exp == null) return _snack(_isBn ? 'অভিজ্ঞতা (বছর) দিন' : 'Enter your experience (years)', error: true);
    if (_role == 'advocate' && _barNoCtl.text.trim().isEmpty) {
      return _snack(_isBn ? 'বার কাউন্সিল এনরোলমেন্ট নম্বর দিন' : 'Enter your Bar Council enrollment number', error: true);
    }
    if (_role == 'advocate' && _hscUrl == null) {
      return _snack(_isBn ? 'HSC সার্টিফিকেট আপলোড করুন' : 'Upload your HSC certificate', error: true);
    }
    if (_role == 'advocate' && _bachelorUrl == null) {
      return _snack(_isBn ? 'স্নাতক/LLB সার্টিফিকেট আপলোড করুন' : 'Upload your Bachelor\'s/LLB certificate', error: true);
    }

    setState(() { _submitting = true; _error = null; });
    try {
      // Upload profile photo first (best-effort — doesn't block submission).
      if (_photoBase64 != null && !_photoBusy) {
        _photoBusy = true;
        try { await AuthService.instance.uploadProviderProfilePhoto(_photoBase64!); } catch (_) {}
        _photoBusy = false;
      }

      await OnboardingService.instance.submitLegalProfile(
        legalRole: _role,
        caseAreas: _selectedAreas.toList(),
        servicesOffered: _selectedServices.toList(),
        consultationModes: _selectedModes.toList(),
        experienceYears: exp,
        proposedFee: double.tryParse(_feeCtl.text.trim()),
        casesWon: _role == 'advocate' ? int.tryParse(_casesWonCtl.text.trim()) : null,
        barEnrollmentNumber: _role == 'advocate' ? _barNoCtl.text.trim() : null,
        // Bar certificate image upload is handled by the certificate step; a
        // placeholder marks that enrollment was declared for admin review.
        barCertificateUrl: _role == 'advocate' ? 'pending-review' : null,
        hscCertificateUrl: _role == 'advocate' ? _hscUrl : null,
        bachelorCertificateUrl: _role == 'advocate' ? _bachelorUrl : null,
        instituteFromYear: _instituteFromCtl.text.trim().isNotEmpty ? _instituteFromCtl.text.trim() : null,
        instituteToYear: _instituteToCtl.text.trim().isNotEmpty ? _instituteToCtl.text.trim() : null,
        llbUniversity: _role == 'legal_assistant' ? _llbUniCtl.text.trim() : null,
        llbStatus: _role == 'legal_assistant' ? _llbStatus : null,
      );
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'জমা হয়েছে ✅' : 'Submitted ✅', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          _isBn
              ? 'আপনার তথ্য জমা হয়েছে। অ্যাডমিন যাচাই করে ফি নির্ধারণ করলে আপনি গ্রাহকদের কাছে দৃশ্যমান হবেন।'
              : 'Your information has been submitted. Once admin verifies and sets your fee, you\'ll be visible to customers.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text(_isBn ? 'ঠিক আছে' : 'OK', style: const TextStyle(color: AppColors.deepBlue)),
          ),
        ],
      ),
    );
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
              _appBar(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _photoSection(),
                            const SizedBox(height: 16),
                            _roleSection(),
                            const SizedBox(height: 16),
                            _chipsCard(_isBn ? 'কোন কোন বিষয়ে কাজ করেন?' : 'Which areas do you work in?', _areas, _selectedAreas),
                            const SizedBox(height: 16),
                            _chipsCard(_isBn ? 'কোন কোন সেবা দেন?' : 'Which services do you offer?', _services, _selectedServices),
                            const SizedBox(height: 16),
                            _modesCard(),
                            const SizedBox(height: 16),
                            _detailsCard(),
                            if (_role == 'advocate') ...[
                              const SizedBox(height: 16),
                              _certificatesCard(),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                            ],
                            const SizedBox(height: 20),
                            GlassButton(
                              label: _isBn ? 'জমা দিন' : 'Submit',
                              isLoading: _submitting,
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Text(_isBn ? 'আইনজীবী হিসেবে যুক্ত হন' : 'Join as a Lawyer',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _photoSection() => GlassCard(
        child: Row(
          children: [
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.glassWhite,
                  border: Border.all(color: AppColors.glassBorder),
                  image: _photoBase64 != null
                      ? DecorationImage(image: MemoryImage(base64Decode(_photoBase64!)), fit: BoxFit.cover)
                      : null,
                ),
                child: _photoBase64 == null
                    ? const Icon(Icons.add_a_photo_rounded, color: AppColors.textMuted)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isBn ? 'প্রোফাইল ছবি' : 'Profile photo', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(_isBn ? 'গ্রাহকরা আপনার প্রোফাইলে এই ছবি দেখবে (ঐচ্ছিক)' : 'Customers will see this photo on your profile (optional)',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _roleSection() => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isBn ? 'আপনি কে?' : 'Who are you?', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                _roleTab('advocate', _isBn ? '👨‍⚖️ আইনজীবী' : '👨‍⚖️ Advocate', _isBn ? 'সনদপ্রাপ্ত' : 'Certified'),
                const SizedBox(width: 10),
                _roleTab('legal_assistant', _isBn ? '📝 আইন সহকারী' : '📝 Legal Assistant', _isBn ? 'সনদ নেই' : 'No certification'),
              ],
            ),
            if (_role == 'legal_assistant')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                    _isBn
                        ? '⚠️ আপনি কোর্টে প্রতিনিধিত্ব করতে পারবেন না — শুধু পরামর্শ ও ডকুমেন্ট।'
                        : '⚠️ You cannot represent clients in court — consultation and documents only.',
                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
              ),
          ],
        ),
      );

  Widget _roleTab(String code, String label, String sub) {
    final sel = _role == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onRoleChanged(code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            gradient: sel ? AppColors.blueGradient : null,
            color: sel ? null : AppColors.glassWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? Colors.transparent : AppColors.glassBorder),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(color: sel ? Colors.white : AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: sel ? Colors.white70 : AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipsCard(String title, List<Map<String, dynamic>> items, Set<String> selected) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((it) {
                final code = it['code'] as String;
                final label = ((_isBn ? it['bn'] : it['en']) ?? it['bn'] ?? it['en'] ?? code).toString();
                final sel = selected.contains(code);
                return GestureDetector(
                  onTap: () => setState(() => sel ? selected.remove(code) : selected.add(code)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: sel ? AppColors.blueGradient : null,
                      color: sel ? null : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: sel ? Colors.transparent : AppColors.glassBorder),
                    ),
                    child: Text(label, style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _modesCard() => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isBn ? 'পরামর্শের মাধ্যম' : 'Consultation methods', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _modes.map((m) {
                final sel = _selectedModes.contains(m.code);
                return GestureDetector(
                  onTap: () => setState(() => sel ? _selectedModes.remove(m.code) : _selectedModes.add(m.code)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: sel ? AppColors.blueGradient : null,
                      color: sel ? null : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: sel ? Colors.transparent : AppColors.glassBorder),
                    ),
                    child: Text(_isBn ? m.bn : m.en, style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _detailsCard() => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_experienceCtl, _isBn ? 'অভিজ্ঞতা (বছর)' : 'Experience (years)', keyboard: TextInputType.number),
            const SizedBox(height: 12),
            _field(_feeCtl, _isBn ? 'প্রস্তাবিত ফি (৳ / সেশন) — অ্যাডমিন চূড়ান্ত করবে' : 'Proposed fee (৳ / session) — admin will finalize', keyboard: TextInputType.number),
            if (_role == 'advocate') ...[
              const SizedBox(height: 12),
              _field(_casesWonCtl, _isBn ? 'আগের কত মামলা জিতেছেন' : 'How many cases won previously', keyboard: TextInputType.number),
              const SizedBox(height: 12),
              _field(_barNoCtl, _isBn ? 'বার কাউন্সিল এনরোলমেন্ট নম্বর' : 'Bar Council enrollment number'),
            ] else ...[
              const SizedBox(height: 12),
              _field(_llbUniCtl, _isBn ? 'বিশ্ববিদ্যালয় (LLB)' : 'University (LLB)'),
              const SizedBox(height: 12),
              _dropdown(),
            ],
            const SizedBox(height: 12),
            Text(_isBn ? 'যে প্রতিষ্ঠানে পড়েছেন — কোন সাল থেকে কোন সাল পর্যন্ত' : 'Institute studied at — from year to year',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(_instituteFromCtl, _isBn ? 'শুরুর সাল' : 'From year', keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field(_instituteToCtl, _isBn ? 'শেষের সাল' : 'To year', keyboard: TextInputType.number)),
              ],
            ),
          ],
        ),
      );

  Widget _certificatesCard() => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isBn ? 'শিক্ষাগত সার্টিফিকেট (আবশ্যক)' : 'Educational certificates (required)',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                _isBn
                    ? 'আইনজীবী হিসেবে যাচাইয়ের জন্য HSC ও স্নাতক/LLB সার্টিফিকেটের ছবি আপলোড করুন'
                    : 'Upload photos of your HSC and Bachelor\'s/LLB certificates for advocate verification',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            Text(_isBn ? 'HSC সার্টিফিকেট' : 'HSC certificate',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _certPickBox(
              preview: _hscPreview,
              isBusy: _hscUploading,
              uploaded: _hscUrl != null,
              onTap: _pickHscCertificate,
            ),
            const SizedBox(height: 16),
            Text(_isBn ? 'স্নাতক/LLB সার্টিফিকেট' : 'Bachelor\'s/LLB certificate',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _certPickBox(
              preview: _bachelorPreview,
              isBusy: _bachelorUploading,
              uploaded: _bachelorUrl != null,
              onTap: _pickBachelorCertificate,
            ),
          ],
        ),
      );

  // Same visual pattern as _photoSection's picker, but as a full-width box
  // that uploads to the backend and stores the real fileUrl (matching the
  // generic document-upload flow in provider_onboarding_screen.dart), rather
  // than only keeping local base64 bytes.
  Widget _certPickBox({
    required Uint8List? preview,
    required bool isBusy,
    required bool uploaded,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: isBusy ? null : onTap,
        child: Container(
          height: 130,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: uploaded ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
          ),
          child: isBusy
              ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue, strokeWidth: 2))
              : preview != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(
                        children: [
                          Positioned.fill(child: Image.memory(preview, fit: BoxFit.cover)),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.deepBlue, borderRadius: BorderRadius.circular(8)),
                              child: Text(_isBn ? 'পরিবর্তন করুন' : 'Change',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_upload_outlined, color: AppColors.textMuted, size: 28),
                        const SizedBox(height: 6),
                        Text(_isBn ? 'ট্যাপ করে ছবি বেছে নিন' : 'Tap to choose a photo',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
        ),
      );

  Widget _field(TextEditingController c, String hint, {TextInputType? keyboard}) => TextField(
        controller: c,
        keyboardType: keyboard,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(hintText: hint),
      );

  Widget _dropdown() => DropdownButtonFormField<String>(
        initialValue: _llbStatus,
        dropdownColor: AppColors.bgMid,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(labelText: _isBn ? 'অবস্থা' : 'Status'),
        items: [
          DropdownMenuItem(value: 'student', child: Text(_isBn ? 'ছাত্র' : 'Student')),
          DropdownMenuItem(value: 'graduate', child: Text(_isBn ? 'স্নাতক' : 'Graduate')),
          DropdownMenuItem(value: 'paralegal', child: Text(_isBn ? 'প্যারা-লিগ্যাল' : 'Paralegal')),
        ],
        onChanged: (v) => setState(() => _llbStatus = v ?? 'graduate'),
      );
}
