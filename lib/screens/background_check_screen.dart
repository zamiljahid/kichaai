import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../core/network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';

class BackgroundCheckScreen extends StatefulWidget {
  const BackgroundCheckScreen({super.key});

  @override
  State<BackgroundCheckScreen> createState() => _BackgroundCheckScreenState();
}

class _BackgroundCheckScreenState extends State<BackgroundCheckScreen> {
  final _client = ApiClient.instance.dio;
  Map<String, dynamic>? _checkData;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _providerId;

  final _fullNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  XFile? _idFront;
  XFile? _idBack;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _providerId = await ApiClient.getProviderProfileId();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.get('/onboarding/background-check/status');
      if (mounted) {
        setState(() {
          _checkData = res.data as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_fullNameCtrl.text.trim().isEmpty || _dobCtrl.text.trim().isEmpty || _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সব তথ্য পূরণ করুন', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String? frontBase64;
      String? backBase64;
      if (_idFront != null) frontBase64 = base64Encode(await _idFront!.readAsBytes());
      if (_idBack != null) backBase64 = base64Encode(await _idBack!.readAsBytes());

      await _client.post('/onboarding/background-check', data: {
        'providerId': _providerId,
        'fullName': _fullNameCtrl.text.trim(),
        'dateOfBirth': _dobCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        if (frontBase64 != null) 'idFrontImage': frontBase64,
        if (backBase64 != null) 'idBackImage': backBase64,
      });

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ব্যাকগ্রাউন্ড চেক সাবমিট হয়েছে', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF10B981), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      final ex = ApiClient.mapError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ex.messageBn, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickImage(bool isFront) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null && mounted) setState(() { if (isFront) _idFront = picked; else _idBack = picked; });
  }

  @override
  Widget build(BuildContext context) {
    final status = _checkData?['status'] as String?;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('ব্যাকগ্রাউন্ড চেক', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (status != null) _buildStatusBanner(status),
                  if (status == null || status == 'REJECTED') ...[
                    const SizedBox(height: 20),
                    _buildForm(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner(String status) {
    final cfg = switch (status) {
      'VERIFIED' => (const Color(0xFF10B981), Icons.verified_rounded, 'যাচাই সম্পন্ন', 'আপনার ব্যাকগ্রাউন্ড চেক সফলভাবে সম্পন্ন হয়েছে।'),
      'PENDING' => (const Color(0xFFF59E0B), Icons.hourglass_empty_rounded, 'পর্যালোচনাধীন', 'আপনার তথ্য যাচাই করা হচ্ছে। কিছুটা সময় লাগতে পারে।'),
      _ => (const Color(0xFFEF4444), Icons.cancel_outlined, 'প্রত্যাখ্যাত', _checkData?['rejectionReason'] as String? ?? 'আপনার আবেদন প্রত্যাখ্যাত হয়েছে। পুনরায় আবেদন করুন।'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cfg.$1.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cfg.$1.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(cfg.$2, color: cfg.$1, size: 32),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cfg.$3, style: TextStyle(color: cfg.$1, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(cfg.$4, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ])),
      ]),
    ).animate().fadeIn();
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('আবেদন ফর্ম', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 16),
        _label('পূর্ণ নাম'),
        _field(_fullNameCtrl, 'আপনার পূর্ণ নাম', Icons.person_outline_rounded),
        const SizedBox(height: 14),
        _label('জন্ম তারিখ'),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime(1990),
              firstDate: DateTime(1950),
              lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
            );
            if (picked != null && mounted) _dobCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          },
          child: AbsorbPointer(child: _field(_dobCtrl, 'YYYY-MM-DD', Icons.calendar_today_outlined)),
        ),
        const SizedBox(height: 14),
        _label('বর্তমান ঠিকানা'),
        TextField(
          controller: _addressCtrl,
          maxLines: 2,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'আপনার বর্তমান ঠিকানা',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.textMuted, size: 18),
            filled: true,
            fillColor: AppColors.glassWhite,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
        _label('পরিচয়পত্রের ছবি'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _imagePicker('সামনের পৃষ্ঠা', _idFront, () => _pickImage(true))),
          const SizedBox(width: 12),
          Expanded(child: _imagePicker('পেছনের পৃষ্ঠা', _idBack, () => _pickImage(false))),
        ]),
        const SizedBox(height: 28),
        GlassButton(
          label: _isSubmitting ? 'সাবমিট হচ্ছে...' : 'আবেদন করুন',
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
  );

  Widget _field(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
        filled: true,
        fillColor: AppColors.glassWhite,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _imagePicker(String label, XFile? file, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: file != null ? AppColors.deepBlue : AppColors.glassBorder),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(file != null ? Icons.check_circle_rounded : Icons.add_photo_alternate_outlined,
            color: file != null ? AppColors.deepBlue : AppColors.textMuted, size: 28),
          const SizedBox(height: 6),
          Text(file != null ? 'নির্বাচিত' : label, style: TextStyle(color: file != null ? AppColors.deepBlue : AppColors.textMuted, fontSize: 11)),
        ]),
      ),
    );
  }
}
