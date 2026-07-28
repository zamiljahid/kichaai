import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/network/api_client.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
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
          const SnackBar(
            content: Text('সেটিংস সংরক্ষিত হয়েছে', style: TextStyle(color: Colors.white)),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString(), style: const TextStyle(color: Colors.white)),
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
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('নোটিফিকেশন সেটিংস', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : _prefs == null
              ? const Center(child: Text('লোড করা যায়নি', style: TextStyle(color: AppColors.textMuted)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    _sectionHeader('চ্যানেল'),
                    _buildSwitch(
                      icon: Icons.notifications_active_outlined,
                      label: 'পুশ নোটিফিকেশন',
                      subtitle: 'অ্যাপের মাধ্যমে সরাসরি বিজ্ঞপ্তি',
                      value: _prefs!.pushEnabled,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(pushEnabled: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.email_outlined,
                      label: 'ইমেইল নোটিফিকেশন',
                      subtitle: 'ইমেইলে বিজ্ঞপ্তি পাঠানো হবে',
                      value: _prefs!.emailEnabled,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(emailEnabled: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.sms_outlined,
                      label: 'SMS নোটিফিকেশন',
                      subtitle: 'এসএমএসের মাধ্যমে বিজ্ঞপ্তি',
                      value: _prefs!.smsEnabled,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(smsEnabled: v)),
                    ),
                    const SizedBox(height: 24),
                    _sectionHeader('বিভাগ'),
                    _buildSwitch(
                      icon: Icons.work_outline_rounded,
                      label: 'কাজের আপডেট',
                      subtitle: 'জব স্ট্যাটাস পরিবর্তনের বিজ্ঞপ্তি',
                      value: _prefs!.jobUpdate,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(jobUpdate: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.payment_rounded,
                      label: 'পেমেন্ট',
                      subtitle: 'লেনদেন ও পেমেন্টের বিজ্ঞপ্তি',
                      value: _prefs!.payment,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(payment: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.campaign_outlined,
                      label: 'মার্কেটিং',
                      subtitle: 'অফার ও প্রমোশনাল বার্তা',
                      value: _prefs!.marketing,
                      onChanged: (v) => setState(() => _prefs = _prefs!.copyWith(marketing: v)),
                    ),
                    _buildSwitch(
                      icon: Icons.info_outline_rounded,
                      label: 'সিস্টেম',
                      subtitle: 'অ্যাপ আপডেট ও গুরুত্বপূর্ণ বার্তা',
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
                color: AppColors.bgDark,
                border: Border(top: BorderSide(color: AppColors.glassBorder)),
              ),
              child: GlassButton(
                label: _isSaving ? 'সংরক্ষণ হচ্ছে...' : 'সংরক্ষণ করুন',
                onPressed: _isSaving ? null : _save,
                              ),
            ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: SwitchListTile(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.deepBlue,
            secondary: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (value ? AppColors.deepBlue : AppColors.textMuted).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: value ? AppColors.deepBlue : AppColors.textMuted, size: 20),
            ),
            title: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          ),
        ),
      ),
    );
  }
}
