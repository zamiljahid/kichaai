import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/commute_model.dart';
import '../models/dispatch_model.dart' show kRideVehicleTypes, kRideVehicleLabelsBn, kRideVehicleLabelsEn;
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/commute_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'chat_screen.dart';
import 'payment_waiting_screen.dart';

// Shared by _MyTripsTab and _OneOffTripSheet — opens (or reports "not created yet") the
// messaging thread tied to a pairing/trip via serviceRequestId, exactly like the dispatch
// dispatchJobId pattern in active_job_screen.dart but matched on serviceRequestId instead
// (cook/laundry/commute threads are matchmaking-style threads, not dispatch threads).
Future<void> _openCommuteChat(BuildContext context, String serviceRequestId, bool isBn) async {
  try {
    final user = await AuthService.instance.getCurrentUser();
    final threads = await MessagingService.instance.listThreads(user.id);
    ThreadModel? thread;
    for (final t in threads) {
      if (t.serviceRequestId == serviceRequestId) { thread = t; break; }
    }
    if (!context.mounted) return;
    if (thread == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isBn ? 'চ্যাট এখনো তৈরি হয়নি — একটু পরে আবার চেষ্টা করুন' : 'Chat not created yet — try again shortly', style: const TextStyle(color: Colors.white)),
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isBn ? 'চ্যাট খোলা যায়নি' : 'Could not open chat', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

const _kDayCodes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const _kDayLabelsBn = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি', 'রবি'];
const _kDayLabelsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class CommuteScreen extends StatefulWidget {
  /// Which tab to open on. This screen is shared by both sides of a carpool — a passenger
  /// arriving from the customer tab wants "Find a ride", a driver arriving from the provider
  /// dashboard wants "Offer a ride", and landing a driver on the passenger tab made the
  /// provider entry point look like the wrong screen entirely.
  final int initialTab;
  const CommuteScreen({super.key, this.initialTab = 0});

  @override
  State<CommuteScreen> createState() => _CommuteScreenState();
}

class _CommuteScreenState extends State<CommuteScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        title: Text(_isBn ? 'কমিউট পার্টনার' : 'Commute Partner', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.deepBlue,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.deepBlue,
          isScrollable: true,
          tabs: [Tab(text: _isBn ? 'খুঁজুন' : 'Find a ride'), Tab(text: _isBn ? 'অফার দিন' : 'Offer a ride'), Tab(text: _isBn ? 'আমার ট্রিপ' : 'My trips'), Tab(text: _isBn ? 'প্রোফাইল' : 'Profile')],
        ),
      ),
      body: Column(
        children: [
          // The split between this screen and the dashboard is not obvious: recurring carpool
          // lives here, but "I need a ride now" never appears in these tabs — it is broadcast
          // to whoever is online, and lands on the provider dashboard as an offer.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.glassBlue,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.deepBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isBn
                        ? 'এখানে নিয়মিত/শিডিউল করা রাইড। এখনই দরকার — এমন রাইড পেতে ড্যাশবোর্ড থেকে অনলাইন হোন।'
                        : 'This is for recurring/scheduled rides. For on-demand rides, go online from your dashboard.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          // The controller has to be passed here too. Without it TabBarView falls back to
          // DefaultTabController, which this screen never installs (it owns _tabController
          // itself), so didChangeDependencies null-asserted and every one of the four tabs
          // rendered as an empty grey area — the whole screen was unusable.
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_FindTab(), _OfferTab(), _MyTripsTab(), _ProfileTab()],
            ),
          ),
        ],
      ),
    );
  }
}

void _showSnack(BuildContext context, String message, {bool success = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, style: const TextStyle(color: Colors.white)),
    backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(16),
  ));
}

InputDecoration _commuteDeco({String? hint}) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      filled: true,
      fillColor: AppColors.glassWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.glassBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.glassBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.deepBlue, width: 1.5)),
    );

// ─────────────────────────────────────────────────────────────────────────
// TAB 1 — Find a ride (passenger-acting: search recurring offers + one-off posts)
// ─────────────────────────────────────────────────────────────────────────

class _FindTab extends StatefulWidget {
  const _FindTab();
  @override
  State<_FindTab> createState() => _FindTabState();
}

