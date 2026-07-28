import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';

class ExchangeDetailScreen extends StatefulWidget {
  final String exchangeId;
  const ExchangeDetailScreen({super.key, required this.exchangeId});

  @override
  State<ExchangeDetailScreen> createState() => _ExchangeDetailScreenState();
}

class _ExchangeDetailScreenState extends State<ExchangeDetailScreen> {
  final _client = ApiClient.instance.dio;
  Map<String, dynamic>? _exchange;
  bool _isLoading = true;
  String? _userId;

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
      final res = await _client.get('/skill-share/exchanges/${widget.exchangeId}');
      if (mounted) setState(() { _exchange = res.data as Map<String, dynamic>?; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _respond(bool accepted) async {
    try {
      await _client.post('/skill-share/exchanges/${widget.exchangeId}/respond', data: {'accepted': accepted});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accepted ? 'গ্রহণ করা হয়েছে' : 'প্রত্যাখ্যান করা হয়েছে', style: const TextStyle(color: Colors.white)),
            backgroundColor: accepted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: const Text('বাতিল করুন?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('এই এক্সচেঞ্জ বাতিল করতে চান?', style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('হ্যাঁ', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _client.post('/skill-share/exchanges/${widget.exchangeId}/cancel');
      await _load();
    } catch (_) {}
  }

  void _scheduleSession() {
    final dateCtrl = TextEditingController();
    int duration = 60;
    final notesCtrl = TextEditingController();

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
                    const Text('সেশন শিডিউল করুন', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: dateCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDateTimePicker(ctx);
                        if (picked != null) dateCtrl.text = picked.toIso8601String();
                      },
                      decoration: const InputDecoration(
                        hintText: 'তারিখ ও সময়',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        prefixIcon: Icon(Icons.calendar_today_outlined, color: AppColors.textMuted, size: 18),
                        filled: true,
                        fillColor: AppColors.glassWhite,
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('সময়কাল (মিনিট):', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const Spacer(),
                      IconButton(onPressed: () => setS(() => duration = (duration - 30).clamp(30, 120)), icon: const Icon(Icons.remove_rounded, color: AppColors.textMuted, size: 18)),
                      Text('$duration', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                      IconButton(onPressed: () => setS(() => duration = (duration + 30).clamp(30, 120)), icon: const Icon(Icons.add_rounded, color: AppColors.deepBlue, size: 18)),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'নোট',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.glassWhite,
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: 'শিডিউল করুন',
                                            onPressed: () async {
                        try {
                          await _client.post('/skill-share/sessions', data: {
                            'exchangeId': widget.exchangeId,
                            'scheduledAt': dateCtrl.text,
                            'durationMinutes': duration,
                            'notes': notesCtrl.text,
                          });
                          if (ctx.mounted) { Navigator.pop(ctx); _load(); }
                        } catch (_) {}
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

  void _showReviewDialog() {
    int rating = 5;
    final reviewCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('রিভিউ দিন', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
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
                  hintText: 'আপনার অভিজ্ঞতা লিখুন…',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.glassBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.deepBlue)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল', style: TextStyle(color: AppColors.textMuted))),
            TextButton(
              onPressed: () async {
                final text = reviewCtrl.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                await _submitReview(rating, text);
              },
              child: const Text('জমা দিন', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview(int rating, String review) async {
    try {
      await _client.post('/skill-share/exchanges/${widget.exchangeId}/review', data: {
        'reviewerUserId': _userId,
        'rating': rating,
        'review': review,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('রিভিউ জমা হয়েছে', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.mapError(e).messageBn, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<DateTime?> showDateTimePicker(BuildContext ctx) async {
    final date = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null) return null;
    final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final status = _exchange?['status'] as String? ?? '';
    final isResponder = _exchange?['responderId'] == _userId;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('এক্সচেঞ্জ বিবরণ', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (status == 'proposed' || status == 'accepted')
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 20),
              onPressed: _cancel,
              tooltip: 'বাতিল করুন',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : _exchange == null
              ? const Center(child: Text('লোড করা যায়নি', style: TextStyle(color: AppColors.textMuted)))
              : RefreshIndicator(
                  color: AppColors.deepBlue,
                  backgroundColor: AppColors.bgMid,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      _buildStatusCard(status),
                      const SizedBox(height: 16),
                      _buildSkillSwap(),
                      const SizedBox(height: 16),
                      if (status == 'proposed' && isResponder) ...[
                        Row(children: [
                          Expanded(child: GlassButton(label: 'প্রত্যাখ্যান করুন', onPressed: () => _respond(false))),
                          const SizedBox(width: 12),
                          Expanded(child: GlassButton(label: 'গ্রহণ করুন',  onPressed: () => _respond(true))),
                        ]),
                        const SizedBox(height: 16),
                      ],
                      if (status == 'accepted') ...[
                        GlassButton(label: 'সেশন শিডিউল করুন',  onPressed: _scheduleSession),
                        const SizedBox(height: 16),
                      ],
                      if (status == 'completed') ...[
                        GlassButton(label: 'রিভিউ দিন', onPressed: _showReviewDialog),
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(Icons.swap_horiz_rounded, color: color, size: 28),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('স্ট্যাটাস: $status', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('${_exchange?['proposedSessions'] ?? 0} সেশন প্রস্তাবিত', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ]),
    ).animate().fadeIn();
  }

  Widget _buildSkillSwap() {
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
            const Icon(Icons.person_outline_rounded, color: AppColors.deepBlue, size: 28),
            const SizedBox(height: 4),
            Text('আবেদনকারী', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        ),
        const Icon(Icons.swap_horiz_rounded, color: AppColors.deepBlue, size: 32),
        Expanded(
          child: Column(children: [
            const Icon(Icons.person_outline_rounded, color: AppColors.deepBlue, size: 28),
            const SizedBox(height: 4),
            const Text('প্রতিক্রিয়াকারী', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
        const Text('সেশনসমূহ', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 10),
        if (sessions.isEmpty)
          const Text('কোনো সেশন নেই', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
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
                  Text('${s['durationMinutes'] ?? 0} মিনিট', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ])),
                if (!done)
                  TextButton(
                    onPressed: () async {
                      try {
                        await _client.post('/skill-share/sessions/${s['id']}/complete');
                        _load();
                      } catch (_) {}
                    },
                    child: const Text('সম্পন্ন', style: TextStyle(color: AppColors.deepBlue, fontSize: 12)),
                  ),
              ]),
            );
          }),
      ],
    );
  }
}
