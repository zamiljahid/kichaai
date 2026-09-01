import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../core/utils/meet_link.dart';
import '../models/dispatch_model.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_gradients.dart';
import '../theme/status_colors.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'chat_screen.dart';
import 'payment_waiting_screen.dart';
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
  bool _isPayingOnline = false;

  // Platform rate for this job's task category — shown next to a CUSTOM quote so
  // the customer has a fair-price reference before approving (they otherwise have
  // no idea whether ৳4000 for a ৳800-class job is normal).
  TaskCategoryRate? _platformRate;
  bool _isBn = true;

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
          content: Text(_isBn ? 'নিশ্চিত করা যায়নি — আবার চেষ্টা করুন' : 'Could not confirm — try again', style: const TextStyle(color: Colors.white)),
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
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              if (_isLoading && _job == null)
                Expanded(child: Center(child: CircularProgressIndicator(color: colors.primary)))
              else if (_job == null)
                Expanded(child: Center(child: Text(_isBn ? 'তথ্য পাওয়া যাচ্ছে না' : 'Could not load information', style: TextStyle(color: colors.outline))))
              else
                Expanded(child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(children: [
                    _buildStatusCard(_job!),
                    const SizedBox(height: 16),
                    if (_job!.isRide) ...[
                      _buildRideSummaryCard(_job!),
                      const SizedBox(height: 16),
                    ],
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
                    if (_job!.serviceKind == 'lawyer' && (_job!.meetLink ?? '').isNotEmpty) ...[
                      _buildMeetLinkCard(_job!),
                      const SizedBox(height: 16),
                    ],
                    if ((_job!.opinionSummary ?? '').trim().isNotEmpty) ...[
                      _buildOpinionCard(_job!),
                      const SizedBox(height: 16),
                    ],
                    _buildJobDetails(_job!),
                    const SizedBox(height: 16),
                    if (_job!.awaitingQuoteApproval) ...[
                      _buildQuoteApprovalCard(_job!),
                      const SizedBox(height: 16),
                    ],
                    if (_showOnlinePaymentCard(_job!)) ...[
                      _buildOnlinePaymentCard(_job!),
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.outlineVariant, width: 1.5)),
              child: Icon(Icons.home_rounded, color: colors.onSurface, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_isBn ? 'অনুরোধ ট্র্যাকিং' : 'Job Tracking', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const Spacer(),
          _buildPulsingDot(),
        ],
      ),
    );
  }

  Widget _buildPulsingDot() {
    final colors = Theme.of(context).colorScheme;
    final job = _job;
    final isActive = job != null && job.isActive;
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF22C55E) : colors.outlineVariant,
        shape: BoxShape.circle,
        boxShadow: isActive ? [BoxShadow(color: const Color(0xFF22C55E).withOpacity(0.5), blurRadius: 8)] : null,
      ),
    ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1000.ms).then().fadeIn(duration: 1000.ms);
  }

  Widget _buildStatusCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
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
          Text('#${job.id.substring(0, 8).toUpperCase()}', style: TextStyle(color: colors.outline, fontSize: 12, letterSpacing: 1)),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  (String, Color, IconData) _statusInfo(String status) {
    final colors = Theme.of(context).colorScheme;
    switch (status) {
      case 'searching': return (_isBn ? 'কাছের provider খোঁজা হচ্ছে...' : 'Finding a nearby provider...', colors.primary, Icons.search_rounded);
      case 'assigned': return (_isBn ? 'সেবাদাতা পাওয়া গেছে, নিশ্চিত করার অপেক্ষায়' : 'Provider found, awaiting confirmation', const Color(0xFFF59E0B), Icons.person_add_rounded);
      case 'accepted': return (_isBn ? 'সেবাদাতা আসছেন' : 'Provider is on the way', const Color(0xFF8B5CF6), Icons.directions_walk_rounded);
      case 'arriving': return (_isBn ? 'সেবাদাতা কাছাকাছি!' : 'Provider is nearby!', const Color(0xFF06B6D4), Icons.near_me_rounded);
      case 'in_progress': return (_isBn ? 'কাজ চলছে' : 'Job in progress', const Color(0xFF10B981), Icons.build_circle_rounded);
      case 'completed': return (_isBn ? 'কাজ সম্পন্ন! ⭐' : 'Job complete! ⭐', const Color(0xFF22C55E), Icons.check_circle_rounded);
      case 'cancelled': return (_isBn ? 'অনুরোধ বাতিল হয়েছে' : 'Request cancelled', const Color(0xFFEF4444), Icons.cancel_rounded);
      default: return (status, colors.outline, Icons.info_rounded);
    }
  }

  // ── Live location map — appears once a provider is assigned. Backend
  //    guarantees locationTracks is empty before assignment, so we show an
  //    explanatory placeholder rather than a blank map when the provider
  //    hasn't started sharing yet.
  Widget _buildLiveLocation(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    // Newest first per backend contract.
    final latest = job.locationTracks.isNotEmpty ? job.locationTracks.first : null;

    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.my_location_rounded, color: colors.primary, size: 18),
            const SizedBox(width: 6),
            Text(_isBn ? 'লাইভ লোকেশন' : 'Live location',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          if (latest == null)
            Container(
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _isBn ? 'প্রোভাইডার এখনো লোকেশন শেয়ার করেননি' : 'The provider hasn\'t shared their location yet',
                  style: TextStyle(color: colors.outline, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else ...[
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
                      infoWindow: InfoWindow(title: _isBn ? 'প্রোভাইডার' : 'Provider'),
                    ),
                    Marker(
                      markerId: const MarkerId('pickup'),
                      position: LatLng(job.pickupLatitude, job.pickupLongitude),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      infoWindow: InfoWindow(
                          title: job.isRide
                              ? (_isBn ? 'যেখান থেকে' : 'Pickup')
                              : (_isBn ? 'আপনার অবস্থান' : 'Your location')),
                    ),
                    // A ride is the only kind with a destination — show where they're headed.
                    if (job.isRide)
                      Marker(
                        markerId: const MarkerId('dropoff'),
                        position: LatLng(job.dropoffLatitude!, job.dropoffLongitude!),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                        infoWindow: InfoWindow(
                          title: _isBn ? 'গন্তব্য' : 'Destination',
                          snippet: job.dropoffAddressSnapshot,
                        ),
                      ),
                  },
                  // Straight line, not a routed path — we have no directions API wired, and a
                  // fake road route would be misleading. It reads as "roughly this way".
                  // Prefer the real driving route Directions returned at quote time; the
                  // dashed straight line is only the fallback when routing was unavailable.
                  polylines: job.isRide
                      ? {
                          () {
                            final enc = job.rideDetail?.routePolyline;
                            final pts = (enc != null && enc.isNotEmpty)
                                ? decodePolyline(enc)
                                : const <List<double>>[];
                            final hasRoute = pts.length > 1;
                            return Polyline(
                              polylineId: const PolylineId('route'),
                              points: hasRoute
                                  ? pts.map((p) => LatLng(p[0], p[1])).toList()
                                  : [
                                      LatLng(job.pickupLatitude, job.pickupLongitude),
                                      LatLng(job.dropoffLatitude!, job.dropoffLongitude!),
                                    ],
                              color: colors.primary,
                              width: hasRoute ? 5 : 3,
                              patterns: hasRoute
                                  ? const []
                                  : [PatternItem.dash(18), PatternItem.gap(10)],
                            );
                          }(),
                        }
                      : const {},
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  liteModeEnabled: false,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.social_distance_rounded, color: colors.outline, size: 16),
              const SizedBox(width: 6),
              Text(
                _isBn
                    ? '~${_distanceKm(latest.latitude, latest.longitude, job.pickupLatitude, job.pickupLongitude).toStringAsFixed(1)} কিমি দূরে'
                    : '~${_distanceKm(latest.latitude, latest.longitude, job.pickupLatitude, job.pickupLongitude).toStringAsFixed(1)} km away',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ]),
          ],
        ],
      ),
    ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.1);
  }

  // Haversine — same formula dispatch-service uses server-side (see haversineKm in
  // dispatch.service.ts) so the customer's readout matches what actually drives matching.
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * (3.141592653589793 / 180);
    final dLon = (lon2 - lon1) * (3.141592653589793 / 180);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * 3.141592653589793 / 180) * cos(lat2 * 3.141592653589793 / 180) * (sin(dLon / 2) * sin(dLon / 2));
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Widget _buildProviderCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    final name = job.providerNameSnapshot ?? job.assignedProviderId ?? '?';
    final phone = job.providerPhoneSnapshot;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(gradient: AppGradients.primary(colors), shape: BoxShape.circle),
            child: Center(
              child: Text(
                name[0].toUpperCase(),
                style: TextStyle(color: colors.onPrimary, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_isBn ? 'নির্ধারিত সেবাদাতা' : 'Assigned Provider', style: TextStyle(color: colors.outline, fontSize: 11)),
              Text(name, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
              if (phone != null) Text(phone, style: TextStyle(color: colors.outline, fontSize: 12)),
            ]),
          ),
          if (job.serviceKind != 'lawyer')
            GestureDetector(
              onTap: _isOpeningChat ? null : _openJobChat,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle, border: Border.all(color: colors.outlineVariant)),
                child: _isOpeningChat
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary))
                    : Icon(Icons.chat_bubble_outline_rounded, color: colors.primary, size: 18),
              ),
            ),
          if (phone != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.phone_rounded, color: colors.primary, size: 22),
          ],
        ],
      ),
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.1);
  }

  // Shown between accept and the customer's explicit confirm — phone numbers are hidden on
  // both sides until this happens (chat is the only channel meanwhile).
  Widget _buildConfirmProviderCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isBn ? 'নম্বর দেখতে ও কল করতে আগে নিশ্চিত করুন — ততক্ষণ চ্যাটে কথা বলতে পারবেন' : 'Confirm to see the number and call — you can chat until then',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5, height: 1.4),
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
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.outlineVariant, width: 1.5),
                  ),
                  child: Text(_isBn ? 'চ্যাট করুন' : 'Chat', style: TextStyle(color: colors.onSurface, fontSize: 13.5, fontWeight: FontWeight.w600)),
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
                  decoration: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(12)),
                  child: _isConfirming
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isBn ? 'নিশ্চিত করুন' : 'Confirm', style: TextStyle(color: colors.onPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ],
      ),
    ).animate(delay: 120.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildJobDetails(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isBn ? 'অনুরোধের বিবরণ' : 'Request details', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _detail(_isBn ? 'সেবার ধরন' : 'Service type', job.serviceKind),
          _detail(_isBn ? 'জরুরি মাত্রা' : 'Urgency', job.urgencyLevel ?? 'normal'),
          if (job.description?.isNotEmpty ?? false) _detail(_isBn ? 'বিবরণ' : 'Description', job.description!),
          if (job.estimatedAmount != null) _detail(_isBn ? 'আনুমানিক খরচ' : 'Estimated cost', '৳ ${job.estimatedAmount!.toStringAsFixed(0)}'),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _detail(String label, String value) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: colors.outline, fontSize: 12))),
          Expanded(child: Text(value, style: TextStyle(color: colors.onSurface, fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildQuoteApprovalCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.request_quote_rounded, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              Text(_isBn ? 'সেবাদাতার কোট' : 'Provider\'s quote', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('৳ ${job.quotedAmount!.toStringAsFixed(0)}',
                style: TextStyle(color: colors.onSurface, fontSize: 30, fontWeight: FontWeight.w800)),
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
                            ? (_isBn ? 'প্ল্যাটফর্মের নির্ধারিত দাম ৳${rate.fixedPrice.toStringAsFixed(0)} — এই কোটটি তার চেয়ে অনেক বেশি' : 'Platform rate is ৳${rate.fixedPrice.toStringAsFixed(0)} — this quote is much higher')
                            : (_isBn ? 'প্ল্যাটফর্মের নির্ধারিত দাম: ৳${rate.fixedPrice.toStringAsFixed(0)}' : 'Platform rate: ৳${rate.fixedPrice.toStringAsFixed(0)}'),
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
          Center(
            child: Text(_isBn ? 'অনুমোদন না করলে শুধু ভিজিট ফি দিতে হবে, কাজ বাতিল হবে।' : 'If you don\'t approve, only the visiting fee applies and the job is cancelled.',
                textAlign: TextAlign.center, style: TextStyle(color: colors.outline, fontSize: 11)),
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
                    child: Text(_isBn ? 'প্রত্যাখ্যান' : 'Reject', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w700)),
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
                      gradient: AppGradients.primary(colors),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_isBn ? 'অনুমোদন করুন' : 'Approve', style: TextStyle(color: colors.onPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  // Lawyer consultations only ever surface their Meet link inside LawyerConsultationScreen's
  // local widget state, which is lost the moment the customer navigates away — leaving them
  // with no way to rejoin the call if they close the app or come back later. This screen
  // (reachable any time via Orders → this job) is the durable, jobId-backed home for it.

  /// The written opinion, which is the whole thing a consultation customer paid for.
  /// It has been stored on the job since the feature shipped and shown nowhere — after the
  /// Meet ended the app simply went quiet.
  Widget _buildOpinionCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    final summary = (job.opinionSummary ?? '').trim();
    if (summary.isEmpty) return const SizedBox.shrink();
    final advice = (job.opinionAdvice ?? '').trim();
    final steps = (job.opinionNextSteps ?? '').trim();

    Widget section(String labelBn, String labelEn, String value, IconData icon) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 15, color: colors.primary),
              const SizedBox(width: 6),
              Text(_isBn ? labelBn : labelEn,
                  style: TextStyle(
                      color: colors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 5),
            SelectableText(
              value,
              style: TextStyle(
                  color: colors.onSurface, fontSize: 14, height: 1.55),
            ),
          ]),
        );

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.gavel_rounded, color: colors.primary, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_isBn ? 'আপনার আইনি পরামর্শ' : 'Your legal opinion',
                style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800)),
          ),
          if (job.opinionDeliveredAt != null)
            Text(
              '${job.opinionDeliveredAt!.toLocal().day}/${job.opinionDeliveredAt!.toLocal().month}',
              style: TextStyle(color: colors.outline, fontSize: 11),
            ),
        ]),
        const SizedBox(height: 2),
        Text(
          _isBn
              ? 'আইনজীবী ${job.providerNameSnapshot ?? ''} এই পরামর্শ দিয়েছেন'.trim()
              : 'Written by ${job.providerNameSnapshot ?? 'your lawyer'}',
          style: TextStyle(color: colors.outline, fontSize: 11.5),
        ),
        section('সারসংক্ষেপ', 'Summary', summary, Icons.summarize_outlined),
        if (advice.isNotEmpty)
          section('পরামর্শ', 'Advice', advice, Icons.lightbulb_outline_rounded),
        if (steps.isNotEmpty)
          section('পরবর্তী পদক্ষেপ', 'Next steps', steps, Icons.checklist_rounded),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                final text = [
                  _isBn ? 'আইনি পরামর্শ' : 'Legal opinion',
                  '',
                  (_isBn ? 'সারসংক্ষেপ: ' : 'Summary: ') + summary,
                  if (advice.isNotEmpty) (_isBn ? 'পরামর্শ: ' : 'Advice: ') + advice,
                  if (steps.isNotEmpty) (_isBn ? 'পরবর্তী পদক্ষেপ: ' : 'Next steps: ') + steps,
                ].join('\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_isBn ? 'পরামর্শ কপি হয়েছে' : 'Opinion copied',
                      style: const TextStyle(color: Colors.white)),
                  backgroundColor: const Color(0xFF10B981),
                  behavior: SnackBarBehavior.floating,
                ));
              },
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.outlineVariant)),
              icon: Icon(Icons.copy_rounded, size: 15, color: colors.onSurfaceVariant),
              label: Text(_isBn ? 'কপি করুন' : 'Copy',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildMeetLinkCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    final link = job.meetLink!;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.videocam_rounded, color: colors.primary, size: 20),
          const SizedBox(width: 8),
          Text(_isBn ? 'ভিডিও কলের লিংক তৈরি হয়েছে' : 'Video call link created',
              style: TextStyle(color: colors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        SelectableText(link, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 10),
        GlassButton(
          label: _isBn ? 'মিটিং এ যোগ দিন' : 'Join meeting',
          icon: Icons.videocam_rounded,
          onPressed: () => openMeetLink(context, link),
        ),
        const SizedBox(height: 8),
        GlassButton(
          label: _isBn ? 'লিংক কপি করুন' : 'Copy link',
          icon: Icons.copy_rounded,
          isOutlined: true,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_isBn ? 'লিংক কপি হয়েছে' : 'Link copied', style: const TextStyle(color: Colors.white)),
              backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating,
            ));
          },
        ),
      ]),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  /// Ride summary — route, vehicle and fare, shown from the moment the request is posted so
  /// the customer can see what they asked for while it's still "searching".
  Widget _buildRideSummaryCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    final vehicle = job.rideDetail?.vehicleType;
    final vehicleLabel = vehicle == null
        ? null
        : (_isBn ? kRideVehicleLabelsBn[vehicle] : kRideVehicleLabelsEn[vehicle]) ?? vehicle;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _rideRow(Icons.trip_origin_rounded, colors.primary,
            job.pickupAddressSnapshot ?? (_isBn ? 'আপনার অবস্থান' : 'Your location')),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
          child: Container(width: 2, height: 14, color: colors.outlineVariant),
        ),
        _rideRow(Icons.flag_rounded, StatusColors.amber,
            job.dropoffAddressSnapshot ?? (_isBn ? 'গন্তব্য' : 'Destination')),
        const SizedBox(height: 12),
        Divider(height: 1, color: colors.outlineVariant),
        const SizedBox(height: 12),
        Row(children: [
          if (vehicleLabel != null) ...[
            Icon(Icons.two_wheeler_rounded, size: 16, color: colors.outline),
            const SizedBox(width: 5),
            Text(vehicleLabel,
                style: TextStyle(
                    color: colors.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 14),
          ],
          if (job.distanceKm != null) ...[
            Icon(Icons.social_distance_rounded, size: 16, color: colors.outline),
            const SizedBox(width: 5),
            Text('${job.distanceKm!.toStringAsFixed(1)} ${_isBn ? 'কিমি' : 'km'}',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5)),
          ],
          if (job.rideDetail?.durationMinutes != null) ...[
            const SizedBox(width: 14),
            Icon(Icons.schedule_rounded, size: 16, color: colors.outline),
            const SizedBox(width: 5),
            Text('~${job.rideDetail!.durationMinutes} ${_isBn ? 'মিনিট' : 'min'}',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5)),
          ],
          const Spacer(),
          if (job.estimatedAmount != null)
            Text('৳${job.estimatedAmount!.round()}',
                style: TextStyle(
                    color: colors.primary, fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        if (job.rideDetail?.hasSurge == true) ...[
          const SizedBox(height: 6),
          Text(
            _isBn
                ? 'এখন চাহিদা বেশি — ভাড়া কিছুটা বেশি'
                : 'High demand right now — fare is slightly higher',
            style: const TextStyle(color: StatusColors.amber, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ]),
    ).animate(delay: 80.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _rideRow(IconData icon, Color color, String text) {
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(color: colors.onSurface, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
      ]);
  }

  // Cash-on-completion stays the default for every on-demand service — this is an opt-in
  // alternative. Rides are included because paying a stranger driver in cash for a fare the
  // app already computed is exactly the case online payment exists for.
  static const _onlinePaymentKinds = {'technician', 'commute'};
  bool _showOnlinePaymentCard(JobModel job) =>
      _onlinePaymentKinds.contains(job.serviceKind) &&
      job.assignedProviderId != null &&
      !['completed', 'cancelled', 'expired'].contains(job.status) &&
      !job.awaitingQuoteApproval &&
      job.depositStatus != 'paid';

  Widget _buildOnlinePaymentCard(JobModel job) {
    final colors = Theme.of(context).colorScheme;
    final alreadyOptedIn = job.depositStatus == 'pending';
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.payments_rounded, color: colors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alreadyOptedIn
                  ? (_isBn ? 'অনলাইন পেমেন্ট বাকি আছে' : 'Online payment is pending')
                  : (_isBn ? 'ক্যাশের বদলে অনলাইনে পরিশোধ করুন' : 'Pay online instead of cash'),
              style: TextStyle(color: colors.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          // A ride booked with paymentMethod:online arrives here already opted in, so the
          // "skip this and pay cash" line would be telling the customer the opposite of what
          // they already chose.
          alreadyOptedIn
              ? (_isBn
                  ? 'আপনি অনলাইনে পরিশোধ বেছে নিয়েছেন — বিকাশ / নগদ / কার্ডে সম্পন্ন করুন।'
                  : 'You chose to pay online — finish it with bKash / Nagad / card.')
              : (_isBn
                  ? 'না করলে কাজ শেষে যথারীতি সরাসরি ক্যাশ দিতে হবে।'
                  : 'If you skip this, pay the provider cash directly as usual when the job is done.'),
          style: TextStyle(color: colors.outline, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _isPayingOnline ? null : _payOnline,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(12)),
            child: _isPayingOnline
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    alreadyOptedIn
                        ? (_isBn ? 'পেমেন্ট সম্পন্ন করুন' : 'Complete payment')
                        : (_isBn ? 'অনলাইনে পরিশোধ করুন' : 'Pay online'),
                    style: TextStyle(color: colors.onPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ]),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Future<void> _payOnline() async {
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
    setState(() => _isPayingOnline = true);
    try {
      // Idempotent to call again if the job was already opted in (e.g. app was
      // backgrounded mid-payment last time) — optInOnlinePayment only blocks once paid.
      double amount = _job?.depositAmount ?? 0;
      if (_job?.depositStatus != 'pending') {
        final optIn = await DispatchService.instance.optInOnlinePayment(widget.jobId);
        amount = (optIn['amount'] as num?)?.toDouble() ?? amount;
      }
      final transaction = await DispatchService.instance.initiateDepositPayment(widget.jobId);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'পেমেন্ট শুরু করা যায়নি — আবার চেষ্টা করুন' : 'Could not start the payment — please try again', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'সেবার মূল্য' : 'Service Payment',
          titleEn: 'Service Payment',
          amount: amount,
          checkStatus: () async {
            try {
              await DispatchService.instance.confirmDepositPayment(widget.jobId);
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
          applyCoupon: (code) async {
            final t = await DispatchService.instance.initiateDepositPayment(widget.jobId, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? amount};
          },
        ),
      ));
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.mapError(e).localized(_isBn), style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isPayingOnline = false);
    }
  }

  Future<void> _respondQuote(bool approved) async {
    final colors = Theme.of(context).colorScheme;
    if (!approved) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(_isBn ? 'কোট প্রত্যাখ্যান?' : 'Reject quote?', style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text(_isBn ? 'কাজটি বাতিল হয়ে যাবে এবং শুধু ভিজিট ফি প্রযোজ্য হবে।' : 'The job will be cancelled and only the visiting fee will apply.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'না' : 'No', style: TextStyle(color: colors.outline))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(_isBn ? 'হ্যাঁ, প্রত্যাখ্যান' : 'Yes, reject', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
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
          content: Text(
              approved
                  ? (_isBn ? 'কোট অনুমোদিত — কাজ শুরু হবে' : 'Quote approved — job will begin')
                  : (_isBn ? 'কোট প্রত্যাখ্যাত — কাজ বাতিল' : 'Quote rejected — job cancelled'),
              style: const TextStyle(color: Colors.white)),
          backgroundColor: approved ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'কোট প্রক্রিয়া করতে সমস্যা হয়েছে' : 'Could not process the quote', style: const TextStyle(color: Colors.white)),
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
        child: Center(child: Text(_isBn ? 'অনুরোধ বাতিল করুন' : 'Cancel request', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w600))),
      ),
    ).animate(delay: 300.ms).fadeIn();
  }
}
