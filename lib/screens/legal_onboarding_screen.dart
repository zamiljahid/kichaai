import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/network/api_client.dart';
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
  const _ConsultMode(this.code, this.bn);
}

const _modes = [
  _ConsultMode('video', 'ভিডিও কল'),
  _ConsultMode('phone', 'ফোন কল'),
  _ConsultMode('chat', 'চ্যাট'),
  _ConsultMode('in_person', 'সরাসরি'),
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
  String _llbStatus = 'graduate';

  String? _photoBase64;
  bool _photoBusy = false;

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
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
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
      _snack('ছবি বাছাই ব্যর্থ হয়েছে', error: true);
    }
  }

  Future<void> _submit() async {
    // Validation
    if (_selectedAreas.isEmpty) return _snack('অন্তত একটি বিষয় বাছুন', error: true);
    if (_selectedServices.isEmpty) return _snack('অন্তত একটি সেবা বাছুন', error: true);
    final exp = int.tryParse(_experienceCtl.text.trim());
    if (exp == null) return _snack('অভিজ্ঞতা (বছর) দিন', error: true);
    if (_role == 'advocate' && _barNoCtl.text.trim().isEmpty) {
      return _snack('বার কাউন্সিল এনরোলমেন্ট নম্বর দিন', error: true);
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
        llbUniversity: _role == 'legal_assistant' ? _llbUniCtl.text.trim() : null,
        llbStatus: _role == 'legal_assistant' ? _llbStatus : null,
      );
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.mapError(e).messageBn);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: const Text('জমা হয়েছে ✅', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'আপনার তথ্য জমা হয়েছে। অ্যাডমিন যাচাই করে ফি নির্ধারণ করলে আপনি গ্রাহকদের কাছে দৃশ্যমান হবেন।',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('ঠিক আছে', style: TextStyle(color: AppColors.deepBlue)),
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
                            _chipsCard('কোন কোন বিষয়ে কাজ করেন?', _areas, _selectedAreas),
                            const SizedBox(height: 16),
                            _chipsCard('কোন কোন সেবা দেন?', _services, _selectedServices),
                            const SizedBox(height: 16),
                            _modesCard(),
                            const SizedBox(height: 16),
                            _detailsCard(),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                            ],
                            const SizedBox(height: 20),
                            GlassButton(
                              label: 'জমা দিন',
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
            const Text('আইনজীবী হিসেবে যুক্ত হন',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('প্রোফাইল ছবি', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('গ্রাহকরা আপনার প্রোফাইলে এই ছবি দেখবে (ঐচ্ছিক)',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
            const Text('আপনি কে?', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                _roleTab('advocate', '👨‍⚖️ আইনজীবী', 'সনদপ্রাপ্ত'),
                const SizedBox(width: 10),
                _roleTab('legal_assistant', '📝 আইন সহকারী', 'সনদ নেই'),
              ],
            ),
            if (_role == 'legal_assistant')
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('⚠️ আপনি কোর্টে প্রতিনিধিত্ব করতে পারবেন না — শুধু পরামর্শ ও ডকুমেন্ট।',
                    style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
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
                final label = (it['bn'] ?? it['en'] ?? code).toString();
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
            const Text('পরামর্শের মাধ্যম', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
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
                    child: Text(m.bn, style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
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
            _field(_experienceCtl, 'অভিজ্ঞতা (বছর)', keyboard: TextInputType.number),
            const SizedBox(height: 12),
            _field(_feeCtl, 'প্রস্তাবিত ফি (৳ / সেশন) — অ্যাডমিন চূড়ান্ত করবে', keyboard: TextInputType.number),
            if (_role == 'advocate') ...[
              const SizedBox(height: 12),
              _field(_casesWonCtl, 'আগের কত মামলা জিতেছেন', keyboard: TextInputType.number),
              const SizedBox(height: 12),
              _field(_barNoCtl, 'বার কাউন্সিল এনরোলমেন্ট নম্বর'),
            ] else ...[
              const SizedBox(height: 12),
              _field(_llbUniCtl, 'বিশ্ববিদ্যালয় (LLB)'),
              const SizedBox(height: 12),
              _dropdown(),
            ],
          ],
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
        decoration: const InputDecoration(labelText: 'অবস্থা'),
        items: const [
          DropdownMenuItem(value: 'student', child: Text('ছাত্র')),
          DropdownMenuItem(value: 'graduate', child: Text('স্নাতক')),
          DropdownMenuItem(value: 'paralegal', child: Text('প্যারা-লিগ্যাল')),
        ],
        onChanged: (v) => setState(() => _llbStatus = v ?? 'graduate'),
      );
}
