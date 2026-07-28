import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../core/network/api_client.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';

class ProviderOnlineScreen extends StatefulWidget {
  const ProviderOnlineScreen({super.key});

  @override
  State<ProviderOnlineScreen> createState() => _ProviderOnlineScreenState();
}

class _ProviderOnlineScreenState extends State<ProviderOnlineScreen> {
  final _client = ApiClient.instance.dio;
  bool _isOnline = false;
  bool _isLoading = false;
  String _selectedServiceKind = 'technician';
  Map<String, dynamic>? _sessionSummary;
  Timer? _locationTimer;
  Position? _lastPosition;

  // Loaded from /onboarding/my-services (approved only) — this used to be a hardcoded list
  // of all 6 kinds, so a technician could pick "photographer" and go online for a service
  // they were never approved for. The backend now rejects that too; this keeps the UI honest.
  List<String> _serviceKinds = [];
  bool _loadingServices = true;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
    _loadApprovedServices();
  }

  Future<void> _loadApprovedServices() async {
    try {
      final services = await OnboardingService.instance.getMyServices();
      final approved = services
          .where((s) => s['status'] == 'approved')
          .map((s) => (s['serviceTypeId'] as String? ?? '').replaceFirst('st_', ''))
          .where((id) => id.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _serviceKinds = approved;
        _loadingServices = false;
        if (approved.isNotEmpty && !approved.contains(_selectedServiceKind)) {
          _selectedServiceKind = approved.first;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingServices = false);
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    try {
      final res = await _client.get('/dispatch/sessions/me');
      final data = res.data as Map<String, dynamic>?;
      // The session ROW survives going offline (endSession only flips isOnline=false),
      // so "row exists" is not "online" — that mistake made this screen show অনলাইন
      // even after the provider had gone offline elsewhere.
      if (data != null && data['id'] != null && data['isOnline'] == true) {
        if (mounted) {
          setState(() {
            _isOnline = true;
            _selectedServiceKind = data['serviceKind'] as String? ?? _selectedServiceKind;
          });
          _startLocationUpdates();
        }
      }
    } catch (_) {}
  }

  Future<Position?> _getLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied || req == LocationPermission.deniedForever) return null;
      }
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }

  Future<void> _goOnline() async {
    if (_serviceKinds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('কোনো অনুমোদিত সার্ভিস নেই — আগে অনবোর্ডিং সম্পন্ন করুন', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFFF59E0B), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _isLoading = true);
    final pos = await _getLocation();
    if (pos == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('লোকেশন অ্যাক্সেস প্রয়োজন', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFFF59E0B), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    try {
      // This used to post a singular `serviceKind` — the backend contract has always been
      // `serviceKinds` (array), so going online from THIS screen 500'd every time
      // ("Cannot read properties of undefined"). The dashboard toggle already used the
      // right shape; now both go through the same service call. The name/specialization
      // snapshots matter: a technician session without specialization codes receives no
      // specialized jobs at all.
      final userId = await ApiClient.getUserId();
      if (userId == null) throw Exception('user id missing');
      String? name = await ApiClient.getFullName();
      List<String>? specializations;
      try {
        final me = await AuthService.instance.getMeRaw();
        final pp = me['providerProfile'];
        if (pp is Map) {
          name = (pp['displayName'] as String?) ?? name;
          final specs = (pp['specializations'] as List?)?.whereType<String>().toList();
          if (specs != null && specs.isNotEmpty) specializations = specs;
        }
      } catch (_) {}
      await DispatchService.instance.startSession(
        providerId: userId,
        serviceKinds: [_selectedServiceKind],
        currentLatitude: pos.latitude,
        currentLongitude: pos.longitude,
        providerNameSnapshot: name,
        specializations: specializations,
      );
      if (mounted) {
        setState(() {
          _isOnline = true;
          _lastPosition = pos;
          _isLoading = false;
        });
        _startLocationUpdates();
      }
    } catch (e) {
      final ex = ApiClient.mapError(e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ex.messageBn, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _goOffline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: const Text('অফলাইন হবেন?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('অফলাইনে গেলে নতুন জব পাবেন না।', style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('অফলাইন', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    _locationTimer?.cancel();
    try {
      final res = await _client.post('/dispatch/sessions/end');
      if (mounted) {
        setState(() {
          _isOnline = false;
          _sessionSummary = res.data as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final pos = await _getLocation();
      if (pos != null) {
        _lastPosition = pos;
        try {
          await _client.post('/dispatch/sessions/location', data: {
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          });
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('অনলাইন স্ট্যাটাস', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildToggle(),
            const SizedBox(height: 32),
            if (!_isOnline) ...[
              _buildServiceSelector(),
              const SizedBox(height: 24),
            ],
            if (_isOnline) _buildSessionInfo(),
            if (_sessionSummary != null) ...[
              const SizedBox(height: 24),
              _buildSessionSummary(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggle() {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _isOnline
                ? const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)])
                : const LinearGradient(colors: [Color(0xFF374151), Color(0xFF1F2937)]),
            boxShadow: [
              BoxShadow(
                color: (_isOnline ? const Color(0xFF10B981) : AppColors.textMuted).withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(80),
              onTap: _isLoading ? null : (_isOnline ? _goOffline : _goOnline),
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded, color: Colors.white, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          _isOnline ? 'অনলাইন' : 'অফলাইন',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ]),
              ),
            ),
          ),
        ).animate().scale(duration: 400.ms),
        const SizedBox(height: 16),
        Text(
          _isOnline ? 'নতুন জব পাচ্ছেন' : 'ট্যাপ করে অনলাইন হন',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildServiceSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('সার্ভিস বিভাগ', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (_loadingServices)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.deepBlue, strokeWidth: 2))),
            )
          else if (_serviceKinds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('আপনার কোনো অনুমোদিত সার্ভিস নেই — আগে অনবোর্ডিং সম্পন্ন করুন',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            DropdownButtonFormField<String>(
              value: _serviceKinds.contains(_selectedServiceKind) ? _selectedServiceKind : _serviceKinds.first,
              dropdownColor: AppColors.bgMid,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.glassWhite,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: _serviceKinds.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
              onChanged: (v) => setState(() => _selectedServiceKind = v ?? _selectedServiceKind),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.location_on_rounded, color: Color(0xFF10B981), size: 22),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('সেশন সক্রিয়', style: TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w700)),
          Text('সার্ভিস: $_selectedServiceKind', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          if (_lastPosition != null)
            Text('লোকেশন: ${_lastPosition!.latitude.toStringAsFixed(4)}, ${_lastPosition!.longitude.toStringAsFixed(4)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _buildSessionSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('সেশন সারাংশ', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          _summaryCard('সময়', '${_sessionSummary!['duration'] ?? 0} মি'),
          const SizedBox(width: 12),
          _summaryCard('আয়', '৳${_sessionSummary!['earnings'] ?? 0}'),
          const SizedBox(width: 12),
          _summaryCard('জব', '${_sessionSummary!['jobsCompleted'] ?? 0}'),
        ]),
      ]),
    );
  }

  Widget _summaryCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
      ),
    );
  }
}