class _FindTabState extends State<_FindTab> {
  final _areaCtrl = TextEditingController();
  List<CommuteOfferModel> _offers = [];
  List<OneOffCommutePostModel> _oneOffs = [];
  bool _loading = true;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    final area = _areaCtrl.text.trim().isEmpty ? null : _areaCtrl.text.trim();
    try {
      final results = await Future.wait([
        CommuteService.instance.searchOffers(originArea: area),
        CommuteService.instance.searchOneOffPosts(originArea: area, postedByRole: 'driver'),
      ]);
      if (mounted) setState(() {
        _offers = results[0] as List<CommuteOfferModel>;
        _oneOffs = results[1] as List<OneOffCommutePostModel>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestJoin(CommuteOfferModel o) async {
    try {
      await CommuteService.instance.requestToJoin(o.id);
      if (mounted) _showSnack(context, _isBn ? 'অনুরোধ পাঠানো হয়েছে' : 'Request sent', success: true);
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _matchOneOff(OneOffCommutePostModel p) async {
    try {
      final trip = await CommuteService.instance.matchOneOffPost(p.id);
      if (!mounted) return;
      _showSnack(context, _isBn ? 'ম্যাচ হয়েছে' : 'Matched', success: true);
      await _search();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.bgDark,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => _OneOffTripSheet(trip: trip, post: p),
      );
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _postNeedARide() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const _CreateOneOffSheet(role: 'passenger'),
    );
    if (result == true && mounted) _showSnack(context, _isBn ? 'পোস্ট করা হয়েছে' : 'Posted', success: true);
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: OutlinedButton(
          onPressed: _postNeedARide,
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.deepBlue), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: Text(_isBn ? '+ আমার একটি রাইড দরকার' : '+ I need a ride', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _areaCtrl,
          onSubmitted: (_) => _search(),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: _commuteDeco(hint: _isBn ? 'যাত্রা শুরুর এলাকা' : 'Origin area').copyWith(suffixIcon: IconButton(icon: const Icon(Icons.search, color: AppColors.textMuted), onPressed: _search)),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
            : (_offers.isEmpty && _oneOffs.isEmpty)
                ? Center(child: Text(_isBn ? 'কোনো রাইড পাওয়া যায়নি' : 'No rides found', style: const TextStyle(color: AppColors.textMuted)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    children: [
                      if (_offers.isNotEmpty) ...[
                        Text(_isBn ? 'নিয়মিত অফার' : 'Recurring offers', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ..._offers.map((o) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${o.originArea} → ${o.destinationArea ?? ''}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text('${o.windowStart} - ${o.windowEnd} · ${o.vehicleType} · ${o.seatsAvailable} ${_isBn ? "সিট" : "seats"}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                Text('৳${o.costShareAmount.toStringAsFixed(0)}/${_isBn ? "মাস" : "mo"}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                GlassButton(label: _isBn ? 'যোগ দিতে চান' : 'Request to join', onPressed: () => _requestJoin(o), width: double.infinity),
                              ]),
                            )),
                        const SizedBox(height: 16),
                      ],
                      if (_oneOffs.isNotEmpty) ...[
                        Text(_isBn ? 'একবারের পোস্ট' : 'One-off rides', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ..._oneOffs.map((p) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${p.originArea} → ${p.destinationArea ?? ''}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text('${p.tripDateTime.day}/${p.tripDateTime.month} ${p.tripDateTime.hour.toString().padLeft(2, '0')}:${p.tripDateTime.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                if (p.costShareAmount != null) Text('৳${p.costShareAmount!.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                GlassButton(label: _isBn ? 'যোগাযোগ করুন' : 'Match this ride', onPressed: () => _matchOneOff(p), width: double.infinity),
                              ]),
                            )),
                      ],
                    ],
                  ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TAB 2 — Offer a ride (driver-acting: create recurring offer / one-off post,
// manage incoming join requests)
// ─────────────────────────────────────────────────────────────────────────

class _OfferTab extends StatefulWidget {
  const _OfferTab();
  @override
  State<_OfferTab> createState() => _OfferTabState();
}

class _OfferTabState extends State<_OfferTab> {
  bool _isBn = true;
  List<CommuteOfferModel> _myOffers = [];
  List<OneOffCommutePostModel> _passengerPosts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        CommuteService.instance.listMyOffers(),
        CommuteService.instance.searchOneOffPosts(postedByRole: 'passenger'),
      ]);
      if (mounted) setState(() {
        _myOffers = results[0] as List<CommuteOfferModel>;
        _passengerPosts = results[1] as List<OneOffCommutePostModel>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _matchPassenger(OneOffCommutePostModel p) async {
    try {
      final trip = await CommuteService.instance.matchOneOffPost(p.id);
      if (!mounted) return;
      _showSnack(context, _isBn ? 'ম্যাচ হয়েছে' : 'Matched', success: true);
      await _load();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.bgDark,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => _OneOffTripSheet(trip: trip, post: p),
      );
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _createOffer() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const _CreateOfferSheet(),
    );
    if (result == true) await _load();
  }

  Future<void> _createOneOff() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const _CreateOneOffSheet(role: 'driver'),
    );
    if (result == true && mounted) _showSnack(context, _isBn ? 'পোস্ট করা হয়েছে' : 'Posted', success: true);
  }

  Future<void> _viewRequests(CommuteOfferModel o) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _OfferRequestsSheet(offer: o),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: GlassButton(label: _isBn ? '+ নিয়মিত অফার' : '+ Recurring offer', onPressed: _createOffer)),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: _createOneOff, style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.glassBorder), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text(_isBn ? '+ একবারের পোস্ট' : '+ One-off post', style: const TextStyle(color: AppColors.textPrimary)))),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.deepBlue,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  children: [
                    Text(_isBn ? 'আমার নিয়মিত অফার' : 'My recurring offers', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_myOffers.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_isBn ? 'কোনো অফার নেই' : 'No offers yet', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)))
                    else
                      ..._myOffers.map((o) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${o.originArea} → ${o.destinationArea ?? ''}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('${o.windowStart} - ${o.windowEnd} · ${o.seatsAvailable} ${_isBn ? "সিট বাকি" : "seats left"}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              const SizedBox(height: 8),
                              OutlinedButton(onPressed: () => _viewRequests(o), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.deepBlue)), child: Text(_isBn ? 'অনুরোধ দেখুন' : 'View requests', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700))),
                            ]),
                          )),
                    const SizedBox(height: 20),
                    Text(_isBn ? 'যাত্রী খুঁজছেন রাইড' : 'Passengers looking for a ride', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_passengerPosts.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_isBn ? 'কোনো পোস্ট নেই' : 'No posts yet', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)))
                    else
                      ..._passengerPosts.map((p) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${p.originArea} → ${p.destinationArea ?? ''}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('${p.tripDateTime.day}/${p.tripDateTime.month} ${p.tripDateTime.hour.toString().padLeft(2, '0')}:${p.tripDateTime.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              const SizedBox(height: 8),
                              GlassButton(label: _isBn ? 'যাত্রীকে নিন' : 'Offer this ride', onPressed: () => _matchPassenger(p), width: double.infinity),
                            ]),
                          )),
                  ],
                ),
              ),
      ),
    ]);
  }
}

