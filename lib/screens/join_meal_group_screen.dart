import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../services/meal_service.dart';
import '../theme/app_gradients.dart';
import '../theme/status_colors.dart';
import '../widgets/glass_button.dart';

const _kCodeLength = 6;

/// Manual code entry — also the landing target for the kichaai://meal/join/<code>
/// deep link (pass [initialCode] to pre-fill and auto-submit).
class JoinMealGroupScreen extends StatefulWidget {
  final String? initialCode;
  const JoinMealGroupScreen({super.key, this.initialCode});

  @override
  State<JoinMealGroupScreen> createState() => _JoinMealGroupScreenState();
}

class _JoinMealGroupScreenState extends State<JoinMealGroupScreen> {
  late final List<TextEditingController> _charCtrls =
      List.generate(_kCodeLength, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes = List.generate(_kCodeLength, (_) => FocusNode());
  final _yourNameCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ApiClient.getFullName().then((name) {
      if (mounted && name != null) setState(() => _yourNameCtrl.text = name);
    });
    final initial = widget.initialCode?.toUpperCase().trim();
    if (initial != null && initial.length == _kCodeLength) {
      for (int i = 0; i < _kCodeLength; i++) {
        _charCtrls[i].text = initial[i];
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  @override
  void dispose() {
    for (final c in _charCtrls) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _yourNameCtrl.dispose();
    super.dispose();
  }

  String get _code => _charCtrls.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (value.isNotEmpty && index < _kCodeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final code = _code;
    if (code.length != _kCodeLength) {
      setState(() => _error = 'পুরো ৬ ডিজিটের কোড দিন');
      return;
    }
    setState(() { _isSubmitting = true; _error = null; });
    try {
      final (group, alreadyMember) = await MealService.instance.joinGroup(
        inviteCode: code,
        nameSnapshot: _yourNameCtrl.text.trim().isEmpty ? null : _yourNameCtrl.text.trim(),
      );
      if (!mounted) return;
      if (alreadyMember) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('আপনি আগে থেকেই এই গ্রুপের সদস্য'),
          backgroundColor: StatusColors.blue,
        ));
      }
      Navigator.of(context).pop(group);
    } catch (e) {
      if (mounted) setState(() { _isSubmitting = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(title: const Text('কোড দিয়ে যোগ দিন')),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppGradients.background(colors)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text('🔑', style: TextStyle(fontSize: 56))
                  .animate()
                  .scale(duration: 400.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 16),
              Text(
                'গ্রুপ ম্যানেজারের দেওয়া ৬ অক্ষরের কোডটি লিখুন',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_kCodeLength, (i) => _buildCodeBox(i)),
              ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.1),
              const SizedBox(height: 20),
              TextField(
                controller: _yourNameCtrl,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurface),
                decoration: const InputDecoration(hintText: 'আপনার নাম (গ্রুপে দেখাবে)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colors.error, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              GlassButton(
                label: 'যোগ দিন',
                icon: Icons.login_rounded,
                isLoading: _isSubmitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeBox(int index) {
    final colors = Theme.of(context).colorScheme;
    final filled = _charCtrls[index].text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 42,
        height: 52,
        child: TextField(
          controller: _charCtrls[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          maxLength: 1,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: colors.onSurface, fontSize: 22, fontWeight: FontWeight.w700),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
            UpperCaseTextFormatter(),
          ],
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: filled ? colors.primary.withValues(alpha: 0.08) : colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: filled ? colors.primary : colors.outlineVariant, width: filled ? 1.5 : 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: filled ? colors.primary : colors.outlineVariant, width: filled ? 1.5 : 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
          ),
          onChanged: (v) => _onChanged(index, v),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
