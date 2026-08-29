import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/cook_model.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/cook_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'chat_screen.dart';
import 'payment_waiting_screen.dart';

class CookScreen extends StatefulWidget {
  const CookScreen({super.key});

  @override
  State<CookScreen> createState() => _CookScreenState();
}

class _CookScreenState extends State<CookScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isBn = true;

  final _dishCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  DateTime? _windowDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isSubmitting = false;

  List<CookRequestModel> _myRequests = [];
  bool _requestsLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMyRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dishCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyRequests() async {
    setState(() => _requestsLoading = true);
    try {
      final list = await CookService.instance.listMyRequests();
      if (mounted) setState(() { _myRequests = list; _requestsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _requestsLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 30)));
    if (picked != null) setState(() => _windowDate = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_dishCtrl.text.trim().isEmpty || _qtyCtrl.text.trim().isEmpty || _areaCtrl.text.trim().isEmpty) {
      _showError(_isBn ? 'সব প্রয়োজনীয় তথ্য পূরণ করুন' : 'Fill in all required fields');
      return;
    }
    if (_windowDate == null || _startTime == null || _endTime == null) {
      _showError(_isBn ? 'পিকআপ সময় বেছে নিন' : 'Choose a pickup window');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await CookService.instance.createRequest(
        dishName: _dishCtrl.text.trim(),
        quantity: _qtyCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        pickupArea: _areaCtrl.text.trim(),
        windowDate: _windowDate!,
        windowStart: _fmtTime(_startTime!),
        windowEnd: _fmtTime(_endTime!),
      );
      if (!mounted) return;
      _dishCtrl.clear(); _qtyCtrl.clear(); _notesCtrl.clear(); _areaCtrl.clear();
      setState(() { _windowDate = null; _startTime = null; _endTime = null; _isSubmitting = false; });
      _showSuccess(_isBn ? 'রিকোয়েস্ট পোস্ট হয়েছে' : 'Request posted');
      _tabController.animateTo(1);
      await _loadMyRequests();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _openDetail(CookRequestModel req) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _RequestDetailSheet(request: req, isBn: _isBn, onChanged: _loadMyRequests),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16)));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16)));
  }

  InputDecoration _deco({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        filled: true,
        fillColor: AppColors.glassWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.glassBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.glassBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.deepBlue, width: 1.5)),
      );

  Widget _label(String t) => Text(t, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600));

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMid,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18), onPressed: () => Navigator.of(context).pop()),
        title: Text(_isBn ? 'রান্না অন-ডিমান্ড' : 'Cook On-Demand', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.deepBlue,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.deepBlue,
          tabs: [Tab(text: _isBn ? 'নতুন রিকোয়েস্ট' : 'New Request'), Tab(text: _isBn ? 'আমার রিকোয়েস্ট' : 'My Requests')],
        ),
      ),
      body: TabBarView(controller: _tabController, children: [_buildNewTab(), _buildMyTab()]),
    );
  }

  Widget _buildNewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(_isBn ? 'পদের নাম' : 'Dish name'),
          const SizedBox(height: 8),
          TextField(controller: _dishCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _deco(hint: _isBn ? 'যেমন: মুরগির বিরিয়ানি' : 'e.g. Chicken Biryani')),
          const SizedBox(height: 20),
          _label(_isBn ? 'পরিমাণ' : 'Quantity'),
          const SizedBox(height: 8),
          TextField(controller: _qtyCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _deco(hint: _isBn ? 'যেমন: ২ প্লেট' : 'e.g. 2 plates')),
          const SizedBox(height: 20),
          _label(_isBn ? 'নোট (ঐচ্ছিক)' : 'Notes (optional)'),
          const SizedBox(height: 8),
          TextField(controller: _notesCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _deco()),
          const SizedBox(height: 20),
          _label(_isBn ? 'পিকআপ এলাকা' : 'Pickup area'),
          const SizedBox(height: 8),
          TextField(controller: _areaCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _deco(hint: _isBn ? 'যেমন: ধানমন্ডি' : 'e.g. Dhanmondi')),
          const SizedBox(height: 20),
          _label(_isBn ? 'পিকআপ তারিখ' : 'Pickup date'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, color: AppColors.textMuted, size: 16),
                const SizedBox(width: 10),
                Text(_windowDate == null ? (_isBn ? 'তারিখ বেছে নিন' : 'Choose a date') : '${_windowDate!.day}/${_windowDate!.month}/${_windowDate!.year}', style: TextStyle(color: _windowDate == null ? AppColors.textMuted : AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          _label(_isBn ? 'সময়সীমা' : 'Time window'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _pickTime(true), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.glassBorder), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text(_startTime == null ? (_isBn ? 'শুরু' : 'Start') : _fmtTime(_startTime!), style: const TextStyle(color: AppColors.textPrimary)))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () => _pickTime(false), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.glassBorder), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text(_endTime == null ? (_isBn ? 'শেষ' : 'End') : _fmtTime(_endTime!), style: const TextStyle(color: AppColors.textPrimary)))),
          ]),
          const SizedBox(height: 24),
          GlassButton(label: _isSubmitting ? (_isBn ? 'পাঠানো হচ্ছে...' : 'Posting...') : (_isBn ? 'রিকোয়েস্ট পোস্ট করুন' : 'Post Request'), onPressed: _isSubmitting ? null : _submit),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildMyTab() {
    if (_requestsLoading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_myRequests.isEmpty) return Center(child: Text(_isBn ? 'কোনো রিকোয়েস্ট নেই' : 'No requests yet', style: const TextStyle(color: AppColors.textMuted)));
    return RefreshIndicator(
      onRefresh: _loadMyRequests,
      color: AppColors.deepBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _myRequests.length,
        itemBuilder: (ctx, i) {
          final r = _myRequests[i];
          return GestureDetector(
            onTap: () => _openDetail(r),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(r.dishName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Text(r.status.replaceAll('_', ' '), style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 6),
                  Text('${r.quantity} · ${r.pickupArea}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${r.windowStart} - ${r.windowEnd}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ).animate(delay: Duration(milliseconds: 40 * i)).fadeIn(duration: 250.ms);
        },
      ),
    );
  }
}

class _RequestDetailSheet extends StatefulWidget {
  final CookRequestModel request;
  final bool isBn;
  final VoidCallback onChanged;
  const _RequestDetailSheet({required this.request, required this.isBn, required this.onChanged});

  @override
  State<_RequestDetailSheet> createState() => _RequestDetailSheetState();
}

const _kActiveTrackedStatuses = {'confirmed', 'preparing', 'ready_for_pickup'};

class _RequestDetailSheetState extends State<_RequestDetailSheet> {
  List<CookConfirmationModel> _confirmations = [];
  bool _loading = true;
  bool _busy = false;
  bool _isOpeningChat = false;
  late CookRequestModel _liveRequest = widget.request;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    if (_kActiveTrackedStatuses.contains(widget.request.status)) {
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshLocation());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    try {
      final updated = await CookService.instance.getRequest(widget.request.id);
      if (mounted) setState(() => _liveRequest = updated);
    } catch (_) {
      // Best-effort — the map just stays on its last known position until the next tick.
    }
  }

  Future<void> _openChat() async {
    setState(() => _isOpeningChat = true);
    try {
      final user = await AuthService.instance.getCurrentUser();
      final threads = await MessagingService.instance.listThreads(user.id);
      ThreadModel? thread;
      for (final t in threads) {
        if (t.serviceRequestId == widget.request.id) { thread = t; break; }
      }
      if (!mounted) return;
      if (thread == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.isBn ? 'চ্যাট এখনো তৈরি হয়নি — একটু পরে আবার চেষ্টা করুন' : 'Chat not created yet — try again shortly', style: const TextStyle(color: Colors.white)),
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
          content: Text(widget.isBn ? 'চ্যাট খোলা যায়নি' : 'Could not open chat', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _load() async {
    if (widget.request.status != 'posted') {
      setState(() => _loading = false);
      return;
    }
    try {
      final list = await CookService.instance.listConfirmations(widget.request.id);
      if (mounted) setState(() { _confirmations = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Finalize IS "confirm" from the customer's side — payment is now collected right here,
  // not left until after pickup, so the provider isn't cooking on an unpaid order.
  Future<void> _finalize(CookConfirmationModel c) async {
    setState(() => _busy = true);
    try {
      await CookService.instance.finalizeRequest(widget.request.id, c.id);
      if (!mounted) return;
      widget.onChanged();
      await _pay(amountOverride: c.quotedAmount ?? widget.request.budgetAmount);
    } catch (e) {
      setState(() => _busy = false);
      _toast(ApiClient.mapError(e).localized(widget.isBn));
    }
  }

  Future<void> _cancelRequest() async {
    setState(() => _busy = true);
    try {
      await CookService.instance.cancelRequest(widget.request.id);
      if (!mounted) return;
      widget.onChanged();
      Navigator.pop(context);
    } catch (e) {
      setState(() => _busy = false);
      _toast(ApiClient.mapError(e).localized(widget.isBn));
    }
  }

  Future<void> _markPickedUp() async {
    setState(() => _busy = true);
    try {
      await CookService.instance.markPickedUp(widget.request.id);
      if (!mounted) return;
      widget.onChanged();
      Navigator.pop(context);
    } catch (e) {
      setState(() => _busy = false);
      _toast(ApiClient.mapError(e).localized(widget.isBn));
    }
  }

  Future<void> _pay({double? amountOverride}) async {
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: widget.isBn)) return;
    try {
      final transaction = await CookService.instance.initiatePayment(widget.request.id);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        setState(() => _busy = false);
        _toast(widget.isBn ? 'পেমেন্ট শুরু করা যায়নি' : 'Could not start payment');
        return;
      }
      Navigator.pop(context);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: widget.isBn ? 'রান্না পেমেন্ট' : 'Cook Payment',
          titleEn: 'Cook Payment',
          amount: amountOverride ?? widget.request.paymentAmount ?? widget.request.budgetAmount ?? 0,
          checkStatus: () async {
            try {
              final updated = await CookService.instance.confirmPayment(widget.request.id);
              return updated.paymentStatus == 'paid' ? PaymentCheckStatus.completed : PaymentCheckStatus.pending;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: widget.onChanged,
          applyCoupon: (code) async {
            final t = await CookService.instance.initiatePayment(widget.request.id, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? (amountOverride ?? widget.request.paymentAmount ?? widget.request.budgetAmount ?? 0)};
          },
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(ApiClient.mapError(e).localized(widget.isBn));
    }
  }

  Future<void> _rate() async {
    int rating = 5;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(widget.isBn ? 'রেটিং দিন' : 'Rate provider', style: const TextStyle(color: AppColors.textPrimary)),
        content: Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => IconButton(
          icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B)),
          onPressed: () => setD(() => rating = i + 1),
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.isBn ? 'বাতিল' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(widget.isBn ? 'জমা দিন' : 'Submit')),
        ],
      )),
    );
    if (confirmed != true) return;
    try {
      await CookService.instance.rateProvider(widget.request.id, rating);
      if (!mounted) return;
      widget.onChanged();
      Navigator.pop(context);
    } catch (e) {
      _toast(ApiClient.mapError(e).localized(widget.isBn));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _liveRequest;
    final isBn = widget.isBn;
    CookConfirmationModel? finalConfirmation;
    for (final c in r.confirmations) {
      if (c.id == r.confirmedResponseId) { finalConfirmation = c; break; }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(r.dishName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${r.quantity} · ${r.pickupArea}', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            if (_kActiveTrackedStatuses.contains(r.status) && r.providerLatitude != null && r.providerLongitude != null) ...[
              Text(isBn ? 'রাঁধুনির অবস্থান' : "Provider's location", style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 180,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: LatLng(r.providerLatitude!, r.providerLongitude!), zoom: 14),
                    markers: {
                      Marker(markerId: const MarkerId('provider'), position: LatLng(r.providerLatitude!, r.providerLongitude!)),
                    },
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                    liteModeEnabled: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (r.status != 'posted') ...[
              Text(isBn ? 'রাঁধুনির তথ্য' : 'Provider info', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.person_rounded, color: AppColors.deepBlue, size: 18),
                const SizedBox(width: 8),
                Text(finalConfirmation?.providerNameSnapshot ?? (isBn ? 'রাঁধুনি' : 'Provider'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
              if (finalConfirmation?.providerPhoneSnapshot != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 18),
                  const SizedBox(width: 8),
                  Text(finalConfirmation!.providerPhoneSnapshot!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                ]),
              ] else ...[
                const SizedBox(height: 8),
                Text(isBn ? 'নম্বরটি এখনো প্রকাশ করা হয়নি — ততক্ষণ চ্যাটে কথা বলুন' : "The number isn't revealed yet — chat until then", style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4)),
              ],
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _isOpeningChat ? null : _openChat,
                child: Row(children: [
                  _isOpeningChat
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                      : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.deepBlue, size: 16),
                  const SizedBox(width: 8),
                  Text(isBn ? 'রাঁধুনির সাথে চ্যাট করুন' : 'Chat with provider', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            if (r.status == 'posted') ...[
              Text(isBn ? 'রাঁধুনিদের সাড়া' : 'Provider responses', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (_loading) const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
              else if (_confirmations.where((c) => c.status == 'confirmed').isEmpty)
                Text(isBn ? 'এখনো কোনো রাঁধুনি সাড়া দেননি' : 'No providers have responded yet', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))
              else
                ..._confirmations.where((c) => c.status == 'confirmed').map((c) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.providerNameSnapshot ?? (isBn ? 'রাঁধুনি' : 'Provider'), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                          if (c.quotedAmount != null) Text('৳${c.quotedAmount!.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                        ])),
                        TextButton(onPressed: _busy ? null : () => _finalize(c), child: Text(isBn ? 'নির্বাচন করুন' : 'Select')),
                      ]),
                    )),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _busy ? null : _cancelRequest, style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFEF4444))), child: Text(isBn ? 'রিকোয়েস্ট বাতিল করুন' : 'Cancel request', style: const TextStyle(color: Color(0xFFEF4444)))),
            ],
            if (r.status == 'ready_for_pickup')
              GlassButton(label: isBn ? 'পিকআপ সম্পন্ন হয়েছে' : 'Mark picked up', onPressed: _busy ? null : _markPickedUp),
            // Payment is normally collected right at confirm — this is only a resume path for
            // someone who backed out of that payment screen before it completed.
            if ((_kActiveTrackedStatuses.contains(r.status) || r.status == 'completed') && r.paymentStatus != 'paid' && r.paymentAmount != null)
              GlassButton(label: isBn ? 'পেমেন্ট সম্পন্ন করুন' : 'Complete payment', onPressed: () => _pay()),
            if (r.status == 'completed' && r.paymentStatus == 'paid')
              GlassButton(label: isBn ? 'রাঁধুনিকে রেটিং দিন' : 'Rate provider', onPressed: _rate),
          ],
        ),
      ),
    );
  }
}