class _CreateOfferSheet extends StatefulWidget {
  const _CreateOfferSheet();
  @override
  State<_CreateOfferSheet> createState() => _CreateOfferSheetState();
}

class _CreateOfferSheetState extends State<_CreateOfferSheet> {
  bool _isBn = true;
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController(text: 'car');
  final _seatsCtrl = TextEditingController(text: '2');
  final _costCtrl = TextEditingController();
  final Set<String> _days = {};
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_originCtrl.text.trim().isEmpty || _days.isEmpty || _start == null || _end == null || _seatsCtrl.text.trim().isEmpty || _costCtrl.text.trim().isEmpty) {
      _showSnack(context, _isBn ? 'সব তথ্য পূরণ করুন' : 'Fill in all fields');
      return;
    }
    setState(() => _submitting = true);
    try {
      await CommuteService.instance.createOffer(
        originArea: _originCtrl.text.trim(),
        destinationArea: _destCtrl.text.trim().isEmpty ? null : _destCtrl.text.trim(),
        daysOfWeek: _days.toList(),
        windowStart: '${_start!.hour.toString().padLeft(2, '0')}:${_start!.minute.toString().padLeft(2, '0')}',
        windowEnd: '${_end!.hour.toString().padLeft(2, '0')}:${_end!.minute.toString().padLeft(2, '0')}',
        vehicleType: _vehicleCtrl.text.trim(),
        seatsAvailable: int.tryParse(_seatsCtrl.text.trim()) ?? 1,
        costShareAmount: double.tryParse(_costCtrl.text.trim()) ?? 0,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => _submitting = false); _showSnack(context, ApiClient.mapError(e).localized(_isBn)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isBn ? 'নিয়মিত অফার তৈরি করুন' : 'Create recurring offer', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: _originCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'যাত্রা শুরুর এলাকা' : 'Origin area')),
          const SizedBox(height: 12),
          TextField(controller: _destCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'গন্তব্য এলাকা' : 'Destination area')),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: List.generate(7, (i) {
            final code = _kDayCodes[i];
            final selected = _days.contains(code);
            return ChoiceChip(
              label: Text(_isBn ? _kDayLabelsBn[i] : _kDayLabelsEn[i]),
              selected: selected,
              selectedColor: AppColors.deepBlue.withOpacity(0.15),
              labelStyle: TextStyle(color: selected ? AppColors.deepBlue : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
              onSelected: (v) => setState(() => v ? _days.add(code) : _days.remove(code)),
            );
          })),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async { final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0)); if (t != null) setState(() => _start = t); }, child: Text(_start == null ? (_isBn ? 'শুরুর সময়' : 'Start time') : '${_start!.hour.toString().padLeft(2, '0')}:${_start!.minute.toString().padLeft(2, '0')}'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () async { final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0)); if (t != null) setState(() => _end = t); }, child: Text(_end == null ? (_isBn ? 'শেষ সময়' : 'End time') : '${_end!.hour.toString().padLeft(2, '0')}:${_end!.minute.toString().padLeft(2, '0')}'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _vehicleCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'গাড়ির ধরন' : 'Vehicle type'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _seatsCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'সিট' : 'Seats'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'মাসিক খরচ ভাগ (৳)' : 'Monthly cost share (৳)')),
          const SizedBox(height: 20),
          GlassButton(label: _submitting ? (_isBn ? 'সংরক্ষণ হচ্ছে...' : 'Saving...') : (_isBn ? 'অফার তৈরি করুন' : 'Create offer'), onPressed: _submitting ? null : _submit),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _CreateOneOffSheet extends StatefulWidget {
  final String role;
  const _CreateOneOffSheet({required this.role});
  @override
  State<_CreateOneOffSheet> createState() => _CreateOneOffSheetState();
}

