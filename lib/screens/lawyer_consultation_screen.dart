import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/network/api_client.dart';
import '../models/dispatch_model.dart';
import '../services/dispatch_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// Customer-facing lawyer consultation booking (Uber-style).
///  1. pick legal area + service, describe the problem
///  2. create a lawyer job → broadcast notifies matching online lawyers
///  3. the FIRST lawyer to accept wins → the job carries the Meet link
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

  int? _onlineCount; // null = unknown/endpoint unavailable → badge hidden
  int _countSeq = 0; // guards against out-of-order responses

  String? _jobId;
  JobModel? _job;    // set once a lawyer accepts
  String? _meetLink; // Google Meet link (video consultations), set on accept
  bool _busy = false;
  Timer? _pollTimer;

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
      if (mounted) setState(() { _loadingOptions = false; _error = ApiClient.mapError(e).messageBn; });
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
    if (_area == null) return _snack('বিষয় বাছুন', error: true);
    if (_service == null) return _snack('সেবা বাছুন', error: true);
    final description = _descCtrl.text.trim();
    if (description.length < _kMinDescriptionChars) {
      return _snack('আপনার সমস্যাটি একটু বিস্তারিত লিখুন', error: true);
    }
    setState(() { _step = _Step.waiting; _error = null; });
    try {
      final customerId = await ApiClient.getUserId() ?? '';
      final areaLabel = _areas.firstWhere((a) => a['code'] == _area, orElse: () => {})['bn'] ?? '';
      final job = await _dispatch.createJob(
        customerId: customerId,
        serviceTypeId: 'st_lawyer',
        serviceKind: 'lawyer',
        title: 'আইনি পরামর্শ — $areaLabel',
        description: description,
        // Remote consultation — coordinates are unused for matching; send a default.
        pickupLatitude: 23.8103,
        pickupLongitude: 90.4125,
        legalArea: _area,
        legalService: _service,
        consultationMode: 'video',
      );
      if (job.notifiedProviderCount == 0) {
        // Broadcast reached nobody — don't leave the customer on a spinner.
        if (mounted) setState(() => _step = _Step.select);
        _snack('এই মুহূর্তে কোনো আইনজীবী পাওয়া যায়নি — পরে আবার চেষ্টা করুন', error: true);
        return;
      }
      _jobId = job.id;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollJob());
    } catch (e) {
      if (mounted) setState(() { _step = _Step.select; _error = ApiClient.mapError(e).messageBn; });
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
        // Google call) — keep polling until the link lands.
        if (hasLink) _pollTimer?.cancel();
        setState(() { _job = job; _meetLink = job.meetLink; _step = _Step.joined; });
      } else if (job.status == 'cancelled' || job.status == 'expired') {
        // Unclaimed jobs auto-expire backend-side after 15 minutes.
        _pollTimer?.cancel();
        setState(() => _step = _Step.select);
        _snack(
          job.status == 'expired'
              ? 'সময় শেষ — আবার চেষ্টা করুন'
              : 'এই মুহূর্তে কোনো আইনজীবী পাওয়া যায়নি — আবার চেষ্টা করুন',
          error: true,
        );
      }
    } catch (_) {
      // transient poll error — keep trying on the next tick
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

  Widget _appBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text('আইনি পরামর্শ',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _body() {
    switch (_step) {
      case _Step.waiting:
        return _centered(
          const CircularProgressIndicator(color: AppColors.deepBlue),
          'একজন আইনজীবী খোঁজা হচ্ছে…\nকেউ গ্রহণ করা মাত্রই এখানে জানানো হবে।',
        );
      case _Step.joined:
        return _joinedView();
      case _Step.select:
        return _selectView();
    }
  }

  // ── SELECT: one compact form — area, service, description, mode ────

  Widget _selectView() {
    if (_loadingOptions) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionCard(
          title: 'কী বিষয়ে সাহায্য চান?',
          child: _dropdown(
            value: _area,
            hint: 'বিষয় বাছাই করুন',
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
          title: 'কী ধরনের সেবা?',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _dropdown(
              value: _service,
              hint: 'সেবা বাছাই করুন',
              items: _services,
              markAdvocateOnly: true,
              onChanged: (c) {
                setState(() => _service = c);
                _refreshOnlineCount();
              },
            ),
            if (_services.any(_isAdvocateOnly)) ...[
              const SizedBox(height: 10),
              const Row(children: [
                Icon(Icons.gavel_rounded, size: 13, color: AppColors.textMuted),
                SizedBox(width: 5),
                Expanded(
                  child: Text('= শুধু আইনজীবী নিতে পারবেন (আইন সহকারী নয়)',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ),
              ]),
            ],
          ]),
        ),
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
            label: 'আইনজীবী খুঁজুন',
            icon: Icons.search_rounded,
            onPressed: _formValid ? _search : null,
          ),
        ),
      ]),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) => GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  static bool _isAdvocateOnly(Map<String, dynamic> it) =>
      it['advocate'] == true && it['assistant'] != true;

  InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
        filled: true,
        fillColor: const Color(0xFFF9F7F0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.deepBlue, width: 1.5),
        ),
      );

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
  }) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(14),
        menuMaxHeight: 380,
        decoration: _fieldDecoration(hint: hint),
        hint: Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
        items: items.map((it) {
          final code = it['code'] as String;
          final label = (it['bn'] ?? it['en'] ?? code).toString();
          final advocateOnly = markAdvocateOnly && _isAdvocateOnly(it);
          return DropdownMenuItem<String>(
            value: code,
            child: Row(children: [
              if (leadingIcon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.glassBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(leadingIcon(code), size: 16, color: AppColors.deepBlue),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              if (advocateOnly) ...[
                const SizedBox(width: 6),
                const Icon(Icons.gavel_rounded, size: 15, color: AppColors.deepBlue),
              ],
            ]),
          );
        }).toList(),
        onChanged: onChanged,
      );

  // ── Description — what the lawyer reads before accepting ───────────

  Widget _descriptionCard() {
    final len = _descCtrl.text.trim().length;
    final enough = len >= _kMinDescriptionChars;
    return _sectionCard(
      title: 'আপনার সমস্যাটি সংক্ষেপে লিখুন',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _descCtrl,
          minLines: 4,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
          decoration: _fieldDecoration(
              hint: 'যেমন: ৩ বছর আগে বিয়ে হয়েছে, এখন তালাক চাই, ১টি সন্তান আছে।'),
        ),
        const SizedBox(height: 8),
        enough
            ? const Row(children: [
                Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                SizedBox(width: 5),
                Text('যথেষ্ট বিবরণ দেওয়া হয়েছে',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600)),
              ])
            : Text(
                'আইনজীবী আগে থেকে আপনার সমস্যা বুঝে প্রস্তুত হতে পারবেন — কমপক্ষে ${_bnDigits(_kMinDescriptionChars)} অক্ষর লিখুন (${_bnDigits(len)}/${_bnDigits(_kMinDescriptionChars)})',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
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
          color: const Color(0x14D98A0B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x40D98A0B)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB27107)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'এই মুহূর্তে এই বিষয়ে কোনো আইনজীবী অনলাইন নেই — অনুরোধ পাঠালে অপেক্ষা করতে হতে পারে।',
              style: TextStyle(color: Color(0xFF8A5A06), fontSize: 12, height: 1.4),
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
          Text('${_bnDigits(count)} জন আইনজীবী অনলাইন',
              style: const TextStyle(
                  color: Color(0xFF067A57), fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    ]);
  }

  // ── JOINED — the Google Meet link card ──────────────────────────────

  Widget _joinedView() => _centered(
        Container(
          width: 84, height: 84,
          decoration: const BoxDecoration(color: Color(0x3310B981), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 56),
        ),
        '${_job?.providerNameSnapshot ?? 'একজন আইনজীবী'} যুক্ত হয়েছেন',
        action: Column(children: [
          if (_meetLink != null && _meetLink!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.deepBlue.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.deepBlue.withOpacity(0.35)),
              ),
              child: Column(children: [
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.videocam_rounded, color: AppColors.deepBlue, size: 20),
                  SizedBox(width: 8),
                  Text('ভিডিও কলের লিংক তৈরি হয়েছে',
                      style: TextStyle(color: AppColors.deepBlue, fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                SelectableText(_meetLink!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                GlassButton(
                  label: 'লিংক কপি করুন',
                  icon: Icons.copy_rounded,
                  isOutlined: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _meetLink!));
                    _snack('লিংক কপি হয়েছে');
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          GlassButton(
            label: 'কেস ডকুমেন্ট যোগ করুন',
            icon: Icons.upload_file_rounded,
            isOutlined: true,
            isLoading: _busy,
            onPressed: _busy ? null : _addCaseDocument,
          ),
          const SizedBox(height: 12),
          GlassButton(label: 'সম্পন্ন', onPressed: () => Navigator.of(context).pop()),
        ]),
      );

  Future<void> _addCaseDocument() async {
    if (_jobId == null) return;
    final urlCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('কেস ডকুমেন্ট', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ডকুমেন্টের লিংক দিন (ছবি/PDF)। আইনজীবী এটি দেখতে পাবেন।',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://…',
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.glassBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.deepBlue)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: typeCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'ধরন (যেমন: legal_notice) — ঐচ্ছিক',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.glassBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.deepBlue)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('বাতিল', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              final u = urlCtrl.text.trim();
              if (u.startsWith('http')) Navigator.pop(ctx, true);
            },
            child: const Text('যোগ করুন', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
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
      _snack('ডকুমেন্ট যোগ হয়েছে');
    } catch (e) {
      _snack(ApiClient.mapError(e).messageBn, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _centered(Widget top, String msg, {Widget? action}) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            top,
            const SizedBox(height: 20),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 24), action],
          ]),
        ),
      );
}
