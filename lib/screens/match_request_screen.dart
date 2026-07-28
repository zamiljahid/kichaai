import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

class MatchRequestScreen extends StatefulWidget {
  final String providerId;
  final String kind;
  const MatchRequestScreen({super.key, required this.providerId, required this.kind});

  @override
  State<MatchRequestScreen> createState() => _MatchRequestScreenState();
}

class _MatchRequestScreenState extends State<MatchRequestScreen> {
  // requestType ('tutor'/'pet_care'/'mess_finder') → the serviceTypeId the backend requires.
  static const _serviceTypeIds = {
    'tutor': 'st_home_tutor',
    'pet_care': 'st_pet_care',
    'mess_finder': 'st_mess_finder',
  };
  static const _titles = {
    'tutor': 'হোম টিউটর অনুরোধ',
    'pet_care': 'পেট কেয়ার অনুরোধ',
    'mess_finder': 'মেস/আবাসন অনুরোধ',
  };
  static const _expiryOptions = [3, 7, 14, 30];

  final _descController = TextEditingController();
  final _budgetController = TextEditingController();
  DateTime? _preferredDate;
  double? _latitude;
  double? _longitude;
  bool _isLocating = false;
  bool _locationDetected = false;
  bool _isSubmitting = false;
  int _expiresInDays = 7;

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  @override
  void dispose() {
    _descController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      bool ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) { setState(() => _isLocating = false); return; }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _isLocating = false); return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() { _latitude = pos.latitude; _longitude = pos.longitude; _locationDetected = true; _isLocating = false; });
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.deepBlue)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _preferredDate = picked);
  }

  Future<void> _submit() async {
    if (_descController.text.trim().isEmpty) { _showError('বিবরণ লিখুন'); return; }

    final serviceTypeId = _serviceTypeIds[widget.kind];
    if (serviceTypeId == null) { _showError('অজানা সেবার ধরন'); return; }

    final budget = double.tryParse(_budgetController.text.trim());
    setState(() => _isSubmitting = true);
    try {
      final request = await MatchmakingService.instance.createRequest(
        requestType: widget.kind,
        serviceTypeId: serviceTypeId,
        title: _titles[widget.kind] ?? 'অনুরোধ',
        description: _descController.text.trim(),
        budgetMin: budget,
        budgetMax: budget,
        preferredStartDate: _preferredDate?.toIso8601String(),
        serviceLatitude: _latitude,
        serviceLongitude: _longitude,
      );
      // draft → open, otherwise no provider will ever see this request.
      await MatchmakingService.instance.publishRequest(request.id, expiresInDays: _expiresInDays);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('অনুরোধ পাঠানো হয়েছে!', style: TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory)),
      backgroundColor: const Color(0xFFEF4444),
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
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('বিস্তারিত লিখুন'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descController,
                          maxLines: 4,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                          decoration: const InputDecoration(hintText: 'আপনার প্রয়োজন বিস্তারিত লিখুন...'),
                        ),
                        const SizedBox(height: 20),
                        _label('পছন্দের তারিখ'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppColors.glassWhite,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _preferredDate != null ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
                            ),
                            child: Row(children: [
                              Icon(Icons.calendar_today_rounded, color: _preferredDate != null ? AppColors.deepBlue : AppColors.textMuted, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                _preferredDate != null
                                    ? '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}'
                                    : 'তারিখ বেছে নিন',
                                style: TextStyle(color: _preferredDate != null ? AppColors.textPrimary : AppColors.textMuted, fontSize: 14),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _label('বাজেট (টাকা)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _budgetController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'আনুমানিক বাজেট',
                            prefixIcon: Icon(Icons.currency_exchange_rounded, color: AppColors.textMuted, size: 20),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _label('কতদিন খোলা রাখতে চান?'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: _expiryOptions.map((days) {
                            final active = _expiresInDays == days;
                            return GestureDetector(
                              onTap: () => setState(() => _expiresInDays = days),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: active ? AppColors.blueGradient : null,
                                  color: active ? null : AppColors.glassWhite,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: active ? AppColors.deepBlue : AppColors.glassBorder,
                                    width: active ? 1.5 : 1,
                                  ),
                                ),
                                child: Text(
                                  '$days দিন',
                                  style: TextStyle(
                                    color: active ? AppColors.ivory : AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        _label('অবস্থান'),
                        const SizedBox(height: 8),
                        _isLocating
                            ? Row(children: [
                                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue)),
                                const SizedBox(width: 10),
                                Text('অবস্থান খুঁজছে...', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                              ])
                            : _locationDetected
                                ? Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4), width: 1.5),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.location_pin, color: Color(0xFF22C55E), size: 18),
                                      const SizedBox(width: 8),
                                      Text('অবস্থান শনাক্ত হয়েছে', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.w600)),
                                    ]),
                                  )
                                : GestureDetector(
                                    onTap: _detectLocation,
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
                                      child: Row(children: [
                                        const Icon(Icons.location_off_rounded, color: AppColors.textMuted, size: 18),
                                        const SizedBox(width: 8),
                                        Text('অবস্থান চালু করুন', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                      ]),
                                    ),
                                  ),
                        const SizedBox(height: 24),
                        GlassButton(label: 'অনুরোধ পাঠান', isLoading: _isSubmitting, onPressed: _submit),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('অনুরোধ পাঠান', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Send Request', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _label(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
  );
}
