import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../core/utils/meet_link.dart';
import '../models/dispatch_model.dart';
import '../services/dispatch_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'payment_waiting_screen.dart';
import 'lawyer_ai_chat_screen.dart';
import '../theme/status_colors.dart';

/// Customer-facing lawyer consultation booking (Uber-style).
///  1. pick legal area + service, describe the problem, pick instant vs schedule
///  2. create a lawyer job → broadcast notifies matching online lawyers
///  3a. instant: the FIRST lawyer to accept wins → the job carries the Meet link
///  3b. schedule: a lawyer may instead propose 1-3 times; the customer picks
///      one (any lawyer can still just instant-accept first, which wins same as 3a)
///  4. poll the job until accepted, then show the Meet link to join.
///
/// Consultations are Google Meet ONLY — no phone/chat/in-person. Handing the
/// lawyer the customer's phone number is the direct route off-platform (bypasses
/// commission) and moves a privileged legal conversation out of the company-owned
/// Meet room. Deliberate product + revenue decision; do not re-add a mode selector.
class LawyerConsultationScreen extends StatefulWidget {
  const LawyerConsultationScreen({super.key});

  @override
  State<LawyerConsultationScreen> createState() => _LawyerConsultationScreenState();
}

enum _Step { select, waiting, joined }

const _kMinDescriptionChars = 20;

const _areaIcons = <String, IconData>{
  'civil_property': Icons.home_work_rounded,
  'family': Icons.family_restroom_rounded,
  'criminal': Icons.gavel_rounded,
  'cheque_loan': Icons.account_balance_wallet_rounded,
  'labor': Icons.engineering_rounded,
  'consumer_rights': Icons.shopping_bag_rounded,
  'tax_vat': Icons.receipt_long_rounded,
  'other': Icons.more_horiz_rounded,
};

class _LawyerConsultationScreenState extends State<LawyerConsultationScreen> {
  final _dispatch = DispatchService.instance;

  _Step _step = _Step.select;
  bool _loadingOptions = true;
  String? _error;

  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _services = [];
  String? _area;
  String? _service;
  final _descCtrl = TextEditingController();

  // 'instant' = today's only behaviour (broadcast, first to accept wins).
  // 'schedule' = additionally lets a busy lawyer propose times instead of
  // accepting right away — see _slotOffers below.
  String _timing = 'instant';

  int? _onlineCount; // null = unknown/endpoint unavailable → badge hidden
  int _countSeq = 0; // guards against out-of-order responses

  String? _jobId;
  JobModel? _job;    // set once a lawyer accepts
  String? _meetLink; // Google Meet link (video consultations), set on accept
  bool _busy = false;
  Timer? _pollTimer;

