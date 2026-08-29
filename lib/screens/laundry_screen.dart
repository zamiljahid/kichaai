import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/laundry_model.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/laundry_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'chat_screen.dart';
import 'payment_waiting_screen.dart';

class LaundryScreen extends StatefulWidget {
  const LaundryScreen({super.key});

  @override
  State<LaundryScreen> createState() => _LaundryScreenState();
}

class _LaundryScreenState extends State<LaundryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isBn = true;

  List<LaundryRateCardModel> _catalog = [];
  List<LaundryHubModel> _hubs = [];
  bool _catalogLoading = true;

  LaundryHubModel? _selectedHub;
  String? _selectedServiceKind;
  String _pricingUnit = 'per_kg';
  final _loadCtrl = TextEditingController(text: '3');
  final _addressCtrl = TextEditingController();
  DateTime? _slotDate;
  TimeOfDay? _slotTime;
  String _paymentTiming = 'pay_at_booking';
  bool _isSubmitting = false;

  List<LaundryBookingModel> _myBookings = [];
  bool _bookingsLoading = true;
  String? _openingChatBookingId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loadCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await Future.wait([_loadCatalog(), _loadMyBookings()]);
  }

  Future<void> _loadCatalog() async {
    setState(() => _catalogLoading = true);
    try {
      final results = await Future.wait([
        LaundryService.instance.getCatalog(),
        LaundryService.instance.listHubs(),
      ]);
      if (!mounted) return;
      setState(() {
        _catalog = results[0] as List<LaundryRateCardModel>;
        _hubs = results[1] as List<LaundryHubModel>;
        _catalogLoading = false;
        if (_hubs.isNotEmpty) _selectedHub = _hubs.first;
        if (_catalog.isNotEmpty) {
          _selectedServiceKind = _catalog.first.serviceKind;
          _pricingUnit = _catalog.first.pricingUnit;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  Future<void> _loadMyBookings() async {
    setState(() => _bookingsLoading = true);
    try {
      final list = await LaundryService.instance.listMyBookings();
      if (mounted) setState(() { _myBookings = list; _bookingsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _bookingsLoading = false);
    }
  }

  LaundryRateCardModel? get _selectedRateCard {
    for (final c in _catalog) {
      if (c.serviceKind == _selectedServiceKind && c.pricingUnit == _pricingUnit) return c;
    }
    for (final c in _catalog) {
      if (c.serviceKind == _selectedServiceKind) return c;
    }
    return null;
  }

  double get _estimatedPrice {
    final rate = _selectedRateCard;
    final load = double.tryParse(_loadCtrl.text.trim()) ?? 0;
    if (rate == null) return 0;
    return rate.pricePerUnit * load;
  }

  Future<void> _pickSlot() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now.add(const Duration(hours: 2)), firstDate: now, lastDate: now.add(const Duration(days: 30)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() { _slotDate = date; _slotTime = time; });
  }

  Future<void> _submitBooking() async {
    if (_selectedHub == null || _selectedServiceKind == null) {
      _showError(_isBn ? 'হাব ও সার্ভিস বেছে নিন' : 'Choose a hub and service');
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      _showError(_isBn ? 'পিকআপ ঠিকানা লিখুন' : 'Enter a pickup address');
      return;
    }
    if (_slotDate == null || _slotTime == null) {
      _showError(_isBn ? 'পিকআপ সময় বেছে নিন' : 'Choose a pickup slot');
      return;
    }
    final load = double.tryParse(_loadCtrl.text.trim());
    if (load == null || load <= 0) {
      _showError(_isBn ? 'সঠিক পরিমাণ লিখুন' : 'Enter a valid load amount');
      return;
    }

    final slotStart = DateTime(_slotDate!.year, _slotDate!.month, _slotDate!.day, _slotTime!.hour, _slotTime!.minute);
    final slotEnd = slotStart.add(const Duration(hours: 2));

    setState(() => _isSubmitting = true);
    try {
      await LaundryService.instance.createBooking(
        hubId: _selectedHub!.id,
        serviceKind: _selectedServiceKind!,
        pricingUnit: _pricingUnit,
        estimatedLoad: load,
        pickupAddress: _addressCtrl.text.trim(),
        pickupSlotStart: slotStart,
        pickupSlotEnd: slotEnd,
        paymentTiming: _paymentTiming,
      );
      if (!mounted) return;
      _addressCtrl.clear();
      setState(() { _slotDate = null; _slotTime = null; _isSubmitting = false; });
      _showSuccess(_isBn ? 'বুকিং সফল হয়েছে' : 'Booking placed successfully');
      _tabController.animateTo(1);
      await _loadMyBookings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _payForBooking(LaundryBookingModel b) async {
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
    try {
      final transaction = await LaundryService.instance.initiatePayment(b.id);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        _showError(_isBn ? 'পেমেন্ট শুরু করা যায়নি' : 'Could not start payment');
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'লন্ড্রি পেমেন্ট' : 'Laundry Payment',
          titleEn: 'Laundry Payment',
          amount: b.displayAmount,
          checkStatus: () async {
            try {
              final updated = await LaundryService.instance.confirmPayment(b.id);
              return updated.paymentStatus == 'paid' ? PaymentCheckStatus.completed : PaymentCheckStatus.pending;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => _loadMyBookings(),
          applyCoupon: (code) async {
            final t = await LaundryService.instance.initiatePayment(b.id, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? b.displayAmount};
          },
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _cancelBooking(LaundryBookingModel b) async {
    try {
      await LaundryService.instance.cancelBooking(b.id);
      if (!mounted) return;
      _showSuccess(_isBn ? 'বুকিং বাতিল হয়েছে' : 'Booking cancelled');
      await _loadMyBookings();
    } catch (e) {
      if (!mounted) return;
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _openChat(String bookingId) async {
    setState(() => _openingChatBookingId = bookingId);
    try {
      final user = await AuthService.instance.getCurrentUser();
      final threads = await MessagingService.instance.listThreads(user.id);
      ThreadModel? thread;
      for (final t in threads) {
        if (t.serviceRequestId == bookingId) { thread = t; break; }
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
      if (mounted) setState(() => _openingChatBookingId = null);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String _fmtDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMid,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18), onPressed: () => Navigator.of(context).pop()),
        title: Text(_isBn ? 'লন্ড্রি' : 'Laundry', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.deepBlue,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.deepBlue,
          tabs: [Tab(text: _isBn ? 'নতুন বুকিং' : 'New Booking'), Tab(text: _isBn ? 'আমার বুকিং' : 'My Bookings')],
        ),
      ),
      body: TabBarView(controller: _tabController, children: [_buildNewBookingTab(), _buildMyBookingsTab()]),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600));

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

  Widget _buildNewBookingTab() {
    if (_catalogLoading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_hubs.isEmpty || _catalog.isEmpty) {
      return Center(child: Text(_isBn ? 'এই মুহূর্তে কোনো লন্ড্রি হাব উপলব্ধ নেই' : 'No laundry hub available right now', style: const TextStyle(color: AppColors.textMuted)));
    }
    final kinds = _catalog.map((c) => c.serviceKind).toSet().toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(_isBn ? 'হাব' : 'Hub'),
          const SizedBox(height: 8),
          DropdownButtonFormField<LaundryHubModel>(
            value: _selectedHub,
            decoration: _deco(),
            dropdownColor: AppColors.bgMid,
            items: _hubs.map((h) => DropdownMenuItem(value: h, child: Text(h.name, style: const TextStyle(color: AppColors.textPrimary)))).toList(),
            onChanged: (v) => setState(() => _selectedHub = v),
          ),
          const SizedBox(height: 20),
          _label(_isBn ? 'সার্ভিস' : 'Service'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: kinds.map((k) {
              final selected = k == _selectedServiceKind;
              return ChoiceChip(
                label: Text(k.replaceAll('_', ' ')),
                selected: selected,
                selectedColor: AppColors.deepBlue.withOpacity(0.15),
                labelStyle: TextStyle(color: selected ? AppColors.deepBlue : AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 12),
                onSelected: (_) => setState(() {
                  _selectedServiceKind = k;
                  final card = _catalog.firstWhere((c) => c.serviceKind == k, orElse: () => _catalog.first);
                  _pricingUnit = card.pricingUnit;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _label(_isBn ? 'পরিমাণ (${_selectedRateCard?.pricingUnit == 'per_item' ? "আইটেম" : "কেজি"})' : 'Amount (${_selectedRateCard?.pricingUnit == 'per_item' ? 'items' : 'kg'})'),
          const SizedBox(height: 8),
          TextField(controller: _loadCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), style: const TextStyle(color: AppColors.textPrimary), decoration: _deco()),
          if (_selectedRateCard != null) ...[
            const SizedBox(height: 8),
            Text(_isBn ? 'আনুমানিক মূল্য: ৳${_estimatedPrice.toStringAsFixed(0)}' : 'Estimated: ৳${_estimatedPrice.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 20),
          _label(_isBn ? 'পিকআপ ঠিকানা' : 'Pickup address'),
          const SizedBox(height: 8),
          TextField(controller: _addressCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _deco(hint: _isBn ? 'পূর্ণ ঠিকানা লিখুন' : 'Enter full address')),
          const SizedBox(height: 20),
          _label(_isBn ? 'পিকআপ সময়' : 'Pickup slot'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickSlot,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
              child: Row(children: [
                const Icon(Icons.schedule_outlined, color: AppColors.textMuted, size: 16),
                const SizedBox(width: 10),
                Text(_slotDate == null ? (_isBn ? 'সময় বেছে নিন' : 'Choose a slot') : _fmtDate(DateTime(_slotDate!.year, _slotDate!.month, _slotDate!.day, _slotTime!.hour, _slotTime!.minute)),
                    style: TextStyle(color: _slotDate == null ? AppColors.textMuted : AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          _label(_isBn ? 'পেমেন্ট' : 'Payment'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: RadioListTile<String>(
              value: 'pay_at_booking', groupValue: _paymentTiming, onChanged: (v) => setState(() => _paymentTiming = v!),
              title: Text(_isBn ? 'বুকিং করার সময়' : 'At booking', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
              activeColor: AppColors.deepBlue, contentPadding: EdgeInsets.zero, dense: true,
            )),
            Expanded(child: RadioListTile<String>(
              value: 'pay_on_delivery', groupValue: _paymentTiming, onChanged: (v) => setState(() => _paymentTiming = v!),
              title: Text(_isBn ? 'ডেলিভারিতে' : 'On delivery', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
              activeColor: AppColors.deepBlue, contentPadding: EdgeInsets.zero, dense: true,
            )),
          ]),
          const SizedBox(height: 24),
          GlassButton(label: _isSubmitting ? (_isBn ? 'পাঠানো হচ্ছে...' : 'Submitting...') : (_isBn ? 'বুকিং নিশ্চিত করুন' : 'Confirm Booking'), onPressed: _isSubmitting ? null : _submitBooking),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildMyBookingsTab() {
    if (_bookingsLoading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_myBookings.isEmpty) {
      return Center(child: Text(_isBn ? 'কোনো বুকিং নেই' : 'No bookings yet', style: const TextStyle(color: AppColors.textMuted)));
    }
    return RefreshIndicator(
      onRefresh: _loadMyBookings,
      color: AppColors.deepBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _myBookings.length,
        itemBuilder: (ctx, i) => _bookingCard(_myBookings[i]),
      ),
    );
  }

  Widget _bookingCard(LaundryBookingModel b) {
    final canPay = b.paymentStatus != 'paid' && b.status != 'cancelled';
    final canCancel = b.status == 'booked';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(b.serviceKind.replaceAll('_', ' '), style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(b.status.replaceAll('_', ' '), style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(b.pickupAddress, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_fmtDate(b.pickupSlotStart), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(_isBn ? 'মূল্য: ৳${b.displayAmount.toStringAsFixed(0)} (${b.paymentStatus})' : 'Amount: ৳${b.displayAmount.toStringAsFixed(0)} (${b.paymentStatus})', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          if (b.status != 'booked') ...[
            if (b.assignedStaffPhoneSnapshot != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 18),
                const SizedBox(width: 8),
                Text(b.assignedStaffPhoneSnapshot!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              ]),
            ],
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _openingChatBookingId == b.id ? null : () => _openChat(b.id),
              child: Row(children: [
                _openingChatBookingId == b.id
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                    : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.deepBlue, size: 16),
                const SizedBox(width: 8),
                Text(_isBn ? 'স্টাফের সাথে চ্যাট করুন' : 'Chat with staff', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          if (canPay || canCancel) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (canPay) Expanded(child: GlassButton(label: _isBn ? 'পেমেন্ট করুন' : 'Pay', onPressed: () => _payForBooking(b))),
              if (canPay && canCancel) const SizedBox(width: 10),
              if (canCancel) Expanded(child: OutlinedButton(
                onPressed: () => _cancelBooking(b),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFEF4444)), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
              )),
            ]),
          ],
        ],
      ),
    );
  }
}
