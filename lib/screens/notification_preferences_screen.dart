import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../widgets/glass_button.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  NotificationPreference? _prefs;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = await ApiClient.getUserId();
    if (userId == null || userId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final p = await NotificationService.instance.getPreferences(userId);
      if (mounted) setState(() { _prefs = p; _isLoading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _prefs = NotificationPreference(
            userId: userId,
            pushEnabled: true,
            emailEnabled: true,
            smsEnabled: false,
            jobUpdate: true,
            payment: true,
            marketing: false,
            system: true,
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_prefs == null) return;
    setState(() => _isSaving = true);
    try {
      await NotificationService.instance.upsertPreferences(_prefs!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isBn ? 'সেটিংস সংরক্ষিত হয়েছে' : 'Settings saved', style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ApiClient.mapError(e).localized(_isBn), style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'নোটিফিকেশন সেটিংস' : 'Notification Settings', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _prefs == null
              ? Center(child: Text(_isBn ? 'লোড করা যায়নি' : 'Could not load', style: TextStyle(color: colors.outline)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    _sectionHeader(_isBn ? 'চ্যানেল' : 'Channels'),
                    _buildSwitch(
                      icon: Icons.notifications_active_outlined,
                      label: _isBn ? 'পুশ নোটিফিকেশন' : 'Push Notifications',
                      subtitle: _isBn ? 'অ্যাপের মাধ্যমে সরাসরি বিজ্ঞপ্তি' : 'Direct alerts through the app',
                      value: _prefs!.pushEnabled,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(pushEnabled: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.email_outlined,
                      label: _isBn ? 'ইমেইল নোটিফিকেশন' : 'Email Notifications',
                      subtitle: _isBn ? 'ইমেইলে বিজ্ঞপ্তি পাঠানো হবে' : 'Notifications will be sent by email',
                      value: _prefs!.emailEnabled,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(emailEnabled: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.sms_outlined,
                      label: _isBn ? 'SMS নোটিফিকেশন' : 'SMS Notifications',
                      subtitle: _isBn ? 'এসএমএসের মাধ্যমে বিজ্ঞপ্তি' : 'Notifications via SMS',
                      value: _prefs!.smsEnabled,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(smsEnabled: v)),
                    ),
                    const SizedBox(height: 24),
                    _sectionHeader(_isBn ? 'বিভাগ' : 'Categories'),
                    _buildSwitch(
                      icon: Icons.work_outline_rounded,
                      label: _isBn ? 'কাজের আপডেট' : 'Job Updates',
                      subtitle: _isBn ? 'জব স্ট্যাটাস পরিবর্তনের বিজ্ঞপ্তি' : 'Notifications for job status changes',
                      value: _prefs!.jobUpdate,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(jobUpdate: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.payment_rounded,
                      label: _isBn ? 'পেমেন্ট' : 'Payment',
                      subtitle: _isBn ? 'লেনদেন ও পেমেন্টের বিজ্ঞপ্তি' : 'Transaction and payment notifications',
                      value: _prefs!.payment,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(payment: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.campaign_outlined,
                      label: _isBn ? 'মার্কেটিং' : 'Marketing',
                      subtitle: _isBn ? 'অফার ও প্রমোশনাল বার্তা' : 'Offers and promotional messages',
                      value: _prefs!.marketing,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(marketing: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.info_outline_rounded,
                      label: _isBn ? 'সিস্টেম' : 'System',
                      subtitle: _isBn ? 'অ্যাপ আপডেট ও গুরুত্বপূর্ণ বার্তা' : 'App updates and important messages',
                      value: _prefs!.system,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(system: v)),
                    ),
                  ],
                ),
      bottomNavigationBar: _prefs == null
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: GlassButton(
                label: _isSaving ? (_isBn ? 'সংরক্ষণ হচ্ছে...' : 'Saving...') : (_isBn ? 'সংরক্ষণ করুন' : 'Save'),
                onPressed: _isSaving ? null : _save,
                              ),
            ),
    );
  }

  Widget _sectionHeader(String text) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1),
      ),
    );
  }

  Widget _buildSwitch({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: SwitchListTile(
            value: value,
            onChanged: onChanged,
            activeColor: colors.primary,
            secondary: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (value ? colors.primary : colors.outline).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: value ? colors.primary : colors.outline, size: 20),
            ),
            title: Text(label, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: TextStyle(color: colors.outline, fontSize: 11)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          ),
        ),
      ),
    );
  }
}
