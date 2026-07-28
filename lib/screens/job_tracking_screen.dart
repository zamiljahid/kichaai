import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/dispatch_model.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import 'chat_screen.dart';
import 'rating_screen.dart';

class JobTrackingScreen extends StatefulWidget {
  final String jobId;
  const JobTrackingScreen({super.key, required this.jobId});

  @override
  State<JobTrackingScreen> createState() => _JobTrackingScreenState();
}

class _JobTrackingScreenState extends State<JobTrackingScreen> {
  JobModel? _job;
  bool _isLoading = true;
  Timer? _timer;
  bool _isConfirming = false;
  bool _isOpeningChat = false;

  // Platform rate for this job's task category — shown next to a CUSTOM quote so
  // the customer has a fair-price reference before approving (they otherwise have
  // no idea whether ৳4000 for a ৳800-class job is normal).
  TaskCategoryRate? _platformRate;

  @override
  void initState() {
    super.initState();
    _fetch();
    _loadPlatformRate();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  Future<void> _loadPlatformRate() async {
    try {
      final raw = await DispatchService.instance.getTaskCategoryRates();
      if (!mounted) return;
      final rates = raw.map((e) => TaskCategoryRate.fromJson(e)).toList();
      setState(() {
        _platformRate = null;
        final cat = _job?.taskCategory;
        if (cat != null) {
          for (final r in rates) {
            if (r.taskCategory == cat) { _platformRate = r; break; }
          }
        }
        _allRates = rates;
      });
    } catch (_) {}
  }

  List<TaskCategoryRate> _allRates = [];

  TaskCategoryRate? get _rateForJob {
    if (_platformRate != null) return _platformRate;
    final cat = _job?.taskCategory;
    if (cat == null) return null;
    for (final r in _allRates) {
      if (r.taskCategory == cat) return r;
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final job = await DispatchService.instance.getJob(widget.jobId);
      if (!mounted) return;
      setState(() { _job = job; _isLoading = false; });
      if (job.status == 'completed') {
        _timer?.cancel();
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => RatingScreen(jobId: widget.jobId)),
            );
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmProvider() async {
    setState(() => _isConfirming = true);
    try {
      final updated = await DispatchService.instance.revealJobContact(widget.jobId);
      if (mounted) setState(() => _job = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('নিশ্চিত করা যায়নি — আবার চেষ্টা করুন', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  // The chat thread is auto-created by dispatch-service the moment a provider accepts (see
  // dispatch.service.ts createChatThread) — there's no "get thread by job" endpoint, so this
  // finds it by scanning the customer's own thread list for a matching dispatchJobId.
  Future<void> _openJobChat() async {
    setState(() => _isOpeningChat = true);
    try {
      final user = await AuthService.instance.getCurrentUser();
      final threads = await MessagingService.instance.listThreads(user.id);
      ThreadModel? thread;
      for (final t in threads) {
        if (t.dispatchJobId == widget.jobId) { thread = t; break; }
      }
      if (!mounted) return;
      if (thread == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('চ্যাট এখনো তৈরি হয়নি — একটু পরে আবার চেষ্টা করুন', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFFF59E0B),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('চ্যাট খোলা যায়নি', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              if (_isLoading && _job == null)
                const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.deepBlue)))
              else if (_job == null)
                Expanded(child: Center(child: Text('তথ্য পাওয়া যাচ্ছে না', style: TextStyle(color: AppColors.textMuted))))
              else
                Expanded(child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(children: [
                    _buildStatusCard(_job!),
                    const SizedBox(height: 16),
                    if (_job!.assignedProviderId != null) ...[
                      _buildProviderCard(_job!),
                      const SizedBox(height: 16),
                      if (_job!.serviceKind != 'lawyer' && !_job!.providerConfirmed) ...[
                        _buildConfirmProviderCard(_job!),
                        const SizedBox(height: 16),
                      ],
                      _buildLiveLocation(_job!),
                      const SizedBox(height: 16),
                    ],
                    _buildJobDetails(_job!),
                    const SizedBox(height: 16),
                    if (_job!.awaitingQuoteApproval) ...[
                      _buildQuoteApprovalCard(_job!),
                      const SizedBox(height: 16),
                    ],
                    if (_job!.status != 'cancelled' && _job!.status != 'completed')
                      _buildCancelButton(),
                  ]),
                )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
              child: const Icon(Icons.home_rounded, color: AppColors.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('অনুরোধ ট্র্যাকিং', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Job Tracking', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
          const Spacer(),
          _buildPulsingDot(),
        ],
      ),
    );
  }

  Widget _buildPulsingDot() {
    final job = _job;
    final isActive = job != null && job.isActive;
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF22C55E) : AppColors.glassBorder,
        shape: BoxShape.circle,
        boxShadow: isActive ? [BoxShadow(color: const Color(0xFF22C55E).withOpacity(0.5), blurRadius: 8)] : null,
      ),
    ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1000.ms).then().fadeIn(duration: 1000.ms);
  }

  Widget _buildStatusCard(JobModel job) {
    final info = _statusInfo(job.status);
    return GlassCard(
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [info.$2.withOpacity(0.3), info.$2.withOpacity(0.1)]),
              shape: BoxShape.circle,
              border: Border.all(color: info.$2.withOpacity(0.5), width: 2),
            ),
            child: Icon(info.$3, color: info.$2, size: 36),
          ),
          const SizedBox(height: 16),
          Text(info.$1, textAlign: TextAlign.center, style: TextStyle(color: info.$2, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('#${job.id.substring(0, 8).toUpperCase()}', style: TextStyle(color: AppColors.textMuted, fontSize: 12, letterSpacing: 1)),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  (String, Color, IconData) _statusInfo(String status) {
    switch (status) {
      case 'searching': return ('কাছের provider খোঁজা হচ্ছে...', AppColors.deepBlue, Icons.search_rounded);
      case 'assigned': return ('Provider পাওয়া গেছে, নিশ্চিত করার অপেক্ষায়', const Color(0xFFF59E0B), Icons.person_add_rounded);
      case 'accepted': return ('Provider আসছেন', const Color(0xFF8B5CF6), Icons.directions_walk_rounded);
      case 'arriving': return ('Provider কাছাকাছি!', const Color(0xFF06B6D4), Icons.near_me_rounded);
      case 'in_progress': return ('কাজ চলছে', const Color(0xFF10B981), Icons.build_circle_rounded);
      case 'completed': return ('কাজ সম্পন্ন! ⭐', const Color(0xFF22C55E), Icons.check_circle_rounded);
      case 'cancelled': return ('অনুরোধ বাতিল হয়েছে', const Color(0xFFEF4444), Icons.cancel_rounded);
      default: return (status, AppColors.textMuted, Icons.info_rounded);
    }
  }

  // ── Live location map — appears once a provider is assigned. Backend
  //    guarantees locationTracks is empty before assignment, so we show an
  //    explanatory placeholder rather than a blank map when the provider
  //    hasn't started sharing yet.
  Widget _buildLiveLocation(JobModel job) {
    // Newest first per backend contract.
    final latest = job.locationTracks.isNotEmpty ? job.locationTracks.first : null;

    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.my_location_rounded, color: AppColors.deepBlue, size: 18),
            const SizedBox(width: 6),
            const Text('লাইভ লোকেশন',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          if (latest == null)
            Container(
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'প্রোভাইডার এখনো লোকেশন শেয়ার করেননি',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(latest.latitude, latest.longitude),
                    zoom: 15,
                  ),
                  markers: {
                    Marker(
                      markerId: MarkerId(latest.id),
                      position: LatLng(latest.latitude, latest.longitude),
                      infoWindow: const InfoWindow(title: 'প্রোভাইডার'),
                    ),
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  liteModeEnabled: false,
                ),
              ),
            ),
        ],
      ),
    ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildProviderCard(JobModel job) {
    final name = job.providerNameSnapshot ?? job.assignedProviderId ?? '?';
    final phone = job.providerPhoneSnapshot;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
            child: Center(
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(color: AppColors.ivory, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('নির্ধারিত Provider', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              if (phone != null) Text(phone, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
          if (job.serviceKind != 'lawyer')
            GestureDetector(
              onTap: _isOpeningChat ? null : _openJobChat,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.glassWhite, shape: BoxShape.circle, border: Border.all(color: AppColors.glassBorder)),
                child: _isOpeningChat
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                    : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.deepBlue, size: 18),
              ),
            ),
          if (phone != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 22),
          ],
        ],
      ),
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.1);
  }

  // Shown between accept and the customer's explicit confirm — phone numbers are hidden on
  // both sides until this happens (chat is the only channel meanwhile).
  Widget _buildConfirmProviderCard(JobModel job) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'নম্বর দেখতে ও কল করতে আগে নিশ্চিত করুন — ততক্ষণ চ্যাটে কথা বলতে পারবেন',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _isOpeningChat ? null : _openJobChat,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassBorder, width: 1.5),
                  ),
                  child: const Text('চ্যাট করুন', style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _isConfirming ? null : _confirmProvider,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(12)),
                  child: _isConfirming
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('নিশ্চিত করুন', style: TextStyle(color: AppColors.ivory, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ],
      ),
    ).animate(delay: 120.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildJobDetails(JobModel job) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('অনুরোধের বিবরণ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _detail('সেবার ধরন', job.serviceKind),
          _detail('জরুরি মাত্রা', job.urgencyLevel ?? 'normal'),
          if (job.description?.isNotEmpty ?? false) _detail('বিবরণ', job.description!),
          if (job.estimatedAmount != null) _detail('আনুমানিক খরচ', '৳ ${job.estimatedAmount!.toStringAsFixed(0)}'),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildQuoteApprovalCard(JobModel job) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.request_quote_rounded, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              const Text('Provider-এর কোট', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('৳ ${job.quotedAmount!.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.w800)),
          ),
          if (_rateForJob != null) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final rate = _rateForJob!;
              final quoted = job.quotedAmount!;
              final high = quoted > rate.fixedPrice * 1.5;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (high ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: (high ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(high ? Icons.warning_amber_rounded : Icons.verified_outlined,
                        color: high ? const Color(0xFFEF4444) : const Color(0xFF10B981), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        high
                            ? 'প্ল্যাটফর্মের নির্ধারিত দাম ৳${rate.fixedPrice.toStringAsFixed(0)} — এই কোটটি তার চেয়ে অনেক বেশি'
                            : 'প্ল্যাটফর্মের নির্ধারিত দাম: ৳${rate.fixedPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: high ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 4),
          const Center(
            child: Text('অনুমোদন না করলে শুধু ভিজিট ফি দিতে হবে, কাজ বাতিল হবে।',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _respondQuote(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: const Text('প্রত্যাখ্যান', style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _respondQuote(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.blueGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('অনুমোদন করুন', style: TextStyle(color: AppColors.ivory, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Future<void> _respondQuote(bool approved) async {
    if (!approved) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bgMid,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('কোট প্রত্যাখ্যান?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text('কাজটি বাতিল হয়ে যাবে এবং শুধু ভিজিট ফি প্রযোজ্য হবে।',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('না', style: TextStyle(color: AppColors.textMuted))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('হ্যাঁ, প্রত্যাখ্যান', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final updated = await DispatchService.instance.respondToQuote(widget.jobId, approved: approved);
      if (mounted) setState(() => _job = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approved ? 'কোট অনুমোদিত — কাজ শুরু হবে' : 'কোট প্রত্যাখ্যাত — কাজ বাতিল',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: approved ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('কোট প্রক্রিয়া করতে সমস্যা হয়েছে', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: () async {
        try {
          await DispatchService.instance.cancelJob(widget.jobId);
          _fetch();
        } catch (_) {}
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4), width: 1.5),
        ),
        child: const Center(child: Text('অনুরোধ বাতিল করুন', style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w600))),
      ),
    ).animate(delay: 300.ms).fadeIn();
  }
}
