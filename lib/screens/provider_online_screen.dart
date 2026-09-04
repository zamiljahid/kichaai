import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../services/onboarding_service.dart';
import '../widgets/provider_completeness_gate.dart';
import 'gender_screen.dart';
import '../widgets/animated_background.dart';

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
  // All kinds the live session is currently online for — may be more than just
  // _selectedServiceKind for a master provider (e.g. technician + lawyer at once).
  List<String> _activeServiceKinds = [];
  Map<String, dynamic>? _sessionSummary;
  Position? _lastPosition;

  // Loaded from /onboarding/my-services (approved only) — this used to be a hardcoded list
  // of all 6 kinds, so a technician could pick "photographer" and go online for a service
  // they were never approved for. The backend now rejects that too; this keeps the UI honest.
  List<String> _serviceKinds = [];
  bool _loadingServices = true;
  bool _isBn = true;

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

  // Intentionally no dispose() override here — the location timer lives on
  // DispatchService.instance (an app-lifetime singleton), not on this screen's State, precisely
  // so navigating away from this screen doesn't stop it. Only _goOffline() stops it.

  Future<void> _checkExistingSession() async {
    try {
      final session = await DispatchService.instance.getMySession();
      // The session ROW survives going offline (endSession only flips isOnline=false),
      // so "row exists" is not "online" — that mistake made this screen show অনলাইন
      // even after the provider had gone offline elsewhere.
      if (session.isActive) {
        if (mounted) {
          setState(() {
            _isOnline = true;
            // The backend has always stored `serviceKinds` (an array — a master provider can be
            // online for more than one kind at once); reading a singular `serviceKind` here
            // never matched anything and left this label stuck on the dropdown's default after
            // a cold restart while already online.
            if (session.serviceKinds.isNotEmpty) {
              _selectedServiceKind = session.serviceKinds.first;
              _activeServiceKinds = session.serviceKinds;
            }
          });
          DispatchService.instance.startLocationTracking();
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
    final complete = await ensureProviderCompleteness(context, _isBn);
    if (!complete || !mounted) return;
    if (_serviceKinds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isBn ? 'কোনো অনুমোদিত সার্ভিস নেই — আগে অনবোর্ডিং সম্পন্ন করুন' : 'No approved service — complete onboarding first', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFF59E0B), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _isLoading = true);
    final pos = await _getLocation();
    if (pos == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isBn ? 'লোকেশন অ্যাক্সেস প্রয়োজন' : 'Location access required', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFF59E0B), behavior: SnackBarBehavior.floating),
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
      // startSession REPLACES the session's kind set, it doesn't add to it — sending only the
      // newly picked kind here used to silently drop a master provider's OTHER already-online
      // kinds (e.g. going online for "lawyer" from this screen while a "technician" session was
      // already live elsewhere would quietly take the technician session down too). Merge with
      // whatever's already active first.
      final kinds = {..._activeServiceKinds, _selectedServiceKind}.toList();
      final locationMismatch = await DispatchService.instance.startSession(
        providerId: userId,
        serviceKinds: kinds,
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
          _activeServiceKinds = kinds;
        });
        if (locationMismatch) _showLocationMismatchNotice();
        DispatchService.instance.startLocationTracking();
      }
    } catch (e) {
      final ex = ApiClient.mapError(e);
      if (mounted) {
        setState(() => _isLoading = false);
        // dispatch-service's startLiveSession 400s with this exact bilingual message for a
        // caregiver/photographer/cinematographer/makeup_artist provider with no gender set on
        // their profile — give a direct way to fix it instead of just a red toast.
        if (ex.statusCode == 400 && (ex.messageBn.contains('Gender') || ex.message.contains('Gender'))) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ex.localized(_isBn), style: const TextStyle(color: Colors.white)),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: _isBn ? 'সেট করুন' : 'Set it',
                textColor: Colors.white,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GenderScreen())),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ex.localized(_isBn), style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }

  void _showLocationMismatchNotice() {
    final colors = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(_isBn ? 'অবস্থান নিশ্চিত করুন' : 'Confirm your location', style: TextStyle(color: colors.onSurface)),
        content: Text(
          _isBn
              ? 'আপনার বর্তমান অবস্থান আপনার রেজিস্টার্ড ঠিকানা থেকে অনেক দূরে মনে হচ্ছে। আপনি কি নিশ্চিত আপনি এখন এখানে আছেন?'
              : 'Your current location looks far from your registered address. Are you sure you\'re here right now?',
          style: TextStyle(color: colors.outline),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isBn ? 'হ্যাঁ, ঠিক আছে' : 'Yes, that\'s correct', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _goOffline() async {
    final colors = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(_isBn ? 'অফলাইন হবেন?' : 'Go offline?', style: TextStyle(color: colors.onSurface)),
        content: Text(_isBn ? 'অফলাইনে গেলে নতুন জব পাবেন না।' : 'You won\'t receive new jobs while offline.', style: TextStyle(color: colors.outline)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: TextStyle(color: colors.outline))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'অফলাইন' : 'Offline', style: const TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    DispatchService.instance.stopLocationTracking();
    try {
      final res = await _client.post('/dispatch/sessions/end');
      if (mounted) {
        setState(() {
          _isOnline = false;
          _activeServiceKinds = [];
          _sessionSummary = res.data as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return AnimatedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(_isBn ? 'অনলাইন স্ট্যাটাস' : 'Online Status', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
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
      ),
    );
  }

  Widget _buildToggle() {
    final colors = Theme.of(context).colorScheme;
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
                color: (_isOnline ? const Color(0xFF10B981) : colors.outline).withOpacity(0.3),
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
                          _isOnline ? (_isBn ? 'অনলাইন' : 'Online') : (_isBn ? 'অফলাইন' : 'Offline'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ]),
              ),
            ),
          ),
        ).animate().scale(duration: 400.ms),
        const SizedBox(height: 16),
        Text(
          _isOnline ? (_isBn ? 'নতুন জব পাচ্ছেন' : 'Receiving new jobs') : (_isBn ? 'ট্যাপ করে অনলাইন হন' : 'Tap to go online'),
          style: TextStyle(color: colors.outline, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildServiceSelector() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isBn ? 'সার্ভিস বিভাগ' : 'Service Category', style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (_loadingServices)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: colors.primary, strokeWidth: 2))),
            )
          else if (_serviceKinds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  _isBn ? 'আপনার কোনো অনুমোদিত সার্ভিস নেই — আগে অনবোর্ডিং সম্পন্ন করুন' : 'You have no approved service — complete onboarding first',
                  style: TextStyle(color: colors.outline, fontSize: 13)),
            )
          else
            DropdownButtonFormField<String>(
              value: _serviceKinds.contains(_selectedServiceKind) ? _selectedServiceKind : _serviceKinds.first,
              dropdownColor: colors.surface,
              style: TextStyle(color: colors.onSurface),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.surface,
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
    final colors = Theme.of(context).colorScheme;
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
          Text(_isBn ? 'সেশন সক্রিয়' : 'Session Active', style: const TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w700)),
          Text(
            '${_isBn ? 'সার্ভিস' : 'Service'}: ${_activeServiceKinds.isNotEmpty ? _activeServiceKinds.join(', ') : _selectedServiceKind}',
            style: TextStyle(color: colors.outline, fontSize: 12),
          ),
          if (_lastPosition != null)
            Text('${_isBn ? 'লোকেশন' : 'Location'}: ${_lastPosition!.latitude.toStringAsFixed(4)}, ${_lastPosition!.longitude.toStringAsFixed(4)}', style: TextStyle(color: colors.outline, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _buildSessionSummary() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isBn ? 'সেশন সারাংশ' : 'Session Summary', style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          _summaryCard(_isBn ? 'সময়' : 'Time', '${_sessionSummary!['duration'] ?? 0} ${_isBn ? 'মি' : 'min'}'),
          const SizedBox(width: 12),
          _summaryCard(_isBn ? 'আয়' : 'Earnings', '৳${_sessionSummary!['earnings'] ?? 0}'),
          const SizedBox(width: 12),
          _summaryCard(_isBn ? 'জব' : 'Jobs', '${_sessionSummary!['jobsCompleted'] ?? 0}'),
        ]),
      ]),
    );
  }

  Widget _summaryCard(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: colors.outline, fontSize: 11)),
        ]),
      ),
    );
  }
}