  // Schedule-mode only: proposals from lawyers who haven't been picked yet.
  List<Map<String, dynamic>> _slotOffers = [];
  bool _pickingSlot = false;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _refreshOnlineCount();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() { _loadingOptions = true; _error = null; });
    try {
      final opts = await OnboardingService.instance.getLegalOptions();
      if (!mounted) return;
      setState(() {
        _areas = (opts['areas'] as List? ?? []).cast<Map<String, dynamic>>();
        _services = (opts['services'] as List? ?? []).cast<Map<String, dynamic>>();
        _loadingOptions = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loadingOptions = false; _error = ApiClient.mapError(e).localized(_isBn); });
    }
  }

  Future<void> _refreshOnlineCount() async {
    final seq = ++_countSeq;
    final count = await _dispatch.countOnlineLawyers(legalArea: _area, legalService: _service);
    if (!mounted || seq != _countSeq) return;
    setState(() => _onlineCount = count);
  }

  bool get _formValid =>
      _area != null && _service != null && _descCtrl.text.trim().length >= _kMinDescriptionChars;

  Future<void> _search() async {
    if (_area == null) return _snack(_isBn ? 'বিষয় বাছুন' : 'Choose a topic', error: true);
    if (_service == null) return _snack(_isBn ? 'সেবা বাছুন' : 'Choose a service', error: true);
    final description = _descCtrl.text.trim();
    if (description.length < _kMinDescriptionChars) {
      return _snack(_isBn ? 'আপনার সমস্যাটি একটু বিস্তারিত লিখুন' : 'Describe your issue in a bit more detail', error: true);
    }
    setState(() { _step = _Step.waiting; _error = null; });
    try {
      final customerId = await ApiClient.getUserId() ?? '';
      final area = _areas.firstWhere((a) => a['code'] == _area, orElse: () => {});
      final areaLabel = (_isBn ? area['bn'] : (area['en'] ?? area['bn'])) ?? '';
      final job = await _dispatch.createJob(
        customerId: customerId,
        serviceTypeId: 'st_lawyer',
        serviceKind: 'lawyer',
        title: _isBn ? 'আইনি পরামর্শ — $areaLabel' : 'Legal Consultation — $areaLabel',
        description: description,
        // Remote consultation — coordinates are unused for matching; send a default.
        pickupLatitude: 23.8103,
        pickupLongitude: 90.4125,
        legalArea: _area,
        legalService: _service,
        consultationMode: 'video',
        consultationTiming: _timing,
      );
      if (job.notifiedProviderCount == 0) {
        // Broadcast reached nobody — don't leave the customer on a spinner.
        if (mounted) setState(() => _step = _Step.select);
        _snack(_isBn ? 'এই মুহূর্তে কোনো আইনজীবী পাওয়া যায়নি — পরে আবার চেষ্টা করুন' : 'No lawyer is available right now — try again later', error: true);
        return;
      }
      _jobId = job.id;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollJob());
    } catch (e) {
      if (mounted) setState(() { _step = _Step.select; _error = ApiClient.mapError(e).localized(_isBn); });
    }
  }

  Future<void> _pollJob() async {
    if (_jobId == null || !mounted) return;
    try {
      final job = await _dispatch.getJob(_jobId!);
      if (!mounted) return;
      final hasLink = job.meetLink != null && job.meetLink!.isNotEmpty;
      if (hasLink || job.status == 'accepted') {
        // Accept flips status before the Meet link is generated (external
        // Google call) — keep polling until the link lands. Also covers a
        // schedule-mode job someone picked a slot on from elsewhere/another
        // device — pickSlot itself already got its own meetLink locally.
        if (hasLink) _pollTimer?.cancel();
        setState(() { _job = job; _meetLink = job.meetLink; _step = _Step.joined; });
      } else if (job.status == 'cancelled' || job.status == 'expired') {
        // Unclaimed jobs auto-expire backend-side (15 min instant / 24h schedule).
        _pollTimer?.cancel();
        setState(() { _step = _Step.select; _slotOffers = []; });
        _snack(
          job.status == 'expired'
              ? (_isBn ? 'সময় শেষ — আবার চেষ্টা করুন' : 'Time is up — try again')
              : (_isBn ? 'এই মুহূর্তে কোনো আইনজীবী পাওয়া যায়নি — আবার চেষ্টা করুন' : 'No lawyer is available right now — try again'),
          error: true,
        );
      } else if (_timing == 'schedule' && job.status == 'searching') {
        // Still open — check whether any lawyer has proposed times yet.
        try {
          final offers = await _dispatch.listSlotOffers(_jobId!);
          if (mounted) setState(() => _slotOffers = offers);
        } catch (_) {}
      }
    } catch (_) {
      // transient poll error — keep trying on the next tick
    }
  }

  // The waiting screen previously had no way out — a customer stuck here (e.g. because they
  // accidentally have two open requests and this one will never be accepted, see createJob's
  // duplicate-lawyer-request guard) had to fall back to the browser/OS back button, which leaves
  // the job dangling in "searching" forever. Lets them cancel and immediately try again.
  Future<void> _cancelWaitingJob() async {
    if (_jobId == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _dispatch.cancelJob(_jobId!);
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _step = _Step.select;
        _jobId = null;
        _slotOffers = [];
      });
      _snack(_isBn ? 'অনুরোধ বাতিল হয়েছে' : 'Request cancelled');
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickSlot(String providerId, int slotIndex) async {
    if (_jobId == null || _pickingSlot) return;
    setState(() => _pickingSlot = true);
    try {
      await _dispatch.pickSlot(_jobId!, providerId: providerId, slotIndex: slotIndex);
      if (!mounted) return;
      final job = await _dispatch.getJob(_jobId!);
      // No meetLink yet — picking a slot only locks the TIME in; the link is created once
      // the consultation fee is paid (see _joinedView's pay-now card). Keep _pollTimer running
      // so it auto-picks up the link once payment clears, same as the instant-accept path.
      setState(() {
        _job = job;
        _meetLink = job.meetLink;
        _step = _Step.joined;
      });
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
      // Someone else may have taken this slot/job first — refresh the offer list.
      try {
        final offers = await _dispatch.listSlotOffers(_jobId!);
        if (mounted) setState(() => _slotOffers = offers);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _pickingSlot = false);
    }
  }

  // The matched/scheduled lawyer has no Meet link yet — the backend only creates it once this
  // clears (see dispatch.service.ts's confirmDepositPayment), so this is the moment the
  // consultation actually becomes joinable. Same initiate → open gateway → poll → verify
  // pattern as the course-enrollment and advance-booking-deposit flows.
  Future<void> _payNow() async {
    if (_jobId == null || _busy) return;
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
    setState(() => _busy = true);
    try {
      final transaction = await _dispatch.initiateDepositPayment(_jobId!);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        _snack(_isBn ? 'পেমেন্ট শুরু করা যায়নি — আবার চেষ্টা করুন' : 'Could not start the payment — please try again', error: true);
        return;
      }
      final fee = _job?.depositAmount ?? 0;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'পরামর্শ ফি' : 'Consultation Fee',
          titleEn: 'Consultation Fee',
          amount: fee,
          checkStatus: () async {
            try {
              await _dispatch.confirmDepositPayment(_jobId!);
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
          applyCoupon: (code) async {
            final t = await _dispatch.initiateDepositPayment(_jobId!, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? fee};
          },
        ),
      ));
      if (!mounted) return;
      // Payment confirmed server-side already created the Meet link — refresh now instead
      // of waiting for the next 4s poll tick.
      await _pollJob();
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
    ));
  }

  static String _bnDigits(int n) =>
      n.toString().split('').map((d) => '০১২৩৪৫৬৭৮৯'[int.parse(d)]).join();

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _appBar(),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBar() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colors.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Text(_isBn ? 'আইনি পরামর্শ' : 'Legal Consultation',
              style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );
  }

  Widget _body() {
    final colors = Theme.of(context).colorScheme;
    switch (_step) {
      case _Step.waiting:
        if (_timing == 'schedule' && _slotOffers.isNotEmpty) return _slotOffersView();
        return _centered(
          CircularProgressIndicator(color: colors.primary),
          _isBn
              ? (_timing == 'schedule'
                  ? 'একজন আইনজীবী খোঁজা হচ্ছে…\nকেউ সময় প্রস্তাব করলে বা সরাসরি গ্রহণ করলে এখানে জানানো হবে।'
                  : 'একজন আইনজীবী খোঁজা হচ্ছে…\nকেউ গ্রহণ করা মাত্রই এখানে জানানো হবে।')
              : (_timing == 'schedule'
                  ? 'Finding a lawyer…\nYou\'ll be notified here the moment someone proposes a time or accepts directly.'
                  : 'Finding a lawyer…\nYou\'ll be notified here the moment someone accepts.'),
          action: TextButton(
            onPressed: _busy ? null : _cancelWaitingJob,
            child: Text(
              _isBn ? 'অনুরোধ বাতিল করুন' : 'Cancel request',
              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
            ),
          ),
        );
      case _Step.joined:
        return _joinedView();
      case _Step.select:
        return _selectView();
    }
  }

  // ── SELECT: one compact form — area, service, description, mode ────

  Widget _selectView() {
    final colors = Theme.of(context).colorScheme;
    if (_loadingOptions) return Center(child: CircularProgressIndicator(color: colors.primary));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _askAiCard(),
        const SizedBox(height: 14),
        _sectionCard(
          title: _isBn ? 'কী বিষয়ে সাহায্য চান?' : 'What do you need help with?',
          child: _dropdown(
            value: _area,
            hint: _isBn ? 'বিষয় বাছাই করুন' : 'Choose a topic',
            items: _areas,
            leadingIcon: (code) => _areaIcons[code] ?? Icons.balance_rounded,
            onChanged: (c) {
              setState(() => _area = c);
              _refreshOnlineCount();
            },
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: _isBn ? 'কী ধরনের সেবা?' : 'What kind of service?',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _dropdown(
              value: _service,
              hint: _isBn ? 'সেবা বাছাই করুন' : 'Choose a service',
              items: _services,
              markAdvocateOnly: true,
              onChanged: (c) {
                setState(() => _service = c);
                _refreshOnlineCount();
              },
            ),
            if (_services.any(_isAdvocateOnly)) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.gavel_rounded, size: 13, color: colors.outline),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(_isBn ? '= শুধু আইনজীবী নিতে পারবেন (আইন সহকারী নয়)' : '= only advocates can take this (not legal assistants)',
                      style: TextStyle(color: colors.outline, fontSize: 11)),
                ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        _timingSelector(),
        const SizedBox(height: 14),
        _descriptionCard(),
        const SizedBox(height: 18),
        _onlineBadge(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
        ],
        const SizedBox(height: 14),
        Opacity(
          opacity: _formValid ? 1 : 0.45,
          child: GlassButton(
            label: _isBn ? 'আইনজীবী খুঁজুন' : 'Find a lawyer',
            icon: Icons.search_rounded,
            onPressed: _formValid ? _search : null,
          ),
        ),
      ]),
    );
  }

  // Opens the separate lawyer-triage AI chat; if it returns a confident
  // {legalArea, legalService, description} suggestion, pre-fill the form with it
  // (still editable — this doesn't skip the customer's own review before searching).
  Future<void> _openAskAi() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => LawyerAiChatScreen(isBn: _isBn)),
    );
    if (result == null || !mounted) return;
    setState(() {
      final area = result['legalArea'] as String?;
      final service = result['legalService'] as String?;
      final description = result['description'] as String?;
      if (area != null && _areas.any((a) => a['code'] == area)) _area = area;
      if (service != null && _services.any((s) => s['code'] == service)) _service = service;
      if (description != null && description.isNotEmpty) _descCtrl.text = description;
    });
    _refreshOnlineCount();
  }

  Widget _askAiCard() {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
        onTap: _openAskAi,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppGradients.primary(colors),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _isBn ? 'জানেন না কোন lawyer লাগবে?' : "Not sure which lawyer you need?",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _isBn ? 'AI এর সাথে কথা বলে বুঝে নিন' : 'Talk to our AI to figure it out',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
      );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          child,
        ]),
      );
  }

  // ── Instant vs Schedule ──────────────────────────────────────────

  Widget _timingSelector() => _sectionCard(
        title: _isBn ? 'কখন কথা বলতে চান?' : 'When do you want to talk?',
        child: Row(children: [
          Expanded(
            child: _timingOption(
              value: 'instant',
              icon: Icons.bolt_rounded,
              label: _isBn ? 'এখনই' : 'Now',
              sublabel: _isBn ? 'যিনি প্রথমে গ্রহণ করবেন' : 'Whoever accepts first',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _timingOption(
              value: 'schedule',
              icon: Icons.event_available_rounded,
              label: _isBn ? 'সময় ঠিক করুন' : 'Schedule',
              sublabel: _isBn ? 'ব্যস্ত হলেও সময় প্রস্তাব করবেন' : 'They\'ll propose a time if busy',
            ),
          ),
        ]),
      );

  Widget _timingOption({
    required String value,
    required IconData icon,
    required String label,
    required String sublabel,
  }) {
    final colors = Theme.of(context).colorScheme;
    final selected = _timing == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _timing = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withOpacity(0.08) : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 1.5 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 22, color: selected ? colors.primary : colors.outline),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: selected ? colors.primary : colors.onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sublabel,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.outline, fontSize: 10.5, height: 1.3)),
        ]),
      ),
    );
  }

  // ── Schedule-mode: pick from lawyers' proposed times ────────────────

  Widget _slotOffersView() {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_isBn ? 'একজন আইনজীবী কিছু সময় প্রস্তাব করেছেন' : 'A lawyer has proposed some times',
              style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_isBn ? 'আপনার জন্য সুবিধাজনক একটি সময় বেছে নিন — তখনই একটি Meet লিংক তৈরি হবে।' : 'Pick a time that works for you — a Meet link will be created right then.',
              style: TextStyle(color: colors.outline, fontSize: 12.5)),
          const SizedBox(height: 16),
          ..._slotOffers.map(_slotOfferCard),
          const SizedBox(height: 8),
          Center(
            child: Text(_isBn ? 'অন্য আইনজীবীরাও এখনই বা সময় প্রস্তাব করে যুক্ত হতে পারেন — এখানেই দেখা যাবে।' : 'Other lawyers may also join by accepting now or proposing times — you\'ll see it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.outline, fontSize: 11.5)),
          ),
        ]),
      );
  }

  Widget _slotOfferCard(Map<String, dynamic> offer) {
    final colors = Theme.of(context).colorScheme;
    final providerId = offer['providerId'] as String? ?? '';
    final name = (offer['providerNameSnapshot'] as String?)?.trim();
    final slots = (offer['slots'] as List? ?? []).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.gavel_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Text(name?.isNotEmpty == true ? name! : (_isBn ? 'একজন আইনজীবী' : 'A lawyer'),
                style: TextStyle(color: colors.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(slots.length, (i) {
              final start = DateTime.tryParse(slots[i]['start'] as String? ?? '');
              final end = DateTime.tryParse(slots[i]['end'] as String? ?? '');
              final label = start == null
                  ? '—'
                  : end == null
                      ? _fmtSlot(start)
                      : '${_fmtSlot(start)} – ${_fmtTimeOnly(end)}';
              return OutlinedButton(
                onPressed: _pickingSlot ? null : () => _pickSlot(providerId, i),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              );
            }),
          ),
        ]),
      ),
    );
  }

  static const _bnMonths = [
    'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
  ];
  static const _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmtSlot(DateTime d) {
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    final mm = local.minute.toString().padLeft(2, '0');
    final month = (_isBn ? _bnMonths : _enMonths)[local.month - 1];
    final day = _isBn ? _bnDigits(local.day) : '${local.day}';
    final hour = _isBn ? _bnDigits(h) : '$h';
    return '$day $month, $hour:$mm $ampm';
  }

  String _fmtTimeOnly(DateTime d) {
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    final mm = local.minute.toString().padLeft(2, '0');
    final hour = _isBn ? _bnDigits(h) : '$h';
    return '$hour:$mm $ampm';
  }

  static bool _isAdvocateOnly(Map<String, dynamic> it) =>
      it['advocate'] == true && it['assistant'] != true;

  InputDecoration _fieldDecoration({String? hint}) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.outline, fontSize: 13.5),
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      );
  }

  /// `markAdvocateOnly`: services the backend restricts to advocates (court
  /// representation, bail, case filing, full opinion) get a gavel on the right
  /// so the customer knows a legal assistant cannot take it.
  Widget _dropdown({
    required String? value,
    required String hint,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
    IconData Function(String code)? leadingIcon,
    bool markAdvocateOnly = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: colors.outline),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(14),
        menuMaxHeight: 380,
        decoration: _fieldDecoration(hint: hint),
        hint: Text(hint, style: TextStyle(color: colors.outline, fontSize: 13.5)),
        items: items.map((it) {
    final colors = Theme.of(context).colorScheme;
          final code = it['code'] as String;
          final label = ((_isBn ? it['bn'] : it['en']) ?? it['bn'] ?? it['en'] ?? code).toString();
          final advocateOnly = markAdvocateOnly && _isAdvocateOnly(it);
          return DropdownMenuItem<String>(
            value: code,
            child: Row(children: [
              if (leadingIcon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(leadingIcon(code), size: 16, color: colors.primary),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              if (advocateOnly) ...[
                const SizedBox(width: 6),
                Icon(Icons.gavel_rounded, size: 15, color: colors.primary),
              ],
            ]),
          );
        }).toList(),
        onChanged: onChanged,
      );
  }

  // ── Description — what the lawyer reads before accepting ───────────

  Widget _descriptionCard() {
    final colors = Theme.of(context).colorScheme;
    final len = _descCtrl.text.trim().length;
    final enough = len >= _kMinDescriptionChars;
    return _sectionCard(
      title: _isBn ? 'আপনার সমস্যাটি সংক্ষেপে লিখুন' : 'Briefly describe your issue',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _descCtrl,
          minLines: 4,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: colors.onSurface, fontSize: 14, height: 1.5),
          decoration: _fieldDecoration(
              hint: _isBn ? 'যেমন: ৩ বছর আগে বিয়ে হয়েছে, এখন তালাক চাই, ১টি সন্তান আছে।' : 'e.g. Married 3 years ago, want a divorce now, have 1 child.'),
        ),
        const SizedBox(height: 8),
        enough
            ? Row(children: [
                const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 5),
                Text(_isBn ? 'যথেষ্ট বিবরণ দেওয়া হয়েছে' : 'Enough detail provided',
                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600)),
              ])
            : Text(
                _isBn
                    ? 'আইনজীবী আগে থেকে আপনার সমস্যা বুঝে প্রস্তুত হতে পারবেন — কমপক্ষে ${_bnDigits(_kMinDescriptionChars)} অক্ষর লিখুন (${_bnDigits(len)}/${_bnDigits(_kMinDescriptionChars)})'
                    : 'This lets the lawyer understand your issue beforehand — write at least $_kMinDescriptionChars characters ($len/$_kMinDescriptionChars)',
                style: TextStyle(color: colors.outline, fontSize: 11),
              ),
      ]),
    );
  }

  // ── Online-lawyers badge — hidden while the endpoint is unavailable ─

  Widget _onlineBadge() {
    final count = _onlineCount;
    if (count == null) return const SizedBox.shrink();
    if (count == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: StatusColors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: StatusColors.amber.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB27107)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isBn
                  ? 'এই মুহূর্তে এই বিষয়ে কোনো আইনজীবী অনলাইন নেই — অনুরোধ পাঠালে অপেক্ষা করতে হতে পারে।'
                  : 'No lawyer for this topic is online right now — sending a request may mean a wait.',
              style: const TextStyle(color: Color(0xFF8A5A06), fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      );
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x1410B981),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color(0x3310B981)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(_isBn ? '${_bnDigits(count)} জন আইনজীবী অনলাইন' : '$count lawyer${count == 1 ? '' : 's'} online',
              style: const TextStyle(
                  color: Color(0xFF067A57), fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    ]);
  }

  // ── JOINED — the Google Meet link card ──────────────────────────────

  Widget _joinedView() {
    final colors = Theme.of(context).colorScheme;
    return _centered(
        Container(
          width: 84, height: 84,
          decoration: const BoxDecoration(color: Color(0x3310B981), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 56),
        ),
        _job?.depositRequired == true
            ? (_isBn
                ? '${_job?.providerNameSnapshot ?? 'একজন আইনজীবী'} মিলেছেন — পেমেন্ট বাকি'
                : '${_job?.providerNameSnapshot ?? 'A lawyer'} matched — payment pending')
            : (_isBn
                ? '${_job?.providerNameSnapshot ?? 'একজন আইনজীবী'} যুক্ত হয়েছেন'
                : '${_job?.providerNameSnapshot ?? 'A lawyer'} has joined'),
        action: Column(children: [
          if (_job?.depositRequired == true) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: StatusColors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StatusColors.amber.withValues(alpha: 0.35)),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.payments_rounded, color: Color(0xFFB27107), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isBn ? 'Meet লিংক পেতে পরামর্শ ফি পরিশোধ করুন' : 'Pay the consultation fee to get your Meet link',
                      style: const TextStyle(color: Color(0xFF8A5A06), fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                GlassButton(
                  label: _isBn
                      ? '৳${_bnDigits((_job?.depositAmount ?? 0).round())} পরিশোধ করুন'
                      : 'Pay ৳${(_job?.depositAmount ?? 0).round()}',
                  icon: Icons.payments_rounded,
                  isLoading: _busy,
                  onPressed: _busy ? null : _payNow,
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          if (_meetLink != null && _meetLink!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.primary.withOpacity(0.35)),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.videocam_rounded, color: colors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(_isBn ? 'ভিডিও কলের লিংক তৈরি হয়েছে' : 'Video call link created',
                      style: TextStyle(color: colors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                SelectableText(_meetLink!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 10),
                GlassButton(
                  label: _isBn ? 'মিটিং এ যোগ দিন' : 'Join meeting',
                  icon: Icons.videocam_rounded,
                  onPressed: () => openMeetLink(context, _meetLink!),
                ),
                const SizedBox(height: 8),
                GlassButton(
                  label: _isBn ? 'লিংক কপি করুন' : 'Copy link',
                  icon: Icons.copy_rounded,
                  isOutlined: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _meetLink!));
                    _snack(_isBn ? 'লিংক কপি হয়েছে' : 'Link copied');
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          GlassButton(
            label: _isBn ? 'কেস ডকুমেন্ট যোগ করুন' : 'Add case document',
            icon: Icons.upload_file_rounded,
            isOutlined: true,
            isLoading: _busy,
            onPressed: _busy ? null : _addCaseDocument,
          ),
          const SizedBox(height: 12),
          GlassButton(label: _isBn ? 'সম্পন্ন' : 'Done', onPressed: () => Navigator.of(context).pop()),
        ]),
      );
  }

  Future<void> _addCaseDocument() async {
    final colors = Theme.of(context).colorScheme;
    if (_jobId == null) return;
    final urlCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isBn ? 'কেস ডকুমেন্ট' : 'Case Document', style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isBn ? 'ডকুমেন্টের লিংক দিন (ছবি/PDF)। আইনজীবী এটি দেখতে পাবেন।' : 'Enter a document link (image/PDF). The lawyer will be able to see it.',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: TextStyle(color: colors.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://…',
                hintStyle: TextStyle(color: colors.outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.outlineVariant)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.primary)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: typeCtrl,
              style: TextStyle(color: colors.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: _isBn ? 'ধরন (যেমন: legal_notice) — ঐচ্ছিক' : 'Type (e.g. legal_notice) — optional',
                hintStyle: TextStyle(color: colors.outline, fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.outlineVariant)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.primary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: TextStyle(color: colors.outline))),
          TextButton(
            onPressed: () {
              final u = urlCtrl.text.trim();
              if (u.startsWith('http')) Navigator.pop(ctx, true);
            },
            child: Text(_isBn ? 'যোগ করুন' : 'Add', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _dispatch.addConsultationDocument(
        _jobId!,
        fileUrl: urlCtrl.text.trim(),
        docType: typeCtrl.text.trim().isNotEmpty ? typeCtrl.text.trim() : null,
      );
      _snack(_isBn ? 'ডকুমেন্ট যোগ হয়েছে' : 'Document added');
    } catch (e) {
      _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _centered(Widget top, String msg, {Widget? action}) {
    final colors = Theme.of(context).colorScheme;
    return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            top,
            const SizedBox(height: 20),
            Text(msg, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 24), action],
          ]),
        ),
      );
  }
}
