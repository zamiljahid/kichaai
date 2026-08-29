import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/cook_model.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/cook_service.dart';
import '../services/messaging_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import 'chat_screen.dart';
import 'photographer_profile_screen.dart' show sectionCard, labeledField, uploadRow;

const _kActiveJobStatuses = {'confirmed', 'preparing', 'ready_for_pickup'};

const _kDayLabelsBn = ['সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'];
const _kDayLabelsEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class CookProviderScreen extends StatefulWidget {
  const CookProviderScreen({super.key});

  @override
  State<CookProviderScreen> createState() => _CookProviderScreenState();
}

class _CookProviderScreenState extends State<CookProviderScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isBn = true;

  List<CookAvailabilityModel> _availability = [];
  bool _availLoading = true;

  List<CookRequestModel> _openRequests = [];
  bool _openLoading = true;
  final _areaFilterCtrl = TextEditingController();

  List<Map<String, dynamic>> _myJobs = [];
  bool _jobsLoading = true;

  bool _applied = false;
  bool _nidVerified = false;
  bool _statusLoading = true;
  String? _openingChatRequestId;

  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStatus();
    _loadAvailability();
    _loadOpenRequests();
    _loadMyJobs();
    // Only pings while this screen is open (foreground) — a full background tracking service
    // is a bigger scope than "show the customer where their food is" needs right now.
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (_) => _shareLocationForActiveJobs());
  }

  Future<void> _loadStatus() async {
    setState(() => _statusLoading = true);
    try {
      final status = await CookService.instance.getMyProviderStatus();
      if (mounted) setState(() {
        _applied = status['applied'] as bool? ?? false;
        _nidVerified = status['nidVerified'] as bool? ?? false;
        _statusLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  Future<void> _openOnboardingForm() async {
    final submitted = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CookOnboardingScreen()));
    if (submitted == true) {
      _showSuccess(_isBn ? 'প্রোফাইল জমা দেওয়া হয়েছে — এডমিন শীঘ্রই যাচাই করবেন' : 'Profile submitted — an admin will verify you soon');
      await _loadStatus();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _areaFilterCtrl.dispose();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _shareLocationForActiveJobs() async {
    final activeRequestIds = _myJobs
        .where((c) {
          final req = c['request'] as Map<String, dynamic>?;
          final status = req?['status'] as String?;
          final isFinalized = req != null && req['confirmedResponseId'] == c['id'];
          return isFinalized && status != null && _kActiveJobStatuses.contains(status);
        })
        .map((c) => (c['request'] as Map<String, dynamic>)['id'] as String)
        .toList();
    if (activeRequestIds.isEmpty) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      for (final id in activeRequestIds) {
        CookService.instance.updateProviderLocation(id, position.latitude, position.longitude).catchError((_) {});
      }
    } catch (_) {
      // Best-effort — a missed location ping just means the customer's map is a bit stale.
    }
  }

  Future<void> _loadAvailability() async {
    setState(() => _availLoading = true);
    try {
      final list = await CookService.instance.getMyAvailability();
      if (mounted) setState(() { _availability = list; _availLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _availLoading = false);
    }
  }

  Future<void> _loadOpenRequests() async {
    setState(() => _openLoading = true);
    try {
      final list = await CookService.instance.listOpenRequests(pickupArea: _areaFilterCtrl.text.trim().isEmpty ? null : _areaFilterCtrl.text.trim());
      if (mounted) setState(() { _openRequests = list; _openLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _openLoading = false);
    }
  }

  Future<void> _loadMyJobs() async {
    setState(() => _jobsLoading = true);
    try {
      final list = await CookService.instance.listMyConfirmations();
      if (mounted) setState(() { _myJobs = list; _jobsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _jobsLoading = false);
    }
  }

  Future<void> _addRecurringSlot() async {
    int day = 0;
    TimeOfDay start = const TimeOfDay(hour: 17, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 21, minute: 0);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'সাপ্তাহিক সময়' : 'Recurring slot', style: const TextStyle(color: AppColors.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButton<int>(
            value: day,
            dropdownColor: AppColors.bgMid,
            isExpanded: true,
            items: List.generate(7, (i) => DropdownMenuItem(value: i, child: Text(_isBn ? _kDayLabelsBn[i] : _kDayLabelsEn[i], style: const TextStyle(color: AppColors.textPrimary)))),
            onChanged: (v) => setD(() => day = v!),
          ),
          Row(children: [
            Expanded(child: TextButton(onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: start); if (t != null) setD(() => start = t); }, child: Text('${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'))),
            const Text('—'),
            Expanded(child: TextButton(onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: end); if (t != null) setD(() => end = t); }, child: Text('${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}'))),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'সংরক্ষণ' : 'Save')),
        ],
      )),
    );
    if (saved != true) return;
    try {
      await CookService.instance.setRecurringAvailability(
        dayOfWeek: day,
        startTime: '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
        endTime: '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
      );
      await _loadAvailability();
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _addBlackout() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 60)));
    if (date == null) return;
    try {
      await CookService.instance.setAvailabilityOverride(specificDate: date, isBlackout: true);
      await _loadAvailability();
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _confirmRequest(CookRequestModel req) async {
    final ctrl = TextEditingController(text: req.budgetAmount?.toStringAsFixed(0) ?? '');
    final quoted = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'দাম প্রস্তাব করুন' : 'Quote a price', style: const TextStyle(color: AppColors.textPrimary)),
        content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: AppColors.textPrimary), decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_isBn ? 'বাতিল' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: Text(_isBn ? 'পাঠান' : 'Send')),
        ],
      ),
    );
    if (quoted == null) return;
    try {
      await CookService.instance.confirmRequest(req.id, quotedAmount: quoted);
      _showSuccess(_isBn ? 'সাড়া পাঠানো হয়েছে' : 'Response sent');
      await Future.wait([_loadOpenRequests(), _loadMyJobs()]);
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _updateStatus(String requestId, String status) async {
    try {
      await CookService.instance.updateConfirmationStatus(requestId, status);
      await _loadMyJobs();
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _cancelConfirmation(String requestId) async {
    try {
      await CookService.instance.cancelConfirmation(requestId);
      await _loadMyJobs();
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _openChat(String requestId) async {
    setState(() => _openingChatRequestId = requestId);
    try {
      final user = await AuthService.instance.getCurrentUser();
      final threads = await MessagingService.instance.listThreads(user.id);
      ThreadModel? thread;
      for (final t in threads) {
        if (t.serviceRequestId == requestId) { thread = t; break; }
      }
      if (!mounted) return;
      if (thread == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'চ্যাট এখনো তৈরি হয়নি — একটু পরে আবার চেষ্টা করুন' : 'Chat not created yet — try again shortly', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      final otherName = thread.otherParticipantName(user.id);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(threadId: thread!.id, currentUserId: user.id, participantName: otherName),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'চ্যাট খোলা যায়নি' : 'Could not open chat', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _openingChatRequestId = null);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16)));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16)));
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMid,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18), onPressed: () => Navigator.of(context).pop()),
        title: Text(_isBn ? 'রাঁধুনি ড্যাশবোর্ড' : 'Cook Dashboard', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.deepBlue,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.deepBlue,
          isScrollable: true,
          tabs: [Tab(text: _isBn ? 'সময়সূচি' : 'Availability'), Tab(text: _isBn ? 'খোলা রিকোয়েস্ট' : 'Open Requests'), Tab(text: _isBn ? 'আমার কাজ' : 'My Jobs')],
        ),
      ),
      body: Column(children: [
        _buildOnDemandNotice(),
        _buildVerificationBanner(),
        Expanded(child: TabBarView(controller: _tabController, children: [_buildAvailabilityTab(), _buildOpenTab(), _buildJobsTab()])),
      ]),
    );
  }

  /// Cook has the same two-surface split rides do: this screen is the SCHEDULED side
  /// (availability, recurring requests), while "I need a cook now" is broadcast through
  /// dispatch and lands on the provider dashboard as an offer. Nothing said so before.
  Widget _buildOnDemandNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.glassBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorderBlue),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.deepBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isBn
                  ? 'এখানে শিডিউল করা রান্নার কাজ। এখনই দরকার — এমন অর্ডার পেতে ড্যাশবোর্ড থেকে অনলাইন হোন।'
                  : 'This is for scheduled cooking work. For on-demand orders, go online from your dashboard.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBanner() {
    if (_statusLoading) return const SizedBox.shrink();
    if (_nidVerified) return const SizedBox.shrink();

    final color = _applied ? const Color(0xFFF59E0B) : AppColors.deepBlue;
    final title = _applied
        ? (_isBn ? 'যাচাইকরণ অপেক্ষমাণ' : 'Verification pending')
        : (_isBn ? 'রাঁধুনি হিসেবে যাচাই করা হয়নি' : 'Not yet verified as a provider');
    final body = _applied
        ? (_isBn ? 'এডমিন আপনার আবেদন রিভিউ করছেন — যাচাই না হওয়া পর্যন্ত অর্ডার কনফার্ম করতে পারবেন না।' : 'An admin is reviewing your application — you can\'t confirm orders until verified.')
        : (_isBn ? 'রিকোয়েস্ট কনফার্ম করতে হলে আগে যাচাইয়ের জন্য আবেদন করুন।' : 'Apply for verification before you can confirm requests.');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(_applied ? Icons.hourglass_top_rounded : Icons.verified_user_outlined, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ]),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _openOnboardingForm,
          child: Text(
            _applied ? (_isBn ? 'আবেদন সম্পাদনা' : 'Edit application') : (_isBn ? 'প্রোফাইল সম্পন্ন করুন' : 'Complete profile'),
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ]),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildAvailabilityTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: GlassButton(label: _isBn ? '+ সাপ্তাহিক সময়' : '+ Recurring slot', onPressed: _addRecurringSlot)),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: _addBlackout, style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.glassBorder), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text(_isBn ? '+ ছুটি' : '+ Blackout day', style: const TextStyle(color: AppColors.textPrimary)))),
        ]),
      ),
      Expanded(
        child: _availLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
            : _availability.isEmpty
                ? Center(child: Text(_isBn ? 'কোনো সময়সূচি নেই' : 'No availability set', style: const TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    itemCount: _availability.length,
                    itemBuilder: (ctx, i) {
                      final a = _availability[i];
                      final label = a.specificDate != null
                          ? '${a.specificDate!.day}/${a.specificDate!.month}/${a.specificDate!.year}${a.isBlackout ? (_isBn ? " (ছুটি)" : " (blackout)") : ""}'
                          : (_isBn ? _kDayLabelsBn[a.dayOfWeek ?? 0] : _kDayLabelsEn[a.dayOfWeek ?? 0]);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
                        child: Row(children: [
                          Icon(a.isBlackout ? Icons.block_rounded : Icons.schedule_rounded, color: a.isBlackout ? const Color(0xFFEF4444) : AppColors.deepBlue, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600))),
                          if (!a.isBlackout) Text('${a.startTime} - ${a.endTime}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ]),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _buildOpenTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _areaFilterCtrl,
          onSubmitted: (_) => _loadOpenRequests(),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: _isBn ? 'এলাকা দিয়ে খুঁজুন' : 'Search by area',
            suffixIcon: IconButton(icon: const Icon(Icons.search, color: AppColors.textMuted), onPressed: _loadOpenRequests),
            filled: true, fillColor: AppColors.glassWhite,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.glassBorder)),
          ),
        ),
      ),
      Expanded(
        child: _openLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
            : _openRequests.isEmpty
                ? Center(child: Text(_isBn ? 'কোনো খোলা রিকোয়েস্ট নেই' : 'No open requests', style: const TextStyle(color: AppColors.textMuted)))
                : RefreshIndicator(
                    onRefresh: _loadOpenRequests,
                    color: AppColors.deepBlue,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      itemCount: _openRequests.length,
                      itemBuilder: (ctx, i) {
                        final r = _openRequests[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.dishName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('${r.quantity} · ${r.pickupArea}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            Text('${r.windowStart} - ${r.windowEnd}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            if (r.budgetAmount != null) Text('৳${r.budgetAmount!.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            GlassButton(label: _isBn ? 'সাড়া দিন' : 'Respond', onPressed: () => _confirmRequest(r), width: double.infinity),
                          ]),
                        ).animate(delay: Duration(milliseconds: 40 * i)).fadeIn(duration: 250.ms);
                      },
                    ),
                  ),
      ),
    ]);
  }

  Widget _buildJobsTab() {
    if (_jobsLoading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_myJobs.isEmpty) return Center(child: Text(_isBn ? 'কোনো কাজ নেই' : 'No jobs yet', style: const TextStyle(color: AppColors.textMuted)));
    return RefreshIndicator(
      onRefresh: _loadMyJobs,
      color: AppColors.deepBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _myJobs.length,
        itemBuilder: (ctx, i) {
          final c = _myJobs[i];
          final req = c['request'] as Map<String, dynamic>?;
          if (req == null) return const SizedBox.shrink();
          final requestId = req['id'] as String;
          final requestStatus = req['status'] as String? ?? '';
          final confirmationStatus = c['status'] as String? ?? '';
          final isFinalized = req['confirmedResponseId'] == c['id'];
          final canCancel = confirmationStatus == 'confirmed';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(req['dishName'] as String? ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Text(confirmationStatus.replaceAll('_', ' '), style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              Text('${req['pickupArea'] ?? ''}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (isFinalized) ...[
                const SizedBox(height: 4),
                Text(_isBn ? 'রিকোয়েস্ট স্ট্যাটাস: $requestStatus' : 'Request status: $requestStatus', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                if (req['customerPhoneSnapshot'] != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 18),
                    const SizedBox(width: 8),
                    Text(req['customerPhoneSnapshot'] as String, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  ]),
                ],
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _openingChatRequestId == requestId ? null : () => _openChat(requestId),
                  child: Row(children: [
                    _openingChatRequestId == requestId
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                        : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.deepBlue, size: 16),
                    const SizedBox(width: 8),
                    Text(_isBn ? 'গ্রাহকের সাথে চ্যাট করুন' : 'Chat with customer', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
              if (isFinalized || canCancel) ...[
                const SizedBox(height: 12),
                Row(children: [
                  if (isFinalized && requestStatus == 'confirmed')
                    Expanded(child: OutlinedButton(onPressed: () => _updateStatus(requestId, 'preparing'), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.deepBlue), padding: const EdgeInsets.symmetric(vertical: 12)), child: Text(_isBn ? 'রান্না শুরু' : 'Start preparing', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)))),
                  if (isFinalized && requestStatus == 'preparing') ...[
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: () => _updateStatus(requestId, 'ready_for_pickup'), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.deepBlue), padding: const EdgeInsets.symmetric(vertical: 12)), child: Text(_isBn ? 'প্রস্তুত' : 'Ready for pickup', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)))),
                  ],
                  if (canCancel && requestStatus != 'completed' && requestStatus != 'cancelled') ...[
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: () => _cancelConfirmation(requestId), style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFEF4444)), padding: const EdgeInsets.symmetric(vertical: 12)), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)))),
                  ],
                ]),
              ],
            ]),
          ).animate(delay: Duration(milliseconds: 40 * i)).fadeIn(duration: 250.ms);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Become a cook" full onboarding form — NID docs, guardian contact, cooking
