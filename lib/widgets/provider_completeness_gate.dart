import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network/api_client.dart';
import '../services/auth_service.dart';
import 'glass_button.dart';
import 'glass_card.dart';

/// Checks profile-photo / phone / rules-agreement completeness and, if anything is missing,
/// shows a bottom sheet to fix it in place. Returns true once all three are satisfied (either
/// already, or fixed during this call) — false if the user backs out without finishing.
///
/// Mirrors dispatch-service's startLiveSession gate (same three conditions, enforced there too
/// as a fail-closed backstop for older app builds) so every go-online entry point in the app
/// gets this one shared UX instead of a bare "Gender required"-style error toast.
Future<bool> ensureProviderCompleteness(BuildContext context, bool isBn) async {
  Map<String, bool> status;
  try {
    status = await AuthService.instance.getProviderProfileCompleteness();
  } catch (_) {
    // Fail-open on the client-side prompt — dispatch-service's gate is the real enforcement
    // point and will reject going online anyway if this call couldn't reach auth-service.
    return true;
  }
  if (status['hasPhoto'] == true && status['hasPhone'] == true && status['rulesAgreed'] == true) {
    return true;
  }
  if (!context.mounted) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CompletenessSheet(isBn: isBn, initialStatus: status),
  );
  return result ?? false;
}

class _CompletenessSheet extends StatefulWidget {
  final bool isBn;
  final Map<String, bool> initialStatus;
  const _CompletenessSheet({required this.isBn, required this.initialStatus});

  @override
  State<_CompletenessSheet> createState() => _CompletenessSheetState();
}

class _CompletenessSheetState extends State<_CompletenessSheet> {
  late bool _hasPhoto;
  late bool _hasPhone;
  late bool _rulesAgreed;
  bool _agreeChecked = false;
  bool _busyPhoto = false;
  bool _busyPhone = false;
  bool _busyRules = false;
  String? _error;
  final _phoneCtrl = TextEditingController();

  bool get _allDone => _hasPhoto && _hasPhone && _rulesAgreed;

  @override
  void initState() {
    super.initState();
    _hasPhoto = widget.initialStatus['hasPhoto'] ?? false;
    _hasPhone = widget.initialStatus['hasPhone'] ?? false;
    _rulesAgreed = widget.initialStatus['rulesAgreed'] ?? false;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() { _busyPhoto = true; _error = null; });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (file == null) { setState(() => _busyPhoto = false); return; }
      final bytes = await file.readAsBytes();
      await AuthService.instance.uploadProviderProfilePhoto(base64Encode(bytes));
      if (mounted) setState(() { _hasPhoto = true; _busyPhoto = false; });
    } catch (e) {
      if (mounted) setState(() { _busyPhoto = false; _error = ApiClient.mapError(e).localized(widget.isBn); });
    }
  }

  Future<void> _savePhone() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() { _busyPhone = true; _error = null; });
    try {
      await AuthService.instance.updateProfile(phone: phone);
      if (mounted) setState(() { _hasPhone = true; _busyPhone = false; });
    } catch (e) {
      if (mounted) setState(() { _busyPhone = false; _error = ApiClient.mapError(e).localized(widget.isBn); });
    }
  }

  Future<void> _agreeRules() async {
    if (!_agreeChecked) return;
    setState(() { _busyRules = true; _error = null; });
    try {
      await AuthService.instance.agreeToProviderRules();
      if (mounted) setState(() { _rulesAgreed = true; _busyRules = false; });
    } catch (e) {
      if (mounted) setState(() { _busyRules = false; _error = ApiClient.mapError(e).localized(widget.isBn); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBn = widget.isBn;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: colors.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isBn ? 'অনলাইন হওয়ার আগে প্রোফাইল সম্পূর্ণ করুন' : 'Complete your profile before going online',
                style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                ),
              _buildPhotoTile(isBn),
              const SizedBox(height: 12),
              _buildPhoneTile(isBn),
              const SizedBox(height: 12),
              _buildRulesTile(isBn),
              const SizedBox(height: 20),
              GlassButton(
                label: isBn ? 'চালিয়ে যান' : 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: _allDone ? () => Navigator.of(context).pop(true) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTile(bool isBn) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(_hasPhoto ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
              color: _hasPhoto ? const Color(0xFF10B981) : colors.outline, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(isBn ? 'প্রোফাইল ছবি' : 'Profile photo',
                style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          if (!_hasPhoto)
            _busyPhoto
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: _pickPhoto, child: Text(isBn ? 'আপলোড' : 'Upload')),
        ],
      ),
    );
  }

  Widget _buildPhoneTile(bool isBn) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_hasPhone ? Icons.check_circle_rounded : Icons.phone_rounded,
                  color: _hasPhone ? const Color(0xFF10B981) : colors.outline, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(isBn ? 'ফোন নম্বর' : 'Phone number',
                    style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (!_hasPhone) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: colors.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '01XXXXXXXXX',
                      hintStyle: TextStyle(color: colors.outline),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _busyPhone
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: _savePhone, child: Text(isBn ? 'সেভ' : 'Save')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRulesTile(bool isBn) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_rulesAgreed ? Icons.check_circle_rounded : Icons.rule_rounded,
                  color: _rulesAgreed ? const Color(0xFF10B981) : colors.outline, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(isBn ? 'নিয়মাবলী' : 'Rules & Regulations',
                    style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (!_rulesAgreed) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: _agreeChecked, onChanged: (v) => setState(() => _agreeChecked = v ?? false)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: GestureDetector(
                      onTap: () => launchUrl(Uri.parse('https://kichaai.com/provider-rules'), mode: LaunchMode.externalApplication),
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
                          children: [
                            TextSpan(text: isBn ? 'আমি ' : 'I have read and agree to the '),
                            TextSpan(
                              text: isBn ? 'নিয়মাবলী' : 'Rules & Regulations',
                              style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                            ),
                            TextSpan(text: isBn ? ' পড়েছি ও সম্মত' : ''),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GlassButton(
              label: isBn ? 'সম্মত' : 'Agree',
              isOutlined: true,
              isLoading: _busyRules,
              onPressed: _agreeChecked ? _agreeRules : null,
            ),
          ],
        ],
      ),
    );
  }
}
