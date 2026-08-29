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
import 'chat_screen.dart';

class LaundryHubScreen extends StatefulWidget {
  const LaundryHubScreen({super.key});

  @override
  State<LaundryHubScreen> createState() => _LaundryHubScreenState();
}

class _LaundryHubScreenState extends State<LaundryHubScreen> {
  bool _isBn = true;
  bool _loading = true;
  List<Map<String, dynamic>> _myHubs = [];
  String? _selectedHubId;
  List<LaundryBookingModel> _queue = [];
  bool _queueLoading = false;
  String? _openingChatBookingId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final hubs = await LaundryService.instance.getMyStaffHubs();
      if (!mounted) return;
      setState(() {
        _myHubs = hubs;
        _loading = false;
        if (hubs.isNotEmpty) _selectedHubId = hubs.first['hubId'] as String?;
      });
      if (_selectedHubId != null) await _loadQueue();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadQueue() async {
    if (_selectedHubId == null) return;
    setState(() => _queueLoading = true);
    try {
      final q = await LaundryService.instance.getHubQueue(_selectedHubId!);
      if (mounted) setState(() { _queue = q; _queueLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _queueLoading = false);
    }
  }

  Future<void> _receive(LaundryBookingModel b) async {
    try {
      await LaundryService.instance.receiveBooking(b.id);
      await _loadQueue();
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _weighIn(LaundryBookingModel b) async {
    final ctrl = TextEditingController(text: b.estimatedLoad.toStringAsFixed(1));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'প্রকৃত পরিমাণ' : 'Actual load', style: const TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_isBn ? 'বাতিল' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: Text(_isBn ? 'নিশ্চিত' : 'Confirm')),
        ],
      ),
    );
    if (result == null) return;
    try {
      await LaundryService.instance.weighIn(b.id, result);
      await _loadQueue();
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  static const _kNextStage = {
    'picked_up': 'in_wash',
    'in_wash': 'ready',
    'ready': 'out_for_delivery',
    'out_for_delivery': 'delivered',
  };

  Future<void> _advanceStage(LaundryBookingModel b) async {
    final next = _kNextStage[b.status];
    if (next == null) return;
    try {
      await LaundryService.instance.updateStage(b.id, next);
      await _loadQueue();
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
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

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMid,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18), onPressed: () => Navigator.of(context).pop()),
        title: Text(_isBn ? 'লন্ড্রি হাব কিউ' : 'Laundry Hub Queue', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : _myHubs.isEmpty
              ? Center(child: Text(_isBn ? 'আপনি কোনো হাবের স্টাফ নন' : 'You are not staff at any hub', style: const TextStyle(color: AppColors.textMuted)))
              : Column(children: [
                  if (_myHubs.length > 1)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        value: _selectedHubId,
                        dropdownColor: AppColors.bgMid,
                        items: _myHubs.map((h) {
                          final id = h['hubId'] as String;
                          final hub = h['hub'] as Map<String, dynamic>?;
                          final name = hub?['name'] as String? ?? id;
                          return DropdownMenuItem(value: id, child: Text(name, style: const TextStyle(color: AppColors.textPrimary)));
                        }).toList(),
                        onChanged: (v) { setState(() => _selectedHubId = v); _loadQueue(); },
                      ),
                    ),
                  Expanded(
                    child: _queueLoading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                        : _queue.isEmpty
                            ? Center(child: Text(_isBn ? 'কিউতে কোনো বুকিং নেই' : 'No bookings in queue', style: const TextStyle(color: AppColors.textMuted)))
                            : RefreshIndicator(
                                onRefresh: _loadQueue,
                                color: AppColors.deepBlue,
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                                  itemCount: _queue.length,
                                  itemBuilder: (ctx, i) => _queueCard(_queue[i]),
                                ),
                              ),
                  ),
                ]),
    );
  }

  Widget _queueCard(LaundryBookingModel b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('#${b.bookingNo} · ${b.serviceKind.replaceAll('_', ' ')}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(b.status.replaceAll('_', ' '), style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(b.pickupAddress, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_isBn ? 'আনুমানিক: ${b.estimatedLoad}${b.actualLoad != null ? " · প্রকৃত: ${b.actualLoad}" : ""}' : 'Est: ${b.estimatedLoad}${b.actualLoad != null ? " · Actual: ${b.actualLoad}" : ""}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          if (b.status != 'booked') ...[
            if (b.customerPhoneSnapshot != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 18),
                const SizedBox(width: 8),
                Text(b.customerPhoneSnapshot!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
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
                Text(_isBn ? 'গ্রাহকের সাথে চ্যাট করুন' : 'Chat with customer', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (b.status == 'booked')
              Expanded(child: OutlinedButton(onPressed: () => _receive(b), style: _btnStyle(), child: Text(_isBn ? 'গ্রহণ করুন' : 'Receive', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)))),
            if (b.status == 'picked_up') ...[
              Expanded(child: OutlinedButton(onPressed: () => _weighIn(b), style: _btnStyle(), child: Text(_isBn ? 'ওজন লিখুন' : 'Weigh in', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)))),
              const SizedBox(width: 8),
            ],
            if (_kNextStage.containsKey(b.status)) ...[
              Expanded(child: OutlinedButton(onPressed: () => _advanceStage(b), style: _btnStyle(), child: Text(_isBn ? 'পরবর্তী ধাপ' : 'Next stage', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)))),
            ],
          ]),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  ButtonStyle _btnStyle() => OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.deepBlue), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));
}