class _CreateOneOffSheetState extends State<_CreateOneOffSheet> {
  bool _isBn = true;
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _seatsCtrl = TextEditingController(text: '1');
  DateTime? _date;
  TimeOfDay? _time;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_originCtrl.text.trim().isEmpty || _date == null || _time == null) {
      _showSnack(context, _isBn ? 'সব তথ্য পূরণ করুন' : 'Fill in all fields');
      return;
    }
    setState(() => _submitting = true);
    final dt = DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
    try {
      await CommuteService.instance.createOneOffPost(
        postedByRole: widget.role,
        originArea: _originCtrl.text.trim(),
        destinationArea: _destCtrl.text.trim().isEmpty ? null : _destCtrl.text.trim(),
        tripDateTime: dt,
        seatsOrNeed: int.tryParse(_seatsCtrl.text.trim()) ?? 1,
        costShareAmount: double.tryParse(_costCtrl.text.trim()),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => _submitting = false); _showSnack(context, ApiClient.mapError(e).localized(_isBn)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isBn ? 'একবারের পোস্ট' : 'One-off post', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: _originCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'যাত্রা শুরুর এলাকা' : 'Origin area')),
          const SizedBox(height: 12),
          TextField(controller: _destCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'গন্তব্য এলাকা' : 'Destination area')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async { final now = DateTime.now(); final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 30))); if (d != null) setState(() => _date = d); }, child: Text(_date == null ? (_isBn ? 'তারিখ' : 'Date') : '${_date!.day}/${_date!.month}'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () async { final t = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (t != null) setState(() => _time = t); }, child: Text(_time == null ? (_isBn ? 'সময়' : 'Time') : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _seatsCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'সিট' : 'Seats'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'খরচ ভাগ (৳)' : 'Cost share (৳)'))),
          ]),
          const SizedBox(height: 20),
          GlassButton(label: _submitting ? (_isBn ? 'পোস্ট হচ্ছে...' : 'Posting...') : (_isBn ? 'পোস্ট করুন' : 'Post'), onPressed: _submitting ? null : _submit),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _OfferRequestsSheet extends StatefulWidget {
  final CommuteOfferModel offer;
  const _OfferRequestsSheet({required this.offer});
  @override
  State<_OfferRequestsSheet> createState() => _OfferRequestsSheetState();
}