// specialty, home address, per-dish pricing table, platform-pricing choice,
// and the time-penalty/red-card policy acknowledgment. Reachable from the
// verification banner's "Complete profile" / "Edit application" action.
// Kept as its own screen (pushed via Navigator) rather than inlined into the
// dashboard's tabs — the dashboard is already a 3-tab shell and this form has
// enough fields (2 uploads + 5 text inputs + a repeatable table + a policy
// checkbox) to deserve its own scroll/submit flow.
// ─────────────────────────────────────────────────────────────────────────────

class _CookMenuItemRow {
  final nameCtrl = TextEditingController();
  final quantityCtrl = TextEditingController();
  final rateCtrl = TextEditingController();
  final prepTimeCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    quantityCtrl.dispose();
    rateCtrl.dispose();
    prepTimeCtrl.dispose();
  }
}

class CookOnboardingScreen extends StatefulWidget {
  const CookOnboardingScreen({super.key});

  @override
  State<CookOnboardingScreen> createState() => _CookOnboardingScreenState();
}

class _CookOnboardingScreenState extends State<CookOnboardingScreen> {
  bool _isBn = true;

  String? _profilePhotoUrl;
  bool _uploadingProfilePhoto = false;

  final _ownPhoneCtrl = TextEditingController();

  String? _ownNidUrl;
  bool _uploadingOwnNid = false;
  String? _guardianNidUrl;
  bool _uploadingGuardianNid = false;

