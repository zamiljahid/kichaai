import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/skill_share_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import 'payment_waiting_screen.dart';

/// Read-only-ish detail for one of MY OWN exchanges (reached from the
/// "এক্সচেঞ্জ" tab). Accepting/rejecting someone else's open post now happens
/// from the discovery feed itself (skill_share_screen.dart's "অনুরোধ" tab) —
/// this screen used to also carry accept/reject buttons, but the condition
/// gating them (`responderId == myUserId` while `status == 'proposed'`) could
/// never be true by construction (responderId is only ever set as the
/// RESULT of accepting), so they were unreachable dead code even before this
/// rewrite moved responding elsewhere.
class ExchangeDetailScreen extends StatefulWidget {
  final String exchangeId;
  const ExchangeDetailScreen({super.key, required this.exchangeId});

  @override
  State<ExchangeDetailScreen> createState() => _ExchangeDetailScreenState();
}

class _ExchangeDetailScreenState extends State<ExchangeDetailScreen> {
  final _svc = SkillShareService.instance;
  Map<String, dynamic>? _exchange;
  bool _isLoading = true;
  String? _userId;
  bool _busy = false;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final e = await _svc.getExchange(widget.exchangeId);
      if (mounted) setState(() { _exchange = e; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'বাতিল করুন?' : 'Cancel?', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(_isBn ? 'এই এক্সচেঞ্জ বাতিল করতে চান?' : 'Do you want to cancel this exchange?', style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'না' : 'No', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'হ্যাঁ' : 'Yes', style: const TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await _svc.cancelExchange(widget.exchangeId);
      await _load();
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scheduleSession() {
    DateTime? picked;
    final dateLabelCtrl = TextEditingController();
    int duration = 60;
    final notesCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: AppColors.bgMid,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(_isBn ? 'সেশন শিডিউল করুন' : 'Schedule a Session', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: dateLabelCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      readOnly: true,
                      onTap: () async {
                        final p = await _showDateTimePicker(ctx);
                        if (p != null) {
                          picked = p;
                          setS(() => dateLabelCtrl.text = '${p.day}/${p.month}/${p.year} — ${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}');
                        }
                      },
                      decoration: InputDecoration(
                        hintText: _isBn ? 'তারিখ ও সময়' : 'Date and time',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.calendar_today_outlined, color: AppColors.textMuted, size: 18),
                        filled: true,
                        fillColor: AppColors.glassWhite,
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Text(_isBn ? 'সময়কাল (মিনিট):' : 'Duration (minutes):', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const Spacer(),
                      IconButton(onPressed: () => setS(() => duration = (duration - 30).clamp(30, 120)), icon: const Icon(Icons.remove_rounded, color: AppColors.textMuted, size: 18)),
                      Text('$duration', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                      IconButton(onPressed: () => setS(() => duration = (duration + 30).clamp(30, 120)), icon: const Icon(Icons.add_rounded, color: AppColors.deepBlue, size: 18)),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: _isBn ? 'নোট' : 'Notes',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.glassWhite,
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: _isBn ? 'শিডিউল করুন' : 'Schedule',
                      isLoading: submitting,
                      onPressed: submitting ? null : () async {
                        if (picked == null) { _showError(_isBn ? 'তারিখ ও সময় বাছাই করুন' : 'Choose a date and time'); return; }
                        setS(() => submitting = true);
                        try {
                          await _svc.scheduleSession(
                            exchangeId: widget.exchangeId,
                            scheduledAt: picked!.toIso8601String(),
                            durationMins: duration,
                            notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                          );
                          if (ctx.mounted) { Navigator.pop(ctx); _load(); }
                        } catch (e) {
                          setS(() => submitting = false);
                          if (ctx.mounted) _showError(ApiClient.mapError(e).localized(_isBn));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ৳100 platform fee — both sides pay before a session can be scheduled (backend enforces
  // this at scheduleSession; this button is how either side actually satisfies it).
  Future<void> _payFee() async {
    try {
      final res = await _svc.initiateFeePayment(widget.exchangeId);
      final gatewayPageUrl = res['gatewayPageUrl'] as String?;
      if (gatewayPageUrl == null) {
        _showError(_isBn ? 'পেমেন্ট শুরু করা যায়নি' : 'Could not start the payment');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'প্ল্যাটফর্ম ফি' : 'Platform Fee',
          titleEn: 'Platform Fee',
          amount: 100,
          checkStatus: () async {
            try {
              await _svc.confirmFeePayment(widget.exchangeId);
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
          applyCoupon: (code) async {
            final t = await _svc.initiateFeePayment(widget.exchangeId, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? 100};
          },
        ),
      ));
      await _load();
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _reportReciprocity(bool wasTaught) async {
    try {
      await _svc.reportNonReciprocity(widget.exchangeId, wasTaught: wasTaught);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'ধন্যবাদ, জানানো হয়েছে' : 'Thanks, noted', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  void _showReciprocityPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_isBn ? 'তিনি কি স্কিলটি শিখিয়েছেন?' : 'Did they actually teach the skill?', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          _isBn
              ? 'তারা যে স্কিল অফার করেছিলেন সেটা কি সত্যিই শিখিয়েছেন? "না" দিলে তারা প্ল্যাটফর্ম থেকে স্থায়ীভাবে নিষিদ্ধ হবেন।'
              : 'Did they genuinely teach you the skill they offered? Answering "No" permanently bans them from skill-share.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); _reportReciprocity(false); }, child: Text(_isBn ? 'না' : 'No', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700))),
          TextButton(onPressed: () { Navigator.pop(ctx); _reportReciprocity(true); }, child: Text(_isBn ? 'হ্যাঁ, শিখিয়েছেন' : 'Yes, they did', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  void _showReviewDialog() {
    int rating = 5;
    final reviewCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(_isBn ? 'রিভিউ দিন' : 'Leave a Review', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < rating;
                  return IconButton(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    constraints: const BoxConstraints(),
                    onPressed: () => setS(() => rating = i + 1),
                    icon: Icon(filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: const Color(0xFFF59E0B), size: 32),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reviewCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _isBn ? 'আপনার অভিজ্ঞতা লিখুন…' : 'Describe your experience…',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.glassBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.deepBlue)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted))),
            TextButton(
              onPressed: () async {
                final text = reviewCtrl.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                await _submitReview(rating, text);
              },
              child: Text(_isBn ? 'জমা দিন' : 'Submit', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview(int rating, String review) async {
    try {
      await _svc.reviewExchange(widget.exchangeId, rating: rating, review: review);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'রিভিউ জমা হয়েছে' : 'Review submitted', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<DateTime?> _showDateTimePicker(BuildContext ctx) async {
    final date = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null) return null;
    if (!ctx.mounted) return null;
    final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    final status = _exchange?['status'] as String? ?? '';
    final isRequester = _exchange?['requesterId'] == _userId;
    final requesterFeePaid = _exchange?['requesterFeePaid'] == true;
    final responderFeePaid = _exchange?['responderFeePaid'] == true;
    final myFeePaid = isRequester ? requesterFeePaid : responderFeePaid;
    final requesterReciprocityReport = _exchange?['requesterReciprocityReport'];
    final responderReciprocityReport = _exchange?['responderReciprocityReport'];
    final myReciprocityReport = isRequester ? requesterReciprocityReport : responderReciprocityReport;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'এক্সচেঞ্জ বিবরণ' : 'Exchange Details', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if ((status == 'proposed' || status == 'accepted') && !_busy)
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 20),
              onPressed: _cancel,
              tooltip: _isBn ? 'বাতিল করুন' : 'Cancel',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : _exchange == null
              ? Center(child: Text(_isBn ? 'লোড করা যায়নি' : 'Could not load', style: const TextStyle(color: AppColors.textMuted)))
              : RefreshIndicator(
                  color: AppColors.deepBlue,
                  backgroundColor: AppColors.bgMid,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      _buildStatusCard(status),
                      const SizedBox(height: 16),
                      _buildSkillSwap(isRequester),
                      const SizedBox(height: 16),
                      if (status == 'proposed' && isRequester) ...[
                        Text(_isBn ? 'অন্য কেউ সাড়া দেওয়ার অপেক্ষায় — "অনুরোধ" ফিডে দেখা যাচ্ছে' : 'Waiting for someone to respond — visible in the "Requests" feed', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.5)),
                        const SizedBox(height: 16),
                      ],
                      if (status == 'accepted') ...[
                        if (!myFeePaid) ...[
                          Text(
                            _isBn ? 'সেশন শিডিউল করার আগে ৳১০০ প্ল্যাটফর্ম ফি দিতে হবে (উভয় পক্ষকেই)।' : 'A ৳100 platform fee is required from both sides before a session can be scheduled.',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.5),
                          ),
                          const SizedBox(height: 10),
                          GlassButton(label: _isBn ? '৳১০০ ফি দিন' : 'Pay ৳100 fee', onPressed: _payFee),
                        ] else ...[
                          Text(_isBn ? 'আপনার ফি পরিশোধ হয়েছে ✓ — অন্য পক্ষের অপেক্ষায় থাকতে পারে।' : 'Your fee is paid ✓ — the other side may still be pending.', style: const TextStyle(color: Color(0xFF10B981), fontSize: 12.5)),
                          const SizedBox(height: 10),
                          GlassButton(label: _isBn ? 'সেশন শিডিউল করুন' : 'Schedule a session', onPressed: _scheduleSession),
                        ],
                        const SizedBox(height: 16),
                      ],
                      if (status == 'completed') ...[
                        GlassButton(label: _isBn ? 'রিভিউ দিন' : 'Leave a review', onPressed: _showReviewDialog),
                        const SizedBox(height: 10),
                        if (myReciprocityReport == null)
                          OutlinedButton(
                            onPressed: _showReciprocityPrompt,
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.glassBorder), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: Text(_isBn ? 'তিনি কি সত্যিই শিখিয়েছেন? জানান' : 'Report whether they actually taught you', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                          )
                        else
                          Text(_isBn ? 'আপনি ইতিমধ্যে জানিয়েছেন ✓' : 'You already reported this ✓', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 16),
                      ],
                      _buildSessionsSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatusCard(String status) {
    final colors = {
      'proposed': const Color(0xFFF59E0B),
      'accepted': const Color(0xFF10B981),
      'completed': const Color(0xFF8B5CF6),
      'cancelled': const Color(0xFFEF4444),
    };
    final color = colors[status] ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.swap_horiz_rounded, color: color, size: 28),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isBn ? 'স্ট্যাটাস: $status' : 'Status: $status', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          Text(_isBn ? '${_exchange?['agreedSessionCount'] ?? 1} সেশন প্রস্তাবিত' : '${_exchange?['agreedSessionCount'] ?? 1} session(s) proposed', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ]),
    ).animate().fadeIn();
  }

  Widget _buildSkillSwap(bool isRequester) {
    final offered = _exchange?['offeredSkill'] as Map<String, dynamic>?;
    final wanted = _exchange?['wantedSkill'] as Map<String, dynamic>?;
    final offeredName = offered?['skillName'] as String? ?? (_isBn ? 'অজানা' : 'Unknown');
    final wantedName = (wanted?['skillName'] as String?) ?? (_exchange?['wantedSkillName'] as String?) ?? _exchange?['wantedSkillCategory'] as String? ?? (_isBn ? 'অজানা' : 'Unknown');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(children: [
        Expanded(
          child: Column(children: [
            const Icon(Icons.person_outline_rounded, color: AppColors.deepBlue, size: 24),
            const SizedBox(height: 4),
            Text(
              isRequester ? (_isBn ? 'আপনি দিচ্ছেন' : 'You\'re giving') : (_isBn ? 'উনি দিচ্ছেন' : 'They\'re giving'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
            ),
            const SizedBox(height: 2),
            Text(offeredName, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        const Icon(Icons.swap_horiz_rounded, color: AppColors.deepBlue, size: 28),
        Expanded(
          child: Column(children: [
            const Icon(Icons.person_outline_rounded, color: AppColors.deepBlue, size: 24),
            const SizedBox(height: 4),
            Text(
              isRequester ? (_isBn ? 'উনি দিচ্ছেন' : 'They\'re giving') : (_isBn ? 'আপনি দিচ্ছেন' : 'You\'re giving'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
            ),
            const SizedBox(height: 2),
            Text(wantedName, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSessionsSection() {
    final sessions = (_exchange?['sessions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isBn ? 'সেশনসমূহ' : 'Sessions', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 10),
        if (sessions.isEmpty)
          Text(_isBn ? 'কোনো সেশন নেই' : 'No sessions yet', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))
        else
          ...sessions.map((s) {
            final done = s['status'] == 'completed';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgMid,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(children: [
                Icon(done ? Icons.check_circle_rounded : Icons.schedule_rounded, color: done ? const Color(0xFF10B981) : AppColors.textMuted, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['scheduledAt']?.toString().substring(0, 16) ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  Text(_isBn ? '${s['durationMins'] ?? 0} মিনিট' : '${s['durationMins'] ?? 0} min', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ])),
                if (!done)
                  TextButton(
                    onPressed: () async {
                      try {
                        await _svc.completeSession(s['id'] as String);
                        _load();
                      } catch (e) {
                        _showError(ApiClient.mapError(e).localized(_isBn));
                      }
                    },
                    child: Text(_isBn ? 'সম্পন্ন' : 'Complete', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12)),
                  ),
              ]),
            );
          }),
      ],
    );
  }
}