class _OfferRequestsSheetState extends State<_OfferRequestsSheet> {
  bool _isBn = true;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CommuteService.instance.listOfferRequests(widget.offer.id);
      if (mounted) setState(() { _requests = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(String requestId, bool accept) async {
    try {
      if (accept) {
        await CommuteService.instance.acceptRequest(requestId);
      } else {
        await CommuteService.instance.declineRequest(requestId);
      }
      await _load();
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isBn ? 'যোগদানের অনুরোধ' : 'Join requests', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (_loading) const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
        else if (_requests.isEmpty) Text(_isBn ? 'কোনো অনুরোধ নেই' : 'No requests yet', style: const TextStyle(color: AppColors.textMuted))
        else ..._requests.map((r) {
          final status = r['status'] as String? ?? 'requested';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['passengerNameSnapshot'] as String? ?? (_isBn ? 'যাত্রী' : 'Passenger'), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                Text(status, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ])),
              if (status == 'requested') ...[
                IconButton(icon: const Icon(Icons.check_circle, color: Color(0xFF10B981)), onPressed: () => _respond(r['id'] as String, true)),
                IconButton(icon: const Icon(Icons.cancel, color: Color(0xFFEF4444)), onPressed: () => _respond(r['id'] as String, false)),
              ],
            ]),
          );
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TAB 3 — My trips (shared pairings + one-off, both roles)
// ─────────────────────────────────────────────────────────────────────────

class _MyTripsTab extends StatefulWidget {
  const _MyTripsTab();
  @override
  State<_MyTripsTab> createState() => _MyTripsTabState();
}

class _MyTripsTabState extends State<_MyTripsTab> {
  bool _isBn = true;
  List<Map<String, dynamic>> _pairings = [];
  final Set<String> _loggingTripIds = {};
  bool _loading = true;
  String? _myUserId;
  final Set<String> _openingChatIds = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _myUserId = await ApiClient.getUserId();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await CommuteService.instance.listMyPairings();
      if (mounted) setState(() { _pairings = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay(String pairingId, double amount) async {
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
    try {
      final transaction = await CommuteService.instance.initiatePairingPayment(pairingId);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted || gatewayPageUrl == null) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'কমিউট পেমেন্ট' : 'Commute Payment',
          titleEn: 'Commute Payment',
          amount: amount,
          checkStatus: () async {
            try {
              await CommuteService.instance.confirmPairingPayment(pairingId);
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: _load,
        ),
      ));
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  /// Record today's ride against a pairing. This is the shared-cost ledger for a
  /// recurring commute — the endpoint existed but nothing in the app ever wrote to it,
  /// so a monthly settlement had no per-day record behind it.
  Future<void> _logTrip(String pairingId, String status) async {
    setState(() => _loggingTripIds.add(pairingId));
    try {
      await CommuteService.instance.logTrip(pairingId, DateTime.now(), status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          status == 'completed'
              ? (_isBn ? 'আজকের ট্রিপ লগ হয়েছে' : "Today's trip logged")
              : (_isBn ? 'আজ যাননি — লগ হয়েছে' : 'Marked as skipped today'),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ApiClient.mapError(e).localized(_isBn),
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _loggingTripIds.remove(pairingId));
    }
  }

  Future<void> _end(String pairingId) async {
    try {
      await CommuteService.instance.endPairing(pairingId);
      await _load();
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _openChat(String pairingId) async {
    setState(() => _openingChatIds.add(pairingId));
    await _openCommuteChat(context, pairingId, _isBn);
    if (mounted) setState(() => _openingChatIds.remove(pairingId));
  }

  Future<void> _rate(String pairingId, String otherUserId) async {
    int rating = 5;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'রেটিং দিন' : 'Rate partner', style: const TextStyle(color: AppColors.textPrimary)),
        content: Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => IconButton(icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B)), onPressed: () => setD(() => rating = i + 1)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'জমা দিন' : 'Submit')),
        ],
      )),
    );
    if (confirmed != true) return;
    try {
      await CommuteService.instance.ratePairing(pairingId, otherUserId, rating);
      if (mounted) _showSnack(context, _isBn ? 'ধন্যবাদ!' : 'Thanks!', success: true);
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_pairings.isEmpty) return Center(child: Text(_isBn ? 'কোনো ট্রিপ নেই' : 'No trips yet', style: const TextStyle(color: AppColors.textMuted)));
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.deepBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _pairings.length,
        itemBuilder: (ctx, i) {
          final p = _pairings[i];
          final offer = p['offer'] as Map<String, dynamic>?;
          final isDriver = p['driverId'] == _myUserId;
          final otherUserId = isDriver ? p['passengerId'] as String : p['driverId'] as String;
          final status = p['status'] as String? ?? 'active';
          final cost = _asDoubleOrNull(offer?['costShareAmount']) ?? 0;
          // No reveal gate for commute — phones are always visible once a pairing exists.
          final otherPhone = isDriver ? p['passengerPhoneSnapshot'] as String? : offer?['driverPhoneSnapshot'] as String?;
          final pairingId = p['id'] as String;
          final isOpeningChat = _openingChatIds.contains(pairingId);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glassBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(offer != null ? '${offer['originArea']} → ${offer['destinationArea'] ?? ''}' : (_isBn ? 'রুট অজানা' : 'Unknown route'), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Text(status, style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 4),
              Text(isDriver ? (_isBn ? 'আপনি চালক' : 'You are the driver') : (_isBn ? 'আপনি যাত্রী' : 'You are the passenger'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (otherPhone != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 18),
                  const SizedBox(width: 8),
                  Text(otherPhone, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                ]),
              ],
              const SizedBox(height: 8),
              GestureDetector(
                onTap: isOpeningChat ? null : () => _openChat(pairingId),
                child: Row(children: [
                  isOpeningChat
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                      : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.deepBlue, size: 16),
                  const SizedBox(width: 8),
                  Text(isDriver ? (_isBn ? 'যাত্রীর সাথে চ্যাট করুন' : 'Chat with passenger') : (_isBn ? 'চালকের সাথে চ্যাট করুন' : 'Chat with driver'), style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
              if (status == 'active') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loggingTripIds.contains(pairingId)
                          ? null
                          : () => _logTrip(pairingId, 'completed'),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF10B981))),
                      icon: const Icon(Icons.check_rounded,
                          color: Color(0xFF10B981), size: 16),
                      label: Text(_isBn ? 'আজ গিয়েছি' : 'Rode today',
                          style: const TextStyle(
                              color: Color(0xFF10B981), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loggingTripIds.contains(pairingId)
                          ? null
                          : () => _logTrip(pairingId, 'skipped'),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.glassBorder)),
                      icon: const Icon(Icons.remove_rounded,
                          color: AppColors.textMuted, size: 16),
                      label: Text(_isBn ? 'আজ যাইনি' : 'Skipped',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  if (!isDriver) Expanded(child: GlassButton(label: _isBn ? 'পেমেন্ট' : 'Pay', onPressed: () => _pay(p['id'] as String, cost))),
                  if (!isDriver) const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: () => _end(p['id'] as String), style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFEF4444))), child: Text(_isBn ? 'শেষ করুন' : 'End', style: const TextStyle(color: Color(0xFFEF4444))))),
                ]),
              ],
              if (status == 'ended') ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => _rate(p['id'] as String, otherUserId), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.deepBlue)), child: Text(_isBn ? 'রেটিং দিন' : 'Rate', style: const TextStyle(color: AppColors.deepBlue))),
              ],
            ]),
          ).animate(delay: Duration(milliseconds: 40 * i)).fadeIn(duration: 250.ms);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TAB 4 — Profile (default area/vehicle + phone/NID verification request)
