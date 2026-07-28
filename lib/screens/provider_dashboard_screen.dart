import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../core/network/api_client.dart';
import '../models/dispatch_model.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../services/finance_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'active_job_screen.dart';
import 'commission_screen.dart';
import 'match_requests_inbox_screen.dart';
import 'nid_screen.dart';
import 'portfolio_screen.dart';
import 'wallet_screen.dart';

class ProviderDashboardScreen extends StatefulWidget {
  const ProviderDashboardScreen({super.key});

  @override
  State<ProviderDashboardScreen> createState() => _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  int _tab = 0;
  bool _isOnline = false;
  bool _togglingOnline = false;
  String? _userId;
  String? _providerName;

  // Dashboard
  JobModel? _activeJob;
  bool _showingIncomingModal = false;
  Timer? _pollTimer;

  // Earnings
  WalletModel? _wallet;
  List<TransactionModel> _transactions = [];
  bool _loadingEarnings = false;

  // History
  List<JobModel> _jobHistory = [];
  bool _loadingHistory = false;

  // My applied services
  List<Map<String, dynamic>> _myServices = [];
  bool _loadingMyServices = false;

  // Dispatch standing (red cards / temp-ban / unpaid dues)
  ProviderStanding? _standing;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    _providerName = await ApiClient.getFullName();
    if (mounted) setState(() {});
    _loadEarnings();
    _loadHistory();
    _loadMyServices();
    _loadStanding();
    _syncOnlineFromBackend();
  }

  // _isOnline is widget state, and this widget is recreated on every customer↔provider mode
  // switch — without this sync the dashboard showed "অফলাইন" every time it reopened even
  // though the backend session was still live (the online-status screen, which does read
  // /dispatch/sessions/me, kept correctly showing অনলাইন — the two contradicted each other).
  Future<void> _syncOnlineFromBackend() async {
    try {
      final s = await DispatchService.instance.getMySession();
      if (s.isActive && mounted && !_isOnline) {
        setState(() => _isOnline = true);
        _pollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _poll());
      }
    } catch (_) {
      // 404 = no session ever started — genuinely offline, nothing to do.
    }
  }

  Future<void> _loadStanding() async {
    try {
      final s = await DispatchService.instance.getMyStanding();
      if (mounted) setState(() => _standing = s);
    } catch (_) {
      // Standing is a non-critical overlay — ignore load errors silently.
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleOnline() async {
    if (_userId == null) {
      _showError('ব্যবহারকারীর তথ্য লোড হয়নি');
      return;
    }
    setState(() => _togglingOnline = true);
    try {
      if (_isOnline) {
        await DispatchService.instance.endSession(providerId: _userId!);
        _pollTimer?.cancel();
        _pollTimer = null;
        if (mounted) setState(() { _isOnline = false; _activeJob = null; });
      } else {
        // Load provider snapshot FIRST: it decides whether GPS is even required.
        // Consultation broadcasts only reach lawyers whose live session carries
        // role/areas/services + verified=true, and technician broadcasts only
        // reach techs whose session carries the ticked specialization codes.
        // Going online without these means the provider never receives offers.
        final snap = await _loadProviderMatchingSnapshot();
        final legal = snap?.legal;
        final isLawyer = legal != null;
        final specializations = snap?.specializations;

        // A lawyer consults remotely, so GPS must never block them from going online
        // (a denied browser prompt used to abort the whole toggle). Physical providers
        // still need a real position — they are matched by distance.
        Position? pos;
        try {
          if (!kIsWeb) {
            final serviceEnabled = await Geolocator.isLocationServiceEnabled();
            if (!serviceEnabled && !isLawyer) {
              _showError('লোকেশন সার্ভিস বন্ধ আছে');
              return;
            }
          }
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          final denied = permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever;
          if (denied) {
            if (!isLawyer) {
              _showError('লোকেশন অনুমতি দেওয়া হয়নি');
              return;
            }
          } else {
            // Without a timeLimit getCurrentPosition can hang forever on some
            // devices, leaving the toggle stuck on its spinner.
            try {
              pos = await Geolocator.getCurrentPosition(
                timeLimit: const Duration(seconds: 15),
              );
            } catch (_) {
              pos = await Geolocator.getLastKnownPosition();
            }
          }
        } catch (e) {
          debugPrint('[Provider] location unavailable: $e');
          if (!isLawyer) {
            _showError('লোকেশন পাওয়া যায়নি');
            return;
          }
        }
        if (pos == null && !isLawyer) {
          // Physical providers are matched by distance — a session without
          // coordinates would never receive nearby jobs.
          _showError('লোকেশন পাওয়া যায়নি — GPS চালু করে আবার চেষ্টা করুন');
          return;
        }
        debugPrint('[Provider] GPS: ${pos?.latitude}, ${pos?.longitude} (lawyer=$isLawyer)');

        final serviceKinds = _myServices
            .where((s) => s['status'] == 'approved')
            .map((s) => s['serviceTypeId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        if (isLawyer && !serviceKinds.contains('lawyer')) {
          serviceKinds.add('lawyer');
        }
        if (serviceKinds.isEmpty) serviceKinds.add('technician');

        await DispatchService.instance.startSession(
          providerId: _userId!,
          serviceKinds: serviceKinds,
          currentLatitude: pos?.latitude,
          currentLongitude: pos?.longitude,
          providerNameSnapshot: _providerName,
          legalAreas: legal?.areas,
          legalServices: legal?.services,
          legalRole: legal?.role,
          verifiedSnapshot: legal?.verified,
          specializations: specializations,
        );
        if (mounted) {
          setState(() => _isOnline = true);
          _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
        }
      }
    } catch (e) {
      debugPrint('[Provider] toggleOnline error: $e');
      _showError('অনলাইন হওয়া যায়নি: $e');
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  /// Combined matching snapshot for the live session, from /auth/me.providerProfile.
  /// Legal data → null for providers without a legal profile; specializations →
  /// null when the technician hasn't ticked any (still allowed online, but
  /// won't receive specialized jobs). Loaded once so we don't hit /auth/me twice.
  Future<_ProviderMatchingSnapshot?> _loadProviderMatchingSnapshot() async {
    try {
      final me = await AuthService.instance.getMeRaw();
      final pp = me['providerProfile'];
      if (pp is! Map) return null;

      // Legal side (lawyer / legal assistant)
      final role = pp['legalRole'] as String?;
      final services = (pp['legalServices'] as List?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      final areas =
          (pp['legalAreas'] as List?)?.whereType<String>().toList() ??
              const <String>[];
      _LegalSnapshot? legal;
      if (role != null || services.isNotEmpty || areas.isNotEmpty) {
        legal = _LegalSnapshot(
          areas: areas.isNotEmpty ? areas : null,
          services: services.isNotEmpty ? services : null,
          role: role,
          verified: pp['verificationStatus'] == 'verified',
        );
      }

      // Technician specializations — codes only; the broadcast filters by these.
      final specs = (pp['specializations'] as List?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];

      return _ProviderMatchingSnapshot(
        legal: legal,
        specializations: specs.isNotEmpty ? specs : null,
      );
    } catch (e) {
      debugPrint('[Provider] matching snapshot load failed: $e');
      return null;
    }
  }

  Future<void> _poll() async {
    if (_userId == null || !mounted) return;
    try {
      final jobs = await DispatchService.instance.listJobs(assignedProviderId: _userId);
      if (!mounted) return;

      final incoming = jobs.where((j) => j.status == 'assigned').toList();
      // Lawyer consultations are remote (Meet link) — they never enter the
      // physical arrival/OTP active-job flow.
      final active = jobs.where((j) =>
          j.serviceKind != 'lawyer' &&
          (j.status == 'accepted' || j.status == 'arriving' || j.status == 'in_progress')).toList();

      if (active.isNotEmpty) {
        final latestActive = active.first;
        if (_activeJob == null || _activeJob!.id != latestActive.id || _activeJob!.status != latestActive.status) {
          setState(() => _activeJob = latestActive);
        }
      }

      if (incoming.isNotEmpty && !_showingIncomingModal) {
        final incomingJob = incoming.first;
        try {
          final assignments = await DispatchService.instance.listAssignments(incomingJob.id);
          final pending = assignments.where((a) => a.status == 'pending').toList();
          if (pending.isNotEmpty && mounted) {
            _showingIncomingModal = true;
            _showIncomingJobModal(incomingJob, pending.first.id);
          }
        } catch (_) {}
      }

      // On-demand broadcast offers: jobs still 'searching' where I have a pending assignment.
      // (Directly-assigned jobs above stay 'assigned'; these are the geo-broadcast offers.)
      if (_activeJob == null && !_showingIncomingModal) {
        try {
          final offers = await DispatchService.instance.getMyOffers();
          if (offers.isNotEmpty && mounted && !_showingIncomingModal && _activeJob == null) {
            _showingIncomingModal = true;
            _showIncomingJobModal(offers.first.job, offers.first.assignmentId);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _showIncomingJobModal(JobModel job, String assignmentId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _IncomingJobDialog(
        job: job,
        onAccept: () async {
          Navigator.pop(ctx);
          _showingIncomingModal = false;
          try {
            final r = await DispatchService.instance.respondToAssignment(
              assignmentId,
              // Backend AssignmentResponse enum: anything != 'accepted' falls
              // into the reject branch, so the exact value matters.
              response: 'accepted',
              jobId: job.id,
            );
            if (!mounted) return;
            if (job.serviceKind == 'lawyer') {
              // Remote consultation — no arrival/OTP flow. First to accept
              // wins and gets the Meet link right away.
              final meetLink = r['meetLink'] as String?;
              if (meetLink != null && meetLink.isNotEmpty) {
                _showMeetLinkDialog(job, meetLink);
              } else {
                // Non-video consultation (phone/chat) — no Meet link expected.
                _showInfo('পরামর্শ গৃহীত হয়েছে');
              }
            } else {
              setState(() => _activeJob = job);
            }
          } catch (_) {
            _showError('গ্রহণ করতে সমস্যা হয়েছে');
          }
        },
        onReject: () async {
          Navigator.pop(ctx);
          _showingIncomingModal = false;
          try {
            await DispatchService.instance.respondToAssignment(
              assignmentId,
              response: 'rejected',
              jobId: job.id,
            );
          } catch (_) {}
        },
      ),
    );
  }

  Future<void> _loadEarnings() async {
    if (_userId == null) return;
    if (mounted) setState(() => _loadingEarnings = true);
    // Call independently so a 500 on one doesn't kill the other.
    try {
      final w = await FinanceService.instance.getWallet();
      if (mounted) setState(() => _wallet = w);
    } catch (_) {}
    try {
      final t = await FinanceService.instance.listTransactions(providerId: _userId);
      if (mounted) setState(() => _transactions = t);
    } catch (_) {}
    if (mounted) setState(() => _loadingEarnings = false);
  }

  Future<void> _loadMyServices() async {
    if (mounted) setState(() => _loadingMyServices = true);
    try {
      final list = await OnboardingService.instance.getMyServices();
      if (mounted) setState(() => _myServices = list);
    } catch (_) {}
    if (mounted) setState(() => _loadingMyServices = false);
  }

  Future<void> _loadHistory() async {
    if (_userId == null) return;
    setState(() => _loadingHistory = true);
    try {
      final jobs = await DispatchService.instance.listJobs(assignedProviderId: _userId);
      if (mounted) setState(() => _jobHistory = jobs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  /// Won consultation — hand the lawyer the Google Meet link. The app has no
  /// url_launcher, so the link is copied for opening in the browser.
  void _showMeetLinkDialog(JobModel job, String meetLink) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.videocam_rounded, color: Color(0xFF10B981), size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text('পরামর্শ গৃহীত হয়েছে',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${job.customerNameSnapshot ?? 'গ্রাহক'} ভিডিও কলে যুক্ত হবেন। '
              'লিংকটি কপি করে ব্রাউজারে Meet খুলুন।',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.deepBlue.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.deepBlue.withOpacity(0.35)),
              ),
              child: SelectableText(
                meetLink,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: meetLink));
              _showInfo('লিংক কপি হয়েছে');
            },
            icon: const Icon(Icons.copy_rounded, color: AppColors.deepBlue, size: 18),
            label: const Text('কপি করুন',
                style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ঠিক আছে', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const SizedBox(height: 10),
        _buildTabBar(),
        const SizedBox(height: 10),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Text(
            'প্রোভাইডার',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _togglingOnline ? null : _toggleOnline,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: _isOnline ? AppColors.blueGradient : null,
                color: _isOnline ? null : AppColors.glassWhite,
                borderRadius: BorderRadius.circular(20),
                border: _isOnline ? null : Border.all(color: AppColors.glassBorder),
              ),
              child: _togglingOnline
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isOnline ? const Color(0xFF4ADE80) : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _isOnline ? 'অনলাইন' : 'অফলাইন',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isOnline ? Colors.white : AppColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    const tabs = ['ড্যাশবোর্ড', 'আয়', 'ইতিহাস'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isSelected = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(right: i < tabs.length - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.blueGradient : null,
                  color: isSelected ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? null : Border.all(color: AppColors.glassBorder),
                ),
                child: Center(
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildEarningsTab();
      case 2:
        return _buildHistoryTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // Warns the provider about red cards / temp-ban / unpaid dues that block new jobs.
  Widget _buildStandingBanner() {
    final s = _standing;
    if (s == null || s.isClean) return const SizedBox.shrink();

    IconData icon;
    Color color;
    String title;
    String body;

    if (s.isBanned || s.tempBanned) {
      icon = Icons.block_rounded;
      color = const Color(0xFFEF4444);
      final until = s.bannedUntil != null ? _fmtDate(s.bannedUntil!) : null;
      title = s.isBanned ? 'অ্যাকাউন্ট বন্ধ' : 'সাময়িকভাবে বন্ধ';
      body = s.isBanned
          ? 'আপনার অ্যাকাউন্ট বন্ধ আছে। সহায়তার জন্য যোগাযোগ করুন।'
          : '৩টি রেড কার্ড হওয়ায় ${until ?? '৭ দিন'} পর্যন্ত নতুন কাজ পাবেন না।';
    } else if (s.duesBlockingNewJobs) {
      icon = Icons.account_balance_wallet_rounded;
      color = const Color(0xFFEF4444);
      title = 'দেনা বাকি';
      body = '৳${s.unpaidDuesTotal.toStringAsFixed(0)} কমিশন দেনা বাকি — '
          'মেটানোর আগে নতুন কাজ পাবেন না।';
    } else {
      icon = Icons.warning_amber_rounded;
      color = const Color(0xFFF59E0B);
      title = '${s.redFlags}টি রেড কার্ড';
      body = 'আর ${s.cardsUntilBan}টি কার্ড হলে ৭ দিনের জন্য কাজ বন্ধ হবে। '
          'কাজ accept করে বাতিল করা এড়িয়ে চলুন।';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static const _levelLabelsBn = {
    'BRONZE': 'ব্রোঞ্জ', 'SILVER': 'সিলভার', 'GOLD': 'গোল্ড', 'PLATINUM': 'প্লাটিনাম',
  };
  static const _levelColors = {
    'BRONZE': Color(0xFFB08D57), 'SILVER': Color(0xFF9CA3AF), 'GOLD': Color(0xFFF59E0B), 'PLATINUM': Color(0xFF8B5CF6),
  };

  // Name + rating + level in one glance — this data (dispatchAvgRating, level, totalCompleted)
  // was already coming back from GET /dispatch/me/standing but nothing on this screen showed it.
  Widget _buildProfileStrip() {
    final s = _standing;
    final levelColor = _levelColors[s?.level] ?? AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              (_providerName?.isNotEmpty ?? false) ? _providerName![0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_providerName ?? 'প্রোভাইডার',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                    const SizedBox(width: 3),
                    Text(
                      s?.dispatchAvgRating != null ? s!.dispatchAvgRating!.toStringAsFixed(2) : '—',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    if (s != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: levelColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: levelColor.withOpacity(0.4)),
                        ),
                        child: Text(_levelLabelsBn[s.level] ?? s.level,
                            style: TextStyle(color: levelColor, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Text('মোট ${s.totalCompleted}টি কাজ',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The wallet has no "today only" figure — computed here from the same transaction list
  // the earnings tab already loads, so no extra request.
  double get _todayEarnings {
    final now = DateTime.now();
    return _transactions
        .where((t) => t.isCredit && t.createdAt.year == now.year && t.createdAt.month == now.month && t.createdAt.day == now.day)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  Widget _buildTodayEarningsCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: AppColors.blueGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('আজকের আয়', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('৳ ${_todayEarnings.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (_standing != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('এই সপ্তাহে', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('${_standing!.weeklyCompleted}টি কাজ',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildProfileStrip(),
          _buildTodayEarningsCard(),
          _buildStandingBanner(),
          if (!_isOnline)
            GestureDetector(
              onTap: _togglingOnline ? null : _toggleOnline,
              child: GlassCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: AppColors.glassWhite, shape: BoxShape.circle, border: Border.all(color: AppColors.glassBorder)),
                      child: _togglingOnline
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.deepBlue),
                            )
                          : const Icon(Icons.power_settings_new_rounded, color: AppColors.textMuted, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text(_togglingOnline ? 'সংযোগ হচ্ছে…' : 'অফলাইনে আছেন',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('কাজ পেতে এখানে ট্যাপ করুন', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_activeJob != null)
            _buildActiveJobCard()
          else ...[
            _buildServiceKindBadge(),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
                      child: const Icon(Icons.search_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('কাজের অপেক্ষায়...', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('নতুন কাজ আসলে আপনাকে জানানো হবে', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildQuickActions(),
          if (_loadingMyServices || _myServices.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildMyServicesSection(),
          ],
        ],
      ),
    );
  }

  // Portfolio/wall is only meaningful for photographer/cinematographer — showing it to every
  // provider (e.g. a technician) sent them into a screen that could never actually save anything
  // (no photography/cinema profile to attach images to).
  bool get _isVisualProvider => _myServices.any((s) {
        final id = (s['serviceTypeId'] as String? ?? '');
        return id.contains('photograph') || id.contains('cinema');
      });

  Widget _buildQuickActions() {
    void nav(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    // Subtitle is a live number pulled from state already loaded elsewhere on this screen
    // (wallet/standing) — no extra network calls, just surfacing data that used to be
    // invisible until you tapped in.
    final walletSub = _wallet != null ? '৳${_wallet!.balance.toStringAsFixed(0)}' : null;
    final actions = [
      (Icons.account_balance_wallet_outlined, 'ওয়ালেট', walletSub, const Color(0xFF3B82F6), () => nav(const WalletScreen())),
      (Icons.percent_rounded, 'কমিশন', null, const Color(0xFFF59E0B), () => nav(const CommissionScreen())),
      (Icons.credit_card_outlined, 'NID', null, const Color(0xFF8B5CF6), () => nav(const NidScreen())),
      if (_isVisualProvider)
        (Icons.photo_library_outlined, 'পোর্টফোলিও', null, const Color(0xFFEF4444), () => nav(const PortfolioScreen())),
      (Icons.inbox_rounded, 'ম্যাচ অনুরোধ', null, const Color(0xFF10B981), () => nav(const MatchRequestsInboxScreen())),
    ];
    return Row(
      children: actions.map((a) {
        final (icon, label, subtitle, color, onTap) = a;
        return Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: color.withOpacity(0.75), fontSize: 10, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMyServicesSection() {
    if (_loadingMyServices) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text('আমার সেবাসমূহ', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        ..._myServices.map((svc) {
          final name = svc['serviceType']?['name'] as String? ?? svc['serviceTypeId'] as String? ?? '—';
          final status = svc['status'] as String? ?? 'draft';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  _statusChip(status),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _statusChip(String status) {
    final (label, bg, fg) = switch (status) {
      'approved' => ('অনুমোদিত', const Color(0x2010B981), const Color(0xFF10B981)),
      'rejected' => ('প্রত্যাখ্যাত', const Color(0x20EF4444), const Color(0xFFEF4444)),
      'needs_changes' => ('পরিবর্তন দরকার', const Color(0x20F59E0B), const Color(0xFFF59E0B)),
      'submitted' || 'under_review' => ('পর্যালোচনায়', const Color(0x20F97316), const Color(0xFFF97316)),
      _ => ('Draft', const Color(0x20888888), AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildServiceKindBadge() {
    if (_myServices.isEmpty) return const SizedBox.shrink();

    final approved = _myServices.where((s) => s['status'] == 'approved').toList();
    final display = approved.isNotEmpty ? approved : _myServices;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'আপনার সেবাসমূহ',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          ...display.map((svc) {
            final name = svc['serviceType']?['name'] as String?
                ?? svc['serviceTypeId'] as String?
                ?? '—';
            final icon = svc['serviceType']?['icon'] as String? ?? '🔧';
            final status = svc['status'] as String? ?? 'draft';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  _statusChip(status),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActiveJobCard() {
    final job = _activeJob!;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text('সক্রিয় কাজ', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          if (job.eventDate != null) ...[
            const SizedBox(height: 12),
            _EventDateBanner(job: job),
          ],
          const SizedBox(height: 12),
          Text(job.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (job.customerNameSnapshot != null)
            Text('গ্রাহক: ${job.customerNameSnapshot}', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 4),
          Text('অবস্থা: ${job.statusBn()}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          GlassButton(
            label: 'কাজ পরিচালনা করুন',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ActiveJobScreen(
                job: job,
                onJobCompleted: () {
                  if (mounted) setState(() => _activeJob = null);
                },
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsTab() {
    if (_loadingEarnings) {
      return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    return RefreshIndicator(
      onRefresh: _loadEarnings,
      color: AppColors.deepBlue,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text('মোট ব্যালেন্স', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 8),
                Text(
                  '৳ ${_wallet?.balance.toStringAsFixed(0) ?? '0'}',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 36, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_wallet?.currency ?? 'BDT', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('লেনদেনের ইতিহাস', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          if (_transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('কোনো লেনদেন নেই', style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ..._transactions.map(_buildTransactionTile),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(TransactionModel t) {
    final isCredit = t.isCredit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCredit ? const Color(0x2010B981) : const Color(0x20EF4444),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.description ?? (isCredit ? 'জমা' : 'উত্তোলন'),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              '${isCredit ? '+' : '-'}৳ ${t.amount.toStringAsFixed(0)}',
              style: TextStyle(
                color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: AppColors.deepBlue,
      child: _jobHistory.isEmpty
          ? const Center(
              child: Text('কোনো কাজের ইতিহাস নেই', style: TextStyle(color: AppColors.textMuted)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _jobHistory.length,
              itemBuilder: (_, i) => _buildHistoryTile(_jobHistory[i]),
            ),
    );
  }

  Widget _buildHistoryTile(JobModel job) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.title,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(job.statusBn(), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ),
              ],
            ),
            if (job.customerNameSnapshot != null) ...[
              const SizedBox(height: 4),
              Text('গ্রাহক: ${job.customerNameSnapshot}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
            if (job.finalAmount != null || job.estimatedAmount != null) ...[
              const SizedBox(height: 4),
              Text(
                'মূল্য: ৳ ${(job.finalAmount ?? job.estimatedAmount)!.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegalSnapshot {
  final List<String>? areas;
  final List<String>? services;
  final String? role;
  final bool verified;
  const _LegalSnapshot({
    required this.areas,
    required this.services,
    required this.role,
    required this.verified,
  });
}

class _ProviderMatchingSnapshot {
  final _LegalSnapshot? legal;
  final List<String>? specializations;
  const _ProviderMatchingSnapshot({
    required this.legal,
    required this.specializations,
  });
}

class _IncomingJobDialog extends StatelessWidget {
  final JobModel job;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingJobDialog({
    required this.job,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
                child: const Icon(Icons.work_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'নতুন কাজের অনুরোধ!',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            // Advance-booking jobs — surface the event date BEFORE accept so
            // the provider doesn't book a slot they can't make.
            if (job.eventDate != null) ...[
              const SizedBox(height: 14),
              _EventDateBanner(job: job),
            ],
            const SizedBox(height: 12),
            Text(
              job.title,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (job.customerNameSnapshot != null) ...[
              const SizedBox(height: 6),
              Text(
                'গ্রাহক: ${job.customerNameSnapshot}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
            if (job.pickupAddressSnapshot != null) ...[
              const SizedBox(height: 4),
              Text(
                job.exactLocationHidden
                    ? 'আনুমানিক এলাকা: ${job.pickupAddressSnapshot}'
                    : job.pickupAddressSnapshot!,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              if (job.exactLocationHidden) ...[
                const SizedBox(height: 4),
                const Text(
                  'গ্রহণ করলে সম্পূর্ণ ঠিকানা ও ফোন দেখা যাবে',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            if (job.estimatedAmount != null) ...[
              const SizedBox(height: 12),
              Text(
                '৳ ${job.estimatedAmount!.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.deepBlue, fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onReject,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'প্রত্যাখ্যান',
                          style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: onAccept,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: AppColors.blueGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'গ্রহণ করুন',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Advance-booking event date banner ─────────────────────────────
// Renders nothing for immediate jobs (eventDate == null). Used inside the
// incoming-offer modal (pre-accept — critical: the provider must see the
// date before committing) and inside the active-job card (post-accept —
// so the date stays visible while the provider is preparing).

class _EventDateBanner extends StatelessWidget {
  final JobModel job;
  const _EventDateBanner({required this.job});

  static const _bnMonthsFull = [
    'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
  ];

  static String _bnDigits(int n) =>
      n.toString().split('').map((d) => '০১২৩৪৫৬৭৮৯'[int.parse(d)]).join();

  static String _bnPad2(int n) {
    final s = _bnDigits(n);
    return s.length == 1 ? '০$s' : s;
  }

  @override
  Widget build(BuildContext context) {
    final d = job.eventDate;
    if (d == null) return const SizedBox.shrink();
    final local = d.toLocal();
    final day = _bnDigits(local.day);
    final month = _bnMonthsFull[local.month - 1];
    final year = _bnDigits(local.year);
    final hh = _bnPad2(local.hour);
    final mm = _bnPad2(local.minute);
    final duration = job.estimatedDurationHours;
    final durationLabel = duration != null ? ' (${_bnDigits(duration)} ঘণ্টা)' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.deepBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📅', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'অনুষ্ঠানের তারিখ',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$day $month, $year, $hh:$mm$durationLabel',
                  style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
