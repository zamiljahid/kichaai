import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../core/network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

class NidScreen extends StatefulWidget {
  const NidScreen({super.key});

  @override
  State<NidScreen> createState() => _NidScreenState();
}

class _NidScreenState extends State<NidScreen> {
  final _client = ApiClient.instance.dio;
  final _nidNumCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  XFile? _frontImage;
  XFile? _backImage;
  Map<String, dynamic>? _status;
  bool _isLoading = true;
  bool _isSaving = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _nidNumCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.get('/onboarding/nid/status');
      if (mounted) setState(() { _status = res.data as Map<String, dynamic>?; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(bool isFront) async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1200);
    if (image != null) {
      setState(() { if (isFront) _frontImage = image; else _backImage = image; });
    }
  }

  Future<String> _toBase64(XFile file) async {
    final bytes = await File(file.path).readAsBytes();
    return base64Encode(bytes);
  }

  Future<void> _submit() async {
    if (_nidNumCtrl.text.isEmpty) { _showError('NID নম্বর দিন'); return; }
    if (_nameCtrl.text.isEmpty) { _showError('নামে তথ্য দিন'); return; }
    if (_frontImage == null) { _showError('NID সামনের ছবি যোগ করুন'); return; }
    if (_backImage == null) { _showError('NID পিছনের ছবি যোগ করুন'); return; }

    setState(() => _isSaving = true);
    try {
      final userId = await ApiClient.getUserId();
      final providerId = await ApiClient.getProviderProfileId() ?? userId;
      final frontB64 = await _toBase64(_frontImage!);
      final backB64 = await _toBase64(_backImage!);
      final displayName = await ApiClient.getFullName() ?? '';

      await _client.post('/onboarding/nid', data: {
        'providerId': providerId,
        'nidNumber': _nidNumCtrl.text.trim(),
        'nidFrontImage': frontB64,
        'nidBackImage': backB64,
        'nameOnNid': _nameCtrl.text.trim(),
        'displayName': displayName,
      });
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NID জমা দেওয়া হয়েছে, যাচাই হচ্ছে', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF10B981), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      final ex = ApiClient.mapError(e);
      _showError(ex.messageBn);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nidStatus = _status?['status'] as String?;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('NID যাচাইকরণ', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nidStatus != null) _buildStatusBanner(nidStatus),
                  const SizedBox(height: 16),
                  if (nidStatus == null || nidStatus == 'REJECTED') ...[
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('NID নম্বর'),
                          TextField(
                            controller: _nidNumCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _inputDeco('১০/১৩/১৭ সংখ্যার NID', Icons.credit_card_outlined),
                          ),
                          _label('NID-তে নাম'),
                          TextField(
                            controller: _nameCtrl,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _inputDeco('NID তে যেভাবে আছে', Icons.person_outline_rounded),
                          ),
                          const SizedBox(height: 20),
                          Row(children: [
                            Expanded(child: _imagePicker('সামনের দিক', _frontImage, () => _pickImage(true))),
                            const SizedBox(width: 12),
                            Expanded(child: _imagePicker('পিছনের দিক', _backImage, () => _pickImage(false))),
                          ]),
                          const SizedBox(height: 20),
                          GlassButton(
                            label: _isSaving ? 'জমা হচ্ছে...' : 'NID জমা দিন',
                            onPressed: _isSaving ? null : _submit,
                                                      ),
                        ],
                      ),
                    ).animate().fadeIn().slideY(begin: 0.2, end: 0),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner(String status) {
    final isVerified = status == 'VERIFIED';
    final isPending = status == 'PENDING';
    final isRejected = status == 'REJECTED';
    final color = isVerified ? const Color(0xFF10B981) : isPending ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    final icon = isVerified ? Icons.verified_rounded : isPending ? Icons.schedule_rounded : Icons.cancel_rounded;
    final text = isVerified ? 'NID যাচাই সম্পন্ন' : isPending ? 'যাচাই প্রক্রিয়াধীন...' : 'যাচাই প্রত্যাখ্যাত';
    final sub = isRejected ? (_status?['rejectionReason'] as String? ?? 'কারণ অজানা') : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          if (sub != null) Text('কারণ: $sub', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _imagePicker(String label, XFile? file, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
          image: file != null ? DecorationImage(image: FileImage(File(file.path)), fit: BoxFit.cover) : null,
        ),
        child: file == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted, size: 28),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ])
            : null,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
  );

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textMuted),
    prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
    filled: true,
    fillColor: AppColors.glassWhite,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );
}