// ─────────────────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();
  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  bool _isBn = true;
  bool _loading = true;
  bool _saving = false;
  bool _requesting = false;
  bool _phoneVerified = false;
  bool _nidVerified = false;
  final _areaCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _vehicleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await CommuteService.instance.getMyProfile();
      if (mounted) setState(() {
        _areaCtrl.text = profile['defaultOriginArea'] as String? ?? '';
        _vehicleCtrl.text = profile['vehicleType'] as String? ?? '';
        _phoneVerified = profile['phoneVerified'] as bool? ?? false;
        _nidVerified = profile['nidVerified'] as bool? ?? false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CommuteService.instance.upsertMyProfile(
        defaultOriginArea: _areaCtrl.text.trim().isEmpty ? null : _areaCtrl.text.trim(),
        vehicleType: _vehicleCtrl.text.trim().isEmpty ? null : _vehicleCtrl.text.trim(),
      );
      if (mounted) _showSnack(context, _isBn ? 'প্রোফাইল সংরক্ষিত হয়েছে' : 'Profile saved', success: true);
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestVerification() async {
    setState(() => _requesting = true);
    try {
      await CommuteService.instance.requestVerification();
      if (mounted) _showSnack(context, _isBn ? 'অনুরোধ পাঠানো হয়েছে — এডমিন শীঘ্রই যাচাই করবেন' : 'Request sent — an admin will verify you soon', success: true);
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Widget _buildVehiclePicker() {
    final current = _vehicleCtrl.text.trim().toLowerCase();
    return Row(
      children: [
        for (final type in kRideVehicleTypes)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _vehicleCtrl.text = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: current == type ? AppColors.glassBlue : AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: current == type ? AppColors.deepBlue : AppColors.glassBorder,
                      width: current == type ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        switch (type) {
                          'motorcycle' => Icons.two_wheeler_rounded,
                          'cng' => Icons.electric_rickshaw_rounded,
                          _ => Icons.directions_car_filled_rounded,
                        },
                        size: 20,
                        color: current == type ? AppColors.deepBlue : AppColors.textMuted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // A vehicleType outside the known three (older data, or a new
                        // type added server-side) must not crash the profile tab.
                        (_isBn ? kRideVehicleLabelsBn[type] : kRideVehicleLabelsEn[type]) ?? type,
                        style: TextStyle(
                          color: current == type ? AppColors.deepBlue : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_phoneVerified)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.deepBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.35))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.verified_user_outlined, color: AppColors.deepBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_isBn ? 'পেয়ারিং কনফার্ম করতে ফোন ভেরিফিকেশন লাগবে' : 'Phone verification is required before pairing can be confirmed', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12.5, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 10),
              GlassButton(label: _requesting ? (_isBn ? 'পাঠানো হচ্ছে...' : 'Sending...') : (_isBn ? 'ভেরিফিকেশনের জন্য অনুরোধ করুন' : 'Request verification'), onPressed: _requesting ? null : _requestVerification),
            ]),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35))),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(
                (_isBn ? 'ফোন ভেরিফাইড' : 'Phone verified') + (_nidVerified ? (_isBn ? ' · NID ভেরিফাইড' : ' · NID verified') : ''),
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12.5, fontWeight: FontWeight.w700),
              )),
            ]),
          ),
        Text(_isBn ? 'ডিফল্ট এলাকা' : 'Default area', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(controller: _areaCtrl, style: const TextStyle(color: AppColors.textPrimary), decoration: _commuteDeco(hint: _isBn ? 'যেমন: মিরপুর-১০' : 'e.g. Mirpur-10')),
        const SizedBox(height: 20),
        Text(_isBn ? 'গাড়ির ধরন (যদি চালক হন)' : 'Vehicle type (if you drive)', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          _isBn
              ? 'অন-ডিমান্ড রাইড শুধু এই ধরনের চালকদের কাছেই যায় — তাই সঠিকটি বেছে নিন।'
              : 'On-demand rides are only offered to drivers of the matching type, so pick accurately.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        // This used to be free text. Nothing typed here ("car", "কার", "Toyota") ever matched
        // the three types the dispatch broadcast filters on, so the go-online flow had to stop
        // and ask for the vehicle in a dialog EVERY time. Picking from the real list saves the
        // answer once and the dialog never appears again.
        _buildVehiclePicker(),
        const SizedBox(height: 24),
        GlassButton(label: _saving ? (_isBn ? 'সংরক্ষণ হচ্ছে...' : 'Saving...') : (_isBn ? 'প্রোফাইল সংরক্ষণ করুন' : 'Save profile'), onPressed: _saving ? null : _save),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// One-off trip lifecycle (pay → complete → rate), shown right after a match.
// There's no "list my one-off trips" endpoint in commute-service (only recurring
// pairings have one) — the passenger/driver already has everything needed to run
// the whole lifecycle from the trip+post returned at match time, so this sheet is
// the entry point rather than a persisted tab. If either party backs out before
// finishing (e.g. pays later), they can re-match is not possible, but paying,
// completing and rating all remain reachable next time this sheet is reopened —
// in practice parties complete this in one sitting right after matching.
// ─────────────────────────────────────────────────────────────────────────

class _OneOffTripSheet extends StatefulWidget {
  final Map<String, dynamic> trip;
  final OneOffCommutePostModel post;
  const _OneOffTripSheet({required this.trip, required this.post});

  @override
  State<_OneOffTripSheet> createState() => _OneOffTripSheetState();
}

class _OneOffTripSheetState extends State<_OneOffTripSheet> {
  bool _isBn = true;
  bool _busy = false;
  bool _isOpeningChat = false;
  String? _myUserId;
  late Map<String, dynamic> _trip;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _init();
  }

  Future<void> _init() async {
    final id = await ApiClient.getUserId();
    if (mounted) setState(() => _myUserId = id);
  }

  String get _tripId => _trip['id'] as String;
  bool get _isPassenger => _myUserId != null && _trip['passengerId'] == _myUserId;
  String get _paymentStatus => _trip['paymentStatus'] as String? ?? 'pending';
  bool get _isCompleted => _trip['completedAt'] != null;

  Future<void> _pay() async {
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
    setState(() => _busy = true);
    try {
      final transaction = await CommuteService.instance.initiateOneOffPayment(_tripId);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        setState(() => _busy = false);
        _showSnack(context, _isBn ? 'পেমেন্ট শুরু করা যায়নি' : 'Could not start payment');
        return;
      }
      final amount = _asDoubleOrNull(_trip['amount']) ?? widget.post.costShareAmount ?? 0;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'কমিউট পেমেন্ট' : 'Commute Payment',
          titleEn: 'Commute Payment',
          amount: amount,
          checkStatus: () async {
            try {
              await CommuteService.instance.confirmOneOffPayment(_tripId);
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
        ),
      ));
      if (mounted) setState(() { _busy = false; _trip = {..._trip, 'paymentStatus': 'paid'}; });
    } catch (e) {
      if (mounted) { setState(() => _busy = false); _showSnack(context, ApiClient.mapError(e).localized(_isBn)); }
    }
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      await CommuteService.instance.completeOneOffTrip(_tripId);
      if (mounted) setState(() { _busy = false; _trip = {..._trip, 'completedAt': DateTime.now().toIso8601String()}; });
    } catch (e) {
      if (mounted) { setState(() => _busy = false); _showSnack(context, ApiClient.mapError(e).localized(_isBn)); }
    }
  }

  Future<void> _openChat() async {
    setState(() => _isOpeningChat = true);
    await _openCommuteChat(context, _tripId, _isBn);
    if (mounted) setState(() => _isOpeningChat = false);
  }

  Future<void> _rate() async {
    final otherUserId = (_isPassenger ? _trip['driverId'] : _trip['passengerId']) as String;
    int rating = 5;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'রেটিং দিন' : 'Rate partner', style: const TextStyle(color: AppColors.textPrimary)),
        content: Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) => IconButton(icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B)), onPressed: () => setD(() => rating = i + 1)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'জমা দিন' : 'Submit')),
        ],
      )),
    );
    if (confirmed != true) return;
    try {
      await CommuteService.instance.rateOneOffTrip(_tripId, otherUserId, rating);
      if (mounted) { _showSnack(context, _isBn ? 'ধন্যবাদ!' : 'Thanks!', success: true); Navigator.pop(context); }
    } catch (e) {
      if (mounted) _showSnack(context, ApiClient.mapError(e).localized(_isBn));
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    final p = widget.post;
    final amount = _asDoubleOrNull(_trip['amount']) ?? p.costShareAmount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isBn ? 'ট্রিপ ম্যাচ হয়েছে!' : 'Trip matched!', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('${p.originArea} → ${p.destinationArea ?? ''}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${p.tripDateTime.day}/${p.tripDateTime.month} ${p.tripDateTime.hour.toString().padLeft(2, '0')}:${p.tripDateTime.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        if (amount != null) ...[
          const SizedBox(height: 4),
          Text('৳${amount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
        // No reveal gate for commute — phones are always visible once a trip is matched.
        if ((_isPassenger ? _trip['driverPhoneSnapshot'] : _trip['passengerPhoneSnapshot']) != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 18),
            const SizedBox(width: 8),
            Text((_isPassenger ? _trip['driverPhoneSnapshot'] : _trip['passengerPhoneSnapshot']) as String, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ]),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _isOpeningChat ? null : _openChat,
          child: Row(children: [
            _isOpeningChat
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.deepBlue, size: 16),
            const SizedBox(width: 8),
            Text(_isPassenger ? (_isBn ? 'চালকের সাথে চ্যাট করুন' : 'Chat with driver') : (_isBn ? 'যাত্রীর সাথে চ্যাট করুন' : 'Chat with passenger'), style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 20),
        if (_isCompleted)
          OutlinedButton(onPressed: _rate, style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.deepBlue)), child: Text(_isBn ? 'রেটিং দিন' : 'Rate', style: const TextStyle(color: AppColors.deepBlue)))
        else ...[
          if (_isPassenger && _paymentStatus != 'paid')
            GlassButton(label: _busy ? (_isBn ? 'অপেক্ষা করুন...' : 'Please wait...') : (_isBn ? 'পেমেন্ট করুন' : 'Pay now'), onPressed: _busy ? null : _pay)
          else if (!_isPassenger && _paymentStatus != 'paid')
            Text(_isBn ? 'যাত্রীর পেমেন্টের অপেক্ষায়' : 'Waiting for the passenger to pay', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : _complete,
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.glassBorder)),
            child: Text(_isBn ? 'ট্রিপ সম্পন্ন হিসেবে চিহ্নিত করুন' : 'Mark trip complete', style: const TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ]),
    );
  }
}