  final _guardianPhoneCtrl = TextEditingController();
  final _specialtyCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _acceptsPlatformPricing = true;

  final List<_CookMenuItemRow> _menuItems = [_CookMenuItemRow()];

  bool _policyAcknowledged = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _prefillFromAccount();
  }

  Future<void> _prefillFromAccount() async {
    try {
      final user = await AuthService.instance.getCurrentUser();
      if (!mounted) return;
      setState(() => _ownPhoneCtrl.text = user.phone ?? '');
    } catch (_) {}
  }

  @override
  void dispose() {
    _ownPhoneCtrl.dispose();
    _guardianPhoneCtrl.dispose();
    _specialtyCtrl.dispose();
    _addressCtrl.dispose();
    for (final m in _menuItems) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _uploadProfilePhoto() async {
    setState(() => _uploadingProfilePhoto = true);
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final url = await AuthService.instance.uploadProviderProfilePhoto(base64Encode(bytes));
      if (mounted) setState(() => _profilePhotoUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingProfilePhoto = false);
    }
  }

  Future<String?> _pickAndUpload() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    final ext = f.name.split('.').last.toLowerCase();
    final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
    return OnboardingService.instance.uploadFile(fileBase64: base64Encode(bytes), fileName: f.name, mimeType: mime);
  }

  Future<void> _uploadOwnNid() async {
    setState(() => _uploadingOwnNid = true);
    try {
      final url = await _pickAndUpload();
      if (url != null && mounted) setState(() => _ownNidUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingOwnNid = false);
    }
  }

  Future<void> _uploadGuardianNid() async {
    setState(() => _uploadingGuardianNid = true);
    try {
      final url = await _pickAndUpload();
      if (url != null && mounted) setState(() => _guardianNidUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingGuardianNid = false);
    }
  }

  Future<void> _submit() async {
    if (_profilePhotoUrl == null) {
      _snack(_isBn ? 'আপনার প্রোফাইল ছবি আপলোড করুন' : 'Upload your profile picture', error: true);
      return;
    }
    if (_ownPhoneCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'আপনার নিজের ফোন নম্বর লিখুন' : 'Enter your own phone number', error: true);
      return;
    }
    if (_ownNidUrl == null) {
      _snack(_isBn ? 'আপনার নিজের NID আপলোড করুন' : 'Upload your own NID', error: true);
      return;
    }
    if (_guardianNidUrl == null) {
      _snack(_isBn ? 'বাবা/স্বামীর NID আপলোড করুন' : "Upload your father's/husband's NID", error: true);
      return;
    }
    if (_guardianPhoneCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'বাবা/স্বামীর ফোন নম্বর লিখুন' : "Enter your father's/husband's phone number", error: true);
      return;
    }
    if (_specialtyCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'আপনি কী কী রান্না ভালো পারেন লিখুন' : 'Describe the dishes you cook well', error: true);
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'আপনার বাসার ঠিকানা লিখুন' : 'Enter your home address', error: true);
      return;
    }

    final menuItems = <Map<String, dynamic>>[];
    for (final row in _menuItems) {
      final name = row.nameCtrl.text.trim();
      final quantity = row.quantityCtrl.text.trim();
      final rateText = row.rateCtrl.text.trim();
      if (name.isEmpty && quantity.isEmpty && rateText.isEmpty) continue; // skip a fully-blank spare row
      if (name.isEmpty || quantity.isEmpty || rateText.isEmpty) {
        _snack(_isBn ? 'প্রতিটি পদের নাম, পরিমাণ ও দাম পূরণ করুন' : 'Fill in the name, quantity, and rate for every dish row', error: true);
        return;
      }
      final rate = double.tryParse(rateText);
      if (rate == null || rate <= 0) {
        _snack(_isBn ? '"$name" এর জন্য সঠিক দাম লিখুন' : 'Enter a valid rate for "$name"', error: true);
        return;
      }
      final prepText = row.prepTimeCtrl.text.trim();
      final prepTime = prepText.isEmpty ? null : int.tryParse(prepText);
      menuItems.add({
        'itemName': name,
        'quantity': quantity,
        'expectedRate': rate,
        if (prepTime != null) 'prepTimeMinutes': prepTime,
      });
    }
    if (menuItems.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি পদ যোগ করুন' : 'Add at least one dish', error: true);
      return;
    }
    if (!_policyAcknowledged) {
      _snack(_isBn ? 'শুরু করার আগে নীতিমালা মেনে নেওয়ার বক্সে টিক দিন' : 'Please acknowledge the policy before submitting', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await AuthService.instance.updateProfile(phone: _ownPhoneCtrl.text.trim());
      await CookService.instance.submitCookProfile(
        ownNidUrl: _ownNidUrl!,
        guardianNidUrl: _guardianNidUrl!,
        guardianPhone: _guardianPhoneCtrl.text.trim(),
        cookingSpecialty: _specialtyCtrl.text.trim(),
        homeAddress: _addressCtrl.text.trim(),
        acceptsPlatformPricing: _acceptsPlatformPricing,
        policyAcknowledged: _policyAcknowledged,
        menuItems: menuItems,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMid,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18), onPressed: () => Navigator.of(context).pop()),
        title: Text(_isBn ? 'রাঁধুনি হিসেবে যোগ দিন' : 'Become a Cook', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sectionCard(
            title: _isBn ? 'প্রোফাইল ছবি' : 'Profile picture',
            child: Row(children: [
              GestureDetector(
                onTap: _uploadProfilePhoto,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.glassWhite,
                    border: Border.all(color: _profilePhotoUrl != null ? const Color(0xFF10B981) : AppColors.glassBorder, width: 1.5),
                    image: _profilePhotoUrl != null ? DecorationImage(image: NetworkImage(_profilePhotoUrl!), fit: BoxFit.cover) : null,
                  ),
                  child: _uploadingProfilePhoto
                      ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : (_profilePhotoUrl == null ? const Icon(Icons.add_a_photo_rounded, color: AppColors.textMuted, size: 24) : null),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _profilePhotoUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'একটি স্পষ্ট প্রোফাইল ছবি আপলোড করুন — গ্রাহকরা এটা দেখতে পাবেন' : 'Upload a clear profile photo — customers will see this'),
                  style: TextStyle(color: _profilePhotoUrl != null ? const Color(0xFF10B981) : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'আপনার ফোন নম্বর' : 'Your phone number',
            child: labeledField(controller: _ownPhoneCtrl, hint: _isBn ? 'নিজের ফোন নম্বর' : 'Your own phone number', keyboardType: TextInputType.phone),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'আপনার NID' : 'Your NID',
            child: uploadRow(
              label: _ownNidUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'নিজের NID এর ছবি আপলোড করুন' : 'Upload a photo of your own NID'),
              uploaded: _ownNidUrl != null,
              loading: _uploadingOwnNid,
              onTap: _uploadOwnNid,
            ),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'বাবা/স্বামীর NID' : "Father's/Husband's NID",
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              uploadRow(
                label: _guardianNidUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'NID এর ছবি আপলোড করুন' : 'Upload a photo of the NID'),
                uploaded: _guardianNidUrl != null,
                loading: _uploadingGuardianNid,
                onTap: _uploadGuardianNid,
              ),
              const SizedBox(height: 10),
              labeledField(controller: _guardianPhoneCtrl, hint: _isBn ? 'তার ফোন নম্বর' : 'Their phone number', keyboardType: TextInputType.phone),
            ]),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'আপনি কী কী রান্না ভালো পারেন' : 'Dishes you cook well',
            child: TextField(
              controller: _specialtyCtrl,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(hintText: _isBn ? 'যেমন: বাঙালি ঘরোয়া রান্না, বিরিয়ানি, চাইনিজ' : 'e.g. Bengali home-style, Biryani, Chinese'),
            ),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'আপনার বাসার ঠিকানা' : 'Your home address',
            child: TextField(
              controller: _addressCtrl,
              maxLines: 2,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(hintText: _isBn ? 'বাসার পুরো ঠিকানা লিখুন' : 'Enter your full home address'),
            ),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'প্ল্যাটফর্মের নির্ধারিত মূল্যে রান্না' : "Platform's fixed pricing",
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _isBn
                    ? 'প্ল্যাটফর্মের নির্ধারিত মূল্যে (ফিক্সড প্রাইস) প্রতিটি পদ রান্না করতে রাজি আছেন?'
                    : 'Will you cook each dish at the platform\'s fixed price?',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _pricingChoiceChip(
                    label: _isBn ? 'হ্যাঁ' : 'Yes',
                    selected: _acceptsPlatformPricing,
                    onTap: () => setState(() => _acceptsPlatformPricing = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pricingChoiceChip(
                    label: _isBn ? 'না' : 'No',
                    selected: !_acceptsPlatformPricing,
                    onTap: () => setState(() => _acceptsPlatformPricing = false),
                  ),
                ),
              ]),
              if (!_acceptsPlatformPricing) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isBn
                            ? 'সতর্কতা: আপনি প্ল্যাটফর্মের নির্ধারিত মূল্যে রাজি না হলে অন-ডিমান্ড রিকোয়েস্টে আপনাকে ম্যাচ করা কঠিন হতে পারে, কারণ গ্রাহকরা সাধারণত প্ল্যাটফর্মের নির্ধারিত দামেই অর্ডার করেন। তবুও আপনি আবেদন জমা দিতে পারবেন।'
                            : "Warning: without agreeing to the platform's fixed pricing, it may be harder to get matched with on-demand requests, since customers usually order at the platform's set price. You can still submit your application.",
                        style: const TextStyle(color: Color(0xFF92400E), fontSize: 12, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'পদ ভিত্তিক দাম তালিকা' : 'Per-dish price list',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _isBn ? 'প্রতিটি পদের নাম, পরিমাণ/একক ও প্রত্যাশিত দাম যোগ করুন' : 'Add the name, quantity/unit, and your expected rate for each dish',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ..._menuItems.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F7F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(_isBn ? 'পদ #${e.key + 1}' : 'Dish #${e.key + 1}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700))),
                          if (_menuItems.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                              onPressed: () => setState(() { e.value.dispose(); _menuItems.removeAt(e.key); }),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ]),
                        const SizedBox(height: 8),
                        labeledField(controller: e.value.nameCtrl, hint: _isBn ? 'পদের নাম (যেমন: চিকেন বিরিয়ানি)' : 'Dish name (e.g. Chicken Biryani)'),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: labeledField(controller: e.value.quantityCtrl, hint: _isBn ? 'পরিমাণ/একক' : 'Quantity/unit')),
                          const SizedBox(width: 8),
                          Expanded(child: labeledField(controller: e.value.rateCtrl, hint: _isBn ? 'দাম ৳' : 'Rate ৳', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                        ]),
                        const SizedBox(height: 8),
                        labeledField(controller: e.value.prepTimeCtrl, hint: _isBn ? 'রান্নার সময় (মিনিট, ঐচ্ছিক)' : 'Prep time (minutes, optional)', keyboardType: TextInputType.number),
                      ]),
                    ),
                  )),
              TextButton.icon(
                onPressed: () => setState(() => _menuItems.add(_CookMenuItemRow())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(_isBn ? 'আরেকটি পদ যোগ করুন' : 'Add another dish'),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'নীতিমালা' : 'Policy',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _isBn
                    ? 'নির্ধারিত সময়ের মধ্যে কোনো পদ প্রস্তুত করতে না পারলে সময়-জরিমানা (টাইম পেনাল্টি) প্রযোজ্য হবে। কোনো অর্ডার সম্পূর্ণভাবে সম্পন্ন করতে ব্যর্থ হলে তার জন্য রেড কার্ড দেওয়া হবে, যা আপনার অ্যাকাউন্টের অবস্থাকে প্রভাবিত করবে।'
                    : "Policy: if a dish isn't finished within the agreed time, a time penalty applies. If a job isn't completed at all, it results in a red card, which affects your account standing.",
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: _policyAcknowledged,
                onChanged: (v) => setState(() => _policyAcknowledged = v ?? false),
                title: Text(
                  _isBn ? 'আমি উপরের নীতিমালা বুঝেছি এবং মেনে নিচ্ছি' : 'I understand and agree to the policy above',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ]),
          ),
          const SizedBox(height: 22),
          GlassButton(label: _isBn ? 'জমা দিন' : 'Submit', isLoading: _submitting, onPressed: _submitting ? null : _submit),
        ]),
      ),
    );
  }

  Widget _pricingChoiceChip({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? AppColors.blueGradient : null,
          color: selected ? null : const Color(0xFFF9F7F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.deepBlue : AppColors.glassBorder, width: selected ? 1.5 : 1),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}
