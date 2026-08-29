import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../services/meal_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

class CreateMealGroupScreen extends StatefulWidget {
  const CreateMealGroupScreen({super.key});

  @override
  State<CreateMealGroupScreen> createState() => _CreateMealGroupScreenState();
}

class _CreateMealGroupScreenState extends State<CreateMealGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _yourNameCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ApiClient.getFullName().then((name) {
      if (mounted && name != null) setState(() => _yourNameCtrl.text = name);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yourNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'গ্রুপের একটা নাম দিন');
      return;
    }
    setState(() { _isSubmitting = true; _error = null; });
    try {
      final group = await MealService.instance.createGroup(
        name: name,
        nameSnapshot: _yourNameCtrl.text.trim().isEmpty ? null : _yourNameCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(group);
    } catch (e) {
      if (mounted) setState(() { _isSubmitting = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('নতুন মিল গ্রুপ')),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: AppColors.blueGradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.deepBlue.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: const Center(child: Text('🏠', style: TextStyle(fontSize: 38))),
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 24),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('গ্রুপের নাম', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: 'যেমন: বাসা ৪২, রোড ৭'),
                    ),
                    const SizedBox(height: 18),
                    const Text('আপনার নাম (গ্রুপে দেখাবে)', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _yourNameCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: 'আপনার নাম'),
                    ),
                  ],
                ),
              ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.1),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.softRed, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              GlassButton(
                label: 'গ্রুপ তৈরি করুন',
                icon: Icons.add_circle_outline_rounded,
                isLoading: _isSubmitting,
                onPressed: _submit,
              ).animate(delay: 200.ms).fadeIn(),
              const SizedBox(height: 12),
              const Text(
                'গ্রুপ তৈরি করার পর একটা ইনভাইট কোড পাবেন — সেটা বাসার বাকিদের পাঠিয়ে দিলেই তারা যোগ দিতে পারবে।',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
