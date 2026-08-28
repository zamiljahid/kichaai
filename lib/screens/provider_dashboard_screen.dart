import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_exception.dart';
import '../core/utils/app_strings.dart';
import '../core/utils/meet_link.dart';
import '../models/dispatch_model.dart';
import '../services/alarm_notification_service.dart';
import '../services/auth_service.dart';
import '../services/commute_service.dart';
import '../services/dispatch_service.dart';
import '../services/finance_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/provider_completeness_gate.dart';
import 'active_job_screen.dart';
import 'caregiver_profile_screen.dart';
import 'cinematographer_profile_screen.dart';
import 'commission_screen.dart';
import 'commute_screen.dart';
import 'cook_provider_screen.dart';
import 'driver_mode_screen.dart';
import 'household_help_profile_screen.dart';
import 'makeup_artist_profile_screen.dart';
import 'micro_learning_profile_screen.dart';
import 'course_authoring_screen.dart';
import '../models/micro_learning_model.dart';
import '../services/micro_learning_service.dart';
import 'pet_care_profile_screen.dart';
import 'photographer_profile_screen.dart';
import 'quick_help_profile_screen.dart';
import 'skill_share_profile_screen.dart';
import 'technician_onboarding_screen.dart';
import 'gender_screen.dart';
import 'laundry_hub_screen.dart';
import 'match_requests_inbox_screen.dart';
import 'nid_screen.dart';
import 'portfolio_screen.dart';
import 'provider_onboarding_screen.dart';
import 'tutor_profile_screen.dart';
import 'wallet_screen.dart';

class ProviderDashboardScreen extends StatefulWidget {
  const ProviderDashboardScreen({super.key});

  @override
  State<ProviderDashboardScreen> createState() =>
      _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  int _tab = 0;
  bool _isOnline = false;
  bool _togglingOnline = false;
  // True until _syncOnlineFromBackend's first check resolves — without this, every remount
  // (e.g. switching গ্রাহক↔প্রোভাইডার) briefly rendered a confident "অফলাইনে আছেন" for whatever
  // this async call takes to return, before flipping back to online. Looked like the session
  // kept dropping on navigation when it never actually did.
  bool _checkingOnlineStatus = true;
  String? _userId;
  String? _providerName;
  String? _profilePhotoUrl;

  // Dashboard
  JobModel? _activeJob;
  bool _showingIncomingModal = false;
  Timer? _pollTimer;
  // Every currently-pending offer, not just the one the ring-popup shows — backs the
  // persistent "New Job Requests" list so a provider can see/act on all of them, not
  // just whichever one triggered the alarm.
  List<JobOffer> _offers = [];
  List<ProviderReview> _reviews = [];
  bool _loadingReviews = false;
  String? _nidStatus;
  final _offersKey = GlobalKey();
  final _reviewsKey = GlobalKey();
  int _portfolioCount = 0;
  // Jobs this provider already proposed schedule-mode slots for — suppresses
  // re-showing the same accept/reject/propose dialog every poll tick for a
  // job that's still just sitting there pending (see _showIncomingJobModal's
  // onProposeSlots). In-memory only; a restart re-prompting once is fine.
  final Set<String> _proposedSlotJobIds = {};

  // Earnings
  WalletModel? _wallet;
  List<TransactionModel> _transactions = [];
  bool _loadingEarnings = false;

  // History
  List<JobModel> _jobHistory = [];
  bool _loadingHistory = false;

  // My applied services
  List<Map<String, dynamic>> _myServices = [];

  // An instructor's own courses, for the dashboard summary. Loaded only when this
  // provider actually teaches — everyone else never pays for the request.
  List<CourseModel> _myCourses = [];
  bool _loadingCourses = false;

  // The driver's live commission position — rate, why, and progress toward the free day.
  Map<String, dynamic>? _rideCommission;
  bool _loadingMyServices = false;

  // Dispatch standing (red cards / temp-ban / unpaid dues)
  ProviderStanding? _standing;

  bool _isBn = true;

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
    _loadProfilePhoto();
    _loadNidStatus();
    _loadReviews();
  }

  Future<void> _loadProfilePhoto() async {
    try {
      final me = await AuthService.instance.getMeRaw();
      final url =
          (me['providerProfile'] as Map?)?['profilePhotoUrl'] as String?;
      if (mounted && url != null && url.isNotEmpty)
        setState(() => _profilePhotoUrl = url);
    } catch (_) {
      // Non-fatal — the letter avatar stays as the fallback.
    }
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    try {
      final f = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final url = await AuthService.instance
          .uploadProviderProfilePhoto(base64Encode(bytes));
      if (mounted && url != null) setState(() => _profilePhotoUrl = url);
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
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
        _pollTimer ??=
            Timer.periodic(const Duration(seconds: 5), (_) => _poll());
        DispatchService.instance.startLocationTracking();
      }
    } catch (_) {
      // 404 = no session ever started — genuinely offline, nothing to do.
    } finally {
      if (mounted) setState(() => _checkingOnlineStatus = false);
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

  /// The vehicle a driver goes online with. Read from their commute profile; if it's missing
  /// or is legacy free text that doesn't match one of the three real types, ask once and save
  /// the answer so this only ever interrupts them the first time.
  /// Returns null only if the driver dismissed the picker.
  Future<String?> _resolveDriverVehicleType() async {
    String? stored;
    try {
      final profile = await CommuteService.instance.getMyProfile();
      stored = (profile['vehicleType'] as String?)?.trim().toLowerCase();
    } catch (_) {
      // Profile fetch failed — fall through to the picker rather than blocking go-online.
    }
    if (stored != null && kRideVehicleTypes.contains(stored)) return stored;

    if (!mounted) return null;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'আপনি কী চালান?' : 'What do you drive?',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          _isBn
              ? 'যাত্রী যে বাহন চান, সেই বাহনের চালকদের কাছেই অনুরোধ যায় — তাই এটা ঠিকভাবে বেছে নেওয়া জরুরি।'
              : 'Ride requests only go to drivers with the vehicle the passenger asked for, so pick accurately.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          for (final type in kRideVehicleTypes)
            TextButton(
              onPressed: () => Navigator.pop(ctx, type),
              child: Text(
                _isBn ? kRideVehicleLabelsBn[type]! : kRideVehicleLabelsEn[type]!,
                style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return null;

    // Persist so the next go-online is friction-free. Best-effort — a failed save just
    // means they get asked again, which is better than blocking them from working.
    try {
      await CommuteService.instance.upsertMyProfile(vehicleType: picked);
    } catch (_) {}
    return picked;
  }

  Future<void> _toggleOnline() async {
    if (_userId == null) {
      _showError(
          _isBn ? 'ব্যবহারকারীর তথ্য লোড হয়নি' : 'User data not loaded');
      return;
    }
    setState(() => _togglingOnline = true);
    try {
      if (_isOnline) {
        await DispatchService.instance.endSession(providerId: _userId!);
        DispatchService.instance.stopLocationTracking();
        _pollTimer?.cancel();
        _pollTimer = null;
        if (mounted)
          setState(() {
            _isOnline = false;
            _activeJob = null;
            _offers = [];
          });
      } else {
        final complete = await ensureProviderCompleteness(context, _isBn);
        if (!complete || !mounted) return;
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
              _showError(_isBn
                  ? 'লোকেশন সার্ভিস বন্ধ আছে'
                  : 'Location service is off');
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
              _showError(_isBn
                  ? 'লোকেশন অনুমতি দেওয়া হয়নি'
                  : 'Location permission not granted');
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
            _showError(
                _isBn ? 'লোকেশন পাওয়া যায়নি' : 'Could not get location');
            return;
          }
        }
        if (pos == null && !isLawyer) {
          // Physical providers are matched by distance — a session without
          // coordinates would never receive nearby jobs.
          _showError(_isBn
              ? 'লোকেশন পাওয়া যায়নি — GPS চালু করে আবার চেষ্টা করুন'
              : 'Could not get location — turn on GPS and try again');
          return;
        }
        debugPrint(
            '[Provider] GPS: ${pos?.latitude}, ${pos?.longitude} (lawyer=$isLawyer)');

        // Strip the "st_" catalog prefix — the backend compares against bare kind codes
        // (e.g. "technician"), so leaving it on ("st_technician") meant every approved
        // provider's own approved-kind never matched and going online here always failed
        // with "not approved for this service".
        final serviceKinds = _myServices
            .where((s) => s['status'] == 'approved')
            .map((s) =>
                (s['serviceTypeId'] as String? ?? '').replaceFirst('st_', ''))
            .where((id) => id.isNotEmpty)
            .toList();
        if (isLawyer && !serviceKinds.contains('lawyer')) {
          serviceKinds.add('lawyer');
        }
        if (serviceKinds.isEmpty) serviceKinds.add('technician');

        // A ride job always carries a vehicleType, and the broadcast filters providers by
        // `specializationsSnapshot has job.specialization` — so a driver who goes online
        // WITHOUT their vehicle type would silently never receive a single ride. Resolve it
        // (asking once if it's not on their profile yet) before the session starts.
        final vehicleSpecs = <String>[];
        if (serviceKinds.contains('commute')) {
          final vehicle = await _resolveDriverVehicleType();
          if (vehicle == null) {
            // Driver dismissed the picker — don't start a session that can never get work.
            if (mounted) setState(() => _togglingOnline = false);
            return;
          }
          vehicleSpecs.add(vehicle);
        }

        final locationMismatch = await DispatchService.instance.startSession(
          providerId: _userId!,
          serviceKinds: serviceKinds,
          currentLatitude: pos?.latitude,
          currentLongitude: pos?.longitude,
          providerNameSnapshot: _providerName,
          legalAreas: legal?.areas,
          legalServices: legal?.services,
          legalRole: legal?.role,
          verifiedSnapshot: legal?.verified,
          specializations: [...?specializations, ...vehicleSpecs],
        );
        if (mounted) {
          setState(() => _isOnline = true);
          _pollTimer =
              Timer.periodic(const Duration(seconds: 5), (_) => _poll());
          DispatchService.instance.startLocationTracking();
          if (locationMismatch) _showLocationMismatchNotice();
        }
      }
    } catch (e) {
      debugPrint('[Provider] toggleOnline error: $e');
      final ex = ApiClient.mapError(e);
      // dispatch-service's startLiveSession 400s with this exact bilingual message when a
      // caregiver/photographer/cinematographer/makeup_artist provider tries to go online
      // without a real gender set on their profile — surface it with a direct way to fix it
      // instead of a generic "could not go online" (which used to swallow the real reason,
      // leaving the provider stuck with no idea what to do next).
      if (ex.statusCode == 400 &&
          (ex.messageBn.contains('Gender') || ex.message.contains('Gender'))) {
        _showGenderRequiredDialog(ex);
      } else {
        _showError(ex.localized(_isBn));
      }
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  void _showLocationMismatchNotice() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'অবস্থান নিশ্চিত করুন' : 'Confirm your location',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          _isBn
              ? 'আপনার বর্তমান অবস্থান আপনার রেজিস্টার্ড ঠিকানা থেকে অনেক দূরে মনে হচ্ছে। আপনি কি নিশ্চিত আপনি এখন এখানে আছেন?'
              : 'Your current location looks far from your registered address. Are you sure you\'re here right now?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isBn ? 'হ্যাঁ, ঠিক আছে' : 'Yes, that\'s correct',
                style: const TextStyle(color: AppColors.deepBlue)),
          ),
        ],
      ),
    );
  }

  /// "Here's what's wrong, here's the fix" — same shape as the existing Meet-link dialog:
  /// state the actionable backend message, then a one-tap button straight into the screen
  /// that fixes it (GenderScreen), instead of leaving the provider to hunt for a settings menu.
  void _showGenderRequiredDialog(AppException ex) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.wc_rounded, color: Color(0xFFF59E0B), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_isBn ? 'Gender সেট করা প্রয়োজন' : 'Gender required',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Text(
          ex.localized(_isBn),
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isBn ? 'বাতিল' : 'Cancel',
                style: const TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GenderScreen()));
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(_isBn ? 'Gender সেট করুন' : 'Set gender'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
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
      final services =
          (pp['legalServices'] as List?)?.whereType<String>().toList() ??
              const <String>[];
      final areas = (pp['legalAreas'] as List?)?.whereType<String>().toList() ??
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
      final specs =
          (pp['specializations'] as List?)?.whereType<String>().toList() ??
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
      final jobs =
          await DispatchService.instance.listJobs(assignedProviderId: _userId);
      if (!mounted) return;

      final incoming = jobs.where((j) => j.status == 'assigned').toList();
      // Lawyer consultations are remote (Meet link) — they never enter the
      // physical arrival/OTP active-job flow. 'confirmed' is an advance-booking job
      // (photographer/cinematographer/makeup_artist) the customer has locked in for a future
      // date — without it here the job never surfaced as the active card and the provider had
      // no way to ever start/complete it (it just sat at 'confirmed' forever, unpaid).
      final active = jobs
          .where((j) =>
              j.serviceKind != 'lawyer' &&
              (j.status == 'confirmed' ||
                  j.status == 'accepted' ||
                  j.status == 'arriving' ||
                  j.status == 'in_progress'))
          .toList();

      if (active.isNotEmpty) {
        final latestActive = active.first;
        if (_activeJob == null ||
            _activeJob!.id != latestActive.id ||
            _activeJob!.status != latestActive.status) {
          setState(() => _activeJob = latestActive);
        }
      }

      if (incoming.isNotEmpty &&
          !_showingIncomingModal &&
          !_proposedSlotJobIds.contains(incoming.first.id)) {
        final incomingJob = incoming.first;
        try {
          final assignments =
              await DispatchService.instance.listAssignments(incomingJob.id);
          final pending =
              assignments.where((a) => a.status == 'pending').toList();
          if (pending.isNotEmpty && mounted) {
            _showingIncomingModal = true;
            _showIncomingJobModal(incomingJob, pending.first.id);
          }
        } catch (_) {}
      }

      // On-demand broadcast offers: jobs still 'searching' where I have a pending assignment.
      // (Directly-assigned jobs above stay 'assigned'; these are the geo-broadcast offers.)
      // Schedule-mode lawyer jobs live here too (broadcast, not direct-assigned) — skip any
      // already proposed on so the dialog doesn't reappear every 5s while it just sits pending.
      if (_activeJob == null) {
        try {
          final offers = await DispatchService.instance.getMyOffers();
          final freshOffers = offers
              .where((o) => !_proposedSlotJobIds.contains(o.job.id))
              .toList();
          if (mounted) setState(() => _offers = offers);
          if (freshOffers.isNotEmpty &&
              mounted &&
              !_showingIncomingModal &&
              _activeJob == null) {
            _showingIncomingModal = true;
            _showIncomingJobModal(
                freshOffers.first.job, freshOffers.first.assignmentId);
          }
        } catch (_) {}
      } else if (_offers.isNotEmpty) {
        setState(() => _offers = []);
      }
    } catch (_) {}
  }

  // Shared accept/reject path — used by both the ring-popup dialog (_showIncomingJobModal)
  // and the persistent "New Job Requests" list cards, so there's exactly one place that
  // calls respondToAssignment and handles the lawyer-Meet-link / active-job side effects.
  Future<void> _respondToOffer(
      JobModel job, String assignmentId, String response) async {
    setState(() => _offers =
        _offers.where((o) => o.assignmentId != assignmentId).toList());
    try {
      final r = await DispatchService.instance.respondToAssignment(
        assignmentId,
        response: response,
        jobId: job.id,
      );
      if (!mounted || response != 'accepted') return;
      if (job.serviceKind == 'lawyer') {
        // Remote consultation — no arrival/OTP flow. First to accept wins and gets the
        // Meet link right away.
        final meetLink = r['meetLink'] as String?;
        if (meetLink != null && meetLink.isNotEmpty) {
          _showMeetLinkDialog(job, meetLink);
        } else {
          _showInfo(_isBn ? 'পরামর্শ গৃহীত হয়েছে' : 'Consultation accepted');
        }
      } else {
        setState(() => _activeJob = job);
      }
    } catch (_) {
      if (mounted && response == 'accepted') {
        _showError(_isBn ? 'গ্রহণ করতে সমস্যা হয়েছে' : 'Could not accept');
      }
    }
  }

  void _showIncomingJobModal(JobModel job, String assignmentId) {
    // Covers both paths into this modal: a loud push already started this (see
    // push_service.dart) — harmless/idempotent to call again here — and the plain
    // 5s poll discovering an offer with no push involved at all (e.g. web, or the
    // push simply hasn't arrived yet). Either way the ring runs until accept/reject.
    AlarmNotificationService.instance.startRinging(
      title: job.serviceKind == 'lawyer'
          ? (_isBn
              ? 'নতুন আইনি পরামর্শের অনুরোধ'
              : 'New legal consultation request')
          : (_isBn ? 'নতুন কাজের অনুরোধ' : 'New job request'),
      body: _isBn
          ? '"${job.title}" — গ্রহণ করতে ট্যাপ করুন।'
          : '"${job.title}" — tap to accept.',
      payload: job.id,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _IncomingJobDialog(
        job: job,
        isBn: _isBn,
        onAccept: () async {
          AlarmNotificationService.instance.stopRinging();
          Navigator.pop(ctx);
          _showingIncomingModal = false;
          await _respondToOffer(job, assignmentId, 'accepted');
        },
        onReject: () async {
          AlarmNotificationService.instance.stopRinging();
          Navigator.pop(ctx);
          _showingIncomingModal = false;
          await _respondToOffer(job, assignmentId, 'rejected');
        },
        // Only offered for a schedule-mode lawyer job that's still open — instant-timing
        // and already-picked jobs go straight to accept/reject like before.
        onProposeSlots: (job.serviceKind == 'lawyer' &&
                job.consultationTiming == 'schedule')
            ? () {
                AlarmNotificationService.instance.stopRinging();
                Navigator.pop(ctx);
                _showingIncomingModal = false;
                _proposedSlotJobIds.add(job.id);
                _openProposeSlotsSheet(job);
              }
            : null,
      ),
    );
  }

  void _openProposeSlotsSheet(JobModel job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProposeSlotsSheet(
        job: job,
        isBn: _isBn,
        onSubmitted: () => _showInfo(_isBn
            ? 'সময় প্রস্তাব পাঠানো হয়েছে — গ্রাহক বেছে নিলে জানানো হবে'
            : 'Time slots proposed — you\'ll be notified when the customer picks one'),
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
      // Default page size (20) could silently drop earlier same-day transactions off page 1 for
      // a high-volume provider, undercounting "today's earnings" below — 100 comfortably covers
      // a single day's activity for this use case.
      final t = await FinanceService.instance
          .listTransactions(providerId: _userId, limit: 100);
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
    // Same reasoning as the portfolio fetch below: _isInstructor reads _myServices, so the
    // course summary can only be requested once that has resolved.
    if (_isInstructor) _loadMyCourses();
    if (_isDriver) _loadRideCommission();
    // Portfolio only exists for photography/cinema — fetch only when relevant, after
    // _myServices resolves (_isVisualProvider reads it), for the profile-completion check.
    if (_isVisualProvider) {
      try {
        final images = await OnboardingService.instance.listPortfolioImages();
        if (mounted) setState(() => _portfolioCount = images.length);
      } catch (_) {}
    }
  }

  Future<void> _loadNidStatus() async {
    final status = await OnboardingService.instance.getNidStatus();
    if (mounted) setState(() => _nidStatus = status);
  }

  Future<void> _loadReviews() async {
    if (mounted) setState(() => _loadingReviews = true);
    try {
      final reviews = await DispatchService.instance.getMyReviews();
      if (mounted) setState(() => _reviews = reviews);
    } catch (_) {}
    if (mounted) setState(() => _loadingReviews = false);
  }

  Future<void> _loadHistory() async {
    if (_userId == null) return;
    setState(() => _loadingHistory = true);
    try {
      final jobs =
          await DispatchService.instance.listJobs(assignedProviderId: _userId);
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

  /// Won consultation — hand the lawyer the Google Meet link, with a one-tap
  /// button straight into the Meet app/browser (see core/utils/meet_link.dart)
  /// alongside the copy fallback.
  void _showMeetLinkDialog(JobModel job, String meetLink) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.videocam_rounded,
              color: Color(0xFF10B981), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                _isBn ? 'পরামর্শ গৃহীত হয়েছে' : 'Consultation accepted',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isBn
                  ? '${job.customerNameSnapshot ?? 'গ্রাহক'} ভিডিও কলে যুক্ত হবেন।'
                  : '${job.customerNameSnapshot ?? 'The customer'} will join the video call.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
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
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => openMeetLink(ctx, meetLink),
                icon: const Icon(Icons.videocam_rounded, size: 18),
                label: Text(_isBn ? 'মিটিং এ যোগ দিন' : 'Join Meeting'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: meetLink));
              _showInfo(_isBn ? 'লিংক কপি হয়েছে' : 'Link copied');
            },
            icon: const Icon(Icons.copy_rounded,
                color: AppColors.deepBlue, size: 18),
            label: Text(_isBn ? 'কপি করুন' : 'Copy',
                style: const TextStyle(
                    color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isBn ? 'ঠিক আছে' : 'OK',
                style: const TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
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
          Text(
            _isBn ? 'প্রোভাইডার' : 'Provider',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          GestureDetector(
            onTap: (_togglingOnline || _checkingOnlineStatus)
                ? null
                : _toggleOnline,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: _isOnline ? AppColors.blueGradient : null,
                color: _isOnline ? null : AppColors.glassWhite,
                borderRadius: BorderRadius.circular(20),
                border:
                    _isOnline ? null : Border.all(color: AppColors.glassBorder),
              ),
              child: (_togglingOnline || _checkingOnlineStatus)
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _isOnline ? Colors.white : AppColors.deepBlue),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isOnline
                                ? const Color(0xFF4ADE80)
                                : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _isOnline
                                ? (_isBn ? 'অনলাইন' : 'Online')
                                : (_isBn ? 'অফলাইন' : 'Offline'),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isOnline
                                  ? Colors.white
                                  : AppColors.textMuted,
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
    final tabs = _isBn
        ? const ['ড্যাশবোর্ড', 'আয়', 'ইতিহাস']
        : const ['Dashboard', 'Earnings', 'History'];
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
                  border: isSelected
                      ? null
                      : Border.all(color: AppColors.glassBorder),
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
      title = _isBn
          ? (s.isBanned ? 'অ্যাকাউন্ট বন্ধ' : 'সাময়িকভাবে বন্ধ')
          : (s.isBanned ? 'Account Suspended' : 'Temporarily Suspended');
      body = _isBn
          ? (s.isBanned
              ? 'আপনার অ্যাকাউন্ট বন্ধ আছে। সহায়তার জন্য যোগাযোগ করুন।'
              : '৩টি রেড কার্ড হওয়ায় ${until ?? '৭ দিন'} পর্যন্ত নতুন কাজ পাবেন না।')
          : (s.isBanned
              ? 'Your account is suspended. Please contact support.'
              : 'You won\'t get new jobs until ${until ?? '7 days'} due to 3 red cards.');
    } else if (s.duesBlockingNewJobs) {
      icon = Icons.account_balance_wallet_rounded;
      color = const Color(0xFFEF4444);
      title = _isBn ? 'দেনা বাকি' : 'Dues Pending';
      body = _isBn
          ? '৳${s.unpaidDuesTotal.toStringAsFixed(0)} কমিশন দেনা বাকি — মেটানোর আগে নতুন কাজ পাবেন না।'
          : '৳${s.unpaidDuesTotal.toStringAsFixed(0)} commission due — you won\'t get new jobs until it\'s paid.';
    } else {
      icon = Icons.warning_amber_rounded;
      color = const Color(0xFFF59E0B);
      title = _isBn ? '${s.redFlags}টি রেড কার্ড' : '${s.redFlags} Red Card(s)';
      body = _isBn
          ? 'আর ${s.cardsUntilBan}টি কার্ড হলে ৭ দিনের জন্য কাজ বন্ধ হবে। কাজ accept করে বাতিল করা এড়িয়ে চলুন।'
          : '${s.cardsUntilBan} more card(s) will suspend you for 7 days. Avoid accepting and then cancelling jobs.';
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
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.45)),
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
    'BRONZE': 'ব্রোঞ্জ',
    'SILVER': 'সিলভার',
    'GOLD': 'গোল্ড',
    'PLATINUM': 'প্লাটিনাম',
  };
  static const _levelLabelsEn = {
    'BRONZE': 'Bronze',
    'SILVER': 'Silver',
    'GOLD': 'Gold',
    'PLATINUM': 'Platinum',
  };
  static const _levelColors = {
    'BRONZE': Color(0xFFB08D57),
    'SILVER': Color(0xFF9CA3AF),
    'GOLD': Color(0xFFF59E0B),
    'PLATINUM': Color(0xFF8B5CF6),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.blueGradient,
              shape: BoxShape.circle,
              image: (_profilePhotoUrl?.isNotEmpty ?? false)
                  ? DecorationImage(
                      image: NetworkImage(_profilePhotoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: (_profilePhotoUrl?.isNotEmpty ?? false)
                ? null
                : Text(
                    (_providerName?.isNotEmpty ?? false)
                        ? _providerName![0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_providerName ?? (_isBn ? 'প্রোভাইডার' : 'Provider'),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (s?.dispatchAvgRating != null) ...[
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFF59E0B), size: 14),
                      const SizedBox(width: 3),
                      Text(
                        s!.dispatchAvgRating!.toStringAsFixed(2),
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.deepBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_isBn ? 'নতুন' : 'New',
                            style: const TextStyle(
                                color: AppColors.deepBlue,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    if (s != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: levelColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: levelColor.withOpacity(0.4)),
                        ),
                        child: Text(
                            (_isBn
                                    ? _levelLabelsBn[s.level]
                                    : _levelLabelsEn[s.level]) ??
                                s.level,
                            style: TextStyle(
                                color: levelColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                          _isBn
                              ? 'মোট ${s.totalCompleted}টি কাজ'
                              : 'Total ${s.totalCompleted} jobs',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Gender is a profile preference, not a financial/verification stat — moved here
          // from the quick-action grid (only shown for the 4 kinds where it's actually asked).
          if (_isGenderRelevantProvider)
            IconButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GenderScreen())),
              icon: const Icon(Icons.wc_rounded,
                  color: AppColors.textMuted, size: 20),
              tooltip: _isBn ? 'Gender' : 'Gender',
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
        .where((t) =>
            t.isCredit &&
            t.createdAt.year == now.year &&
            t.createdAt.month == now.month &&
            t.createdAt.day == now.day)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  // Last 7 days of credited earnings, oldest first — same _transactions list _todayEarnings
  // already reads, just bucketed by day, so the sparkline below costs no extra request.
  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.1);
    }
  }

  // Compact 4-tile row: total (lifetime) income, completed jobs, rating, pending offers.
  // Each tile is tappable and goes somewhere real — a stat that looks like a card but does
  // nothing on tap reads as broken.
  Widget _buildStatsRow() {
    final rating = _standing?.dispatchAvgRating;
    final pendingCount = _offers.length;
    final tiles = <(String, String, Color, VoidCallback)>[
      (
        _isBn ? 'মোট আয়' : 'Total Income',
        '৳${(_wallet?.lifetimeEarnings ?? 0).toStringAsFixed(0)}',
        AppColors.deepBlue,
        () => setState(() => _tab = 1), // আয় tab
      ),
      (
        _isBn ? 'সম্পন্ন কাজ' : 'Completed',
        '${_standing?.totalCompleted ?? 0}',
        AppColors.softBlue,
        () => setState(() => _tab = 2), // ইতিহাস tab
      ),
      (
        _isBn ? 'রেটিং' : 'Rating',
        rating != null
            ? '⭐ ${rating.toStringAsFixed(1)}'
            : (_isBn ? 'নতুন' : 'New'),
        AppColors.softAmber,
        () => _scrollToSection(_reviewsKey),
      ),
      (
        _isBn ? 'পেন্ডিং কাজ' : 'Pending',
        '$pendingCount',
        pendingCount > 0 ? AppColors.softRed : AppColors.textMuted,
        () => _scrollToSection(_offersKey),
      ),
    ];
    return Row(
      children: tiles.asMap().entries.map((entry) {
        final isLast = entry.key == tiles.length - 1;
        final (label, value, color, onTap) = entry.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: isLast ? 0 : 8),
            child: Material(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Column(
                    children: [
                      Text(value,
                          style: TextStyle(
                              color: color,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Each unmet criterion, with a label explaining WHAT it is and an action that fixes it —
  // tapping the bar used to jump straight into whichever fix came first (usually the raw
  // image picker for the photo), with no explanation of what was being asked for.
  List<(String, IconData, VoidCallback)> _profileCompletionGaps(bool needsNid) {
    return [
      if (!(_profilePhotoUrl?.isNotEmpty ?? false))
        (
          _isBn ? 'প্রোফাইল ছবি যোগ করুন' : 'Add a profile photo',
          Icons.person_outline_rounded,
          _pickAndUploadProfilePhoto
        ),
      if (needsNid && _nidStatus != 'verified')
        (
          _isBn ? 'NID যাচাই করুন' : 'Verify your NID',
          Icons.credit_card_outlined,
          () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const NidScreen())),
        ),
      if (_isVisualProvider && _portfolioCount == 0)
        (
          _isBn ? 'পোর্টফোলিও ছবি যোগ করুন' : 'Add portfolio photos',
          Icons.photo_library_outlined,
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PortfolioScreen())),
        ),
      if (!_myServices.any((s) => s['status'] == 'approved'))
        (
          _isBn ? 'একটি সেবার জন্য আবেদন করুন' : 'Apply for a service',
          Icons.add_circle_outline_rounded,
          () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ProviderOnboardingScreen())),
        ),
    ];
  }

  void _showProfileCompletionSheet(
      List<(String, IconData, VoidCallback)> gaps) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isBn
                    ? 'প্রোফাইল সম্পূর্ণ করতে যা বাকি'
                    : 'What\'s left to complete your profile',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ...gaps.map((g) {
              final (label, icon, action) = g;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    action();
                  },
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(icon, color: AppColors.deepBlue, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(label,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const Icon(Icons.arrow_forward_rounded,
                            color: AppColors.textMuted, size: 16),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // Profile-completion nudge — only counts criteria applicable to this provider (e.g. NID
  // isn't asked of a non-dispatch/matchmaking provider, portfolio isn't asked of a technician).
  Widget _buildProfileCompletion() {
    final needsNid = _isDispatchProvider || _isMatchmakingProvider;
    final criteria = <bool>[
      _profilePhotoUrl?.isNotEmpty ?? false,
      _myServices.any((s) => s['status'] == 'approved'),
      if (needsNid) _nidStatus == 'verified',
      if (_isVisualProvider) _portfolioCount > 0,
    ];
    if (criteria.isEmpty) return const SizedBox.shrink();
    final done = criteria.where((c) => c).length;
    final pct = (done / criteria.length * 100).round();
    if (pct >= 100) return const SizedBox.shrink();
    final gaps = _profileCompletionGaps(needsNid);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _showProfileCompletionSheet(gaps),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isBn
                          ? 'প্রোফাইল $pct% সম্পূর্ণ'
                          : 'Profile $pct% complete',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded,
                      color: AppColors.deepBlue, size: 16),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: done / criteria.length,
                  minHeight: 6,
                  backgroundColor: AppColors.glassBorder,
                  valueColor: const AlwaysStoppedAnimation(AppColors.deepBlue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<double> get _last7DaysEarnings {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      return _transactions
          .where((t) =>
              t.isCredit &&
              t.createdAt.year == day.year &&
              t.createdAt.month == day.month &&
              t.createdAt.day == day.day)
          .fold(0.0, (sum, t) => sum + t.amount);
    });
  }

  Widget _buildTodayEarningsCard() {
    final days = _last7DaysEarnings;
    final maxDay = days.fold(0.0, (m, v) => v > m ? v : m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: AppColors.blueGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_isBn ? 'আজকের আয়' : 'Today\'s Earnings',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('৳ ${_todayEarnings.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                if (_standing != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_isBn ? 'এই সপ্তাহে' : 'This Week',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(
                          _isBn
                              ? '${_standing!.weeklyCompleted}টি কাজ'
                              : '${_standing!.weeklyCompleted} jobs',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
              ],
            ),
            if (maxDay > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: days.map((v) {
                    final heightFraction = (v / maxDay).clamp(0.12, 1.0);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FractionallySizedBox(
                          heightFactor: heightFraction,
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  Colors.white.withOpacity(v > 0 ? 0.85 : 0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _isInstructor =>
      _myServices.any((s) => s['serviceTypeId'] == 'st_micro_learning' && s['status'] == 'approved');

  Future<void> _loadMyCourses() async {
    if (_userId == null || !_isInstructor) return;
    setState(() => _loadingCourses = true);
    try {
      final list = await MicroLearningService.instance.listMyCourses(_userId!);
      if (mounted) setState(() => _myCourses = list);
    } catch (_) {
      // The card just shows zeros; the rest of the dashboard is unaffected.
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  /// An instructor's courses, on the dashboard they actually open. Reaching them used to
  /// mean leaving the dashboard for Profile → "Teach a Course" — the authoring screen was
  /// never linked from here at all, so nothing about teaching was visible on this screen.
  Widget _buildMyCoursesCard() {
    if (!_isInstructor) return const SizedBox.shrink();

    final published = _myCourses.where((c) => c.status == 'published').length;
    final pending = _myCourses.where((c) => c.status == 'pending_review').length;
    final drafts = _myCourses.where((c) => c.status == 'draft').length;
    final learners = _myCourses.fold<int>(0, (t, c) => t + (c.enrollmentCount ?? 0));

    Widget stat(String value, String label) => Expanded(
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const CourseAuthoringScreen()))
            .then((_) => _loadMyCourses()),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.cast_for_education_rounded,
                  color: AppColors.deepBlue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_isBn ? 'আমার কোর্স' : 'My courses',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              if (_loadingCourses)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.textMuted))
              else
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted, size: 18),
            ]),
            const SizedBox(height: 14),
            if (_myCourses.isEmpty && !_loadingCourses)
              Text(
                _isBn
                    ? 'এখনো কোনো কোর্স নেই — এখানে চেপে প্রথমটি বানান'
                    : 'No courses yet — tap here to make your first',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              )
            else
              Row(children: [
                stat('$published', _isBn ? 'প্রকাশিত' : 'Published'),
                stat('$pending', _isBn ? 'অপেক্ষায়' : 'In review'),
                stat('$drafts', _isBn ? 'খসড়া' : 'Drafts'),
                stat('$learners', _isBn ? 'শিক্ষার্থী' : 'Learners'),
              ]),
            // Anything still unpublished earns nothing, so say so rather than leaving a
            // silent number the instructor has to interpret.
            if (drafts > 0) ...[
              const SizedBox(height: 10),
              Text(
                _isBn
                    ? '$drafts টি খসড়া প্রকাশ করা হয়নি — শিক্ষার্থীরা এগুলো দেখতে পাচ্ছে না'
                    : '$drafts draft(s) are unpublished — learners cannot see them',
                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  bool get _isDriver =>
      _myServices.any((s) => s['serviceTypeId'] == 'st_commute' && s['status'] == 'approved');

  Future<void> _loadRideCommission() async {
    final c = await DispatchService.instance.getMyRideCommission();
    if (mounted) setState(() => _rideCommission = c);
  }

  Future<void> _redeemCoupon() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'কুপন কোড' : 'Coupon code',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: _isBn ? 'যেমন RIDE2026' : 'e.g. RIDE2026',
            hintStyle: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_isBn ? 'বাতিল' : 'Cancel',
                  style: const TextStyle(color: AppColors.textMuted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(_isBn ? 'প্রয়োগ করুন' : 'Apply',
                  style: const TextStyle(
                      color: AppColors.deepBlue, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await DispatchService.instance.redeemRideCoupon(code);
      await _loadRideCommission();
      if (mounted) _showInfo(_isBn ? 'কুপন প্রয়োগ হয়েছে' : 'Coupon applied');
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  Future<void> _buyDayPass() async {
    final fee = _rideCommission?['dayPassFee'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: Text(_isBn ? 'আজকের পাস কিনবেন?' : 'Buy a day pass?',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          _isBn
              ? 'আজ সারাদিনের সব রাইডে কোনো কমিশন কাটা হবে না। খরচ ৳$fee।'
              : 'No commission on any ride today. It costs ৳$fee.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_isBn ? 'না' : 'No',
                  style: const TextStyle(color: AppColors.textMuted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_isBn ? 'কিনুন' : 'Buy',
                  style: const TextStyle(
                      color: AppColors.deepBlue, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DispatchService.instance.buyRideDayPass();
      await _loadRideCommission();
      if (mounted) _showInfo(_isBn ? 'আজকের পাস কেনা হয়েছে' : "Today's pass is active");
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  /// A rule nobody can see is a rule nobody rides differently for, so this shows the rate,
  /// the reason behind it, and exactly how far the next break is.
  Widget _buildRideCommissionCard() {
    final c = _rideCommission;
    if (!_isDriver || c == null) return const SizedBox.shrink();

    final rate = (c['rate'] as num?)?.toDouble() ?? 0;
    final reason = (_isBn ? c['reasonBn'] : c['reason'])?.toString() ?? '';
    final daysLeft = (c['daysUntilFreeDay'] as num?)?.toInt() ?? 0;
    final hasCoupon = c['hasCoupon'] == true;
    final hasPass = c['hasDayPassToday'] == true;
    final fee = c['dayPassFee'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.percent_rounded, color: AppColors.deepBlue, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_isBn ? 'আপনার রাইড কমিশন' : 'Your ride commission',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            Text('${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%',
                style: TextStyle(
                    color: rate == 0 ? const Color(0xFF10B981) : AppColors.deepBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(reason, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          if (!hasPass && daysLeft > 0) ...[
            const SizedBox(height: 10),
            Text(
              _isBn
                  ? 'আর $daysLeft দিন টানা রাইড করলে পরের দিন কোনো কমিশন লাগবে না'
                  : 'Ride $daysLeft more day(s) in a row and the next day is commission-free',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (!hasCoupon)
              Expanded(
                child: OutlinedButton(
                  onPressed: _redeemCoupon,
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.deepBlue)),
                  child: Text(_isBn ? 'কুপন আছে' : 'I have a coupon',
                      style: const TextStyle(color: AppColors.deepBlue, fontSize: 12)),
                ),
              ),
            if (!hasCoupon && !hasPass) const SizedBox(width: 8),
            if (!hasPass)
              Expanded(
                child: OutlinedButton(
                  onPressed: _buyDayPass,
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.glassBorder)),
                  child: Text(_isBn ? 'আজকের পাস ৳$fee' : 'Day pass ৳$fee',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildProfileStrip(),
          _buildStatsRow(),
          const SizedBox(height: 12),
          _buildProfileCompletion(),
          _buildTodayEarningsCard(),
          _buildRideCommissionCard(),
          _buildMyCoursesCard(),
          _buildStandingBanner(),
          if (_checkingOnlineStatus)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.deepBlue)),
              ),
            )
          else if (!_isOnline)
            GestureDetector(
              onTap: _togglingOnline ? null : _toggleOnline,
              child: GlassCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          color: AppColors.glassWhite,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.glassBorder)),
                      child: _togglingOnline
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: AppColors.deepBlue),
                            )
                          : const Icon(Icons.power_settings_new_rounded,
                              color: AppColors.textMuted, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text(
                        _togglingOnline
                            ? (_isBn ? 'সংযোগ হচ্ছে…' : 'Connecting…')
                            : (_isBn ? 'অফলাইনে আছেন' : 'You are offline'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                        _isBn
                            ? 'কাজ পেতে এখানে ট্যাপ করুন'
                            : 'Tap here to receive jobs',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_activeJob != null)
            _buildActiveJobCard()
          else
            KeyedSubtree(key: _offersKey, child: _buildJobRequestsSection()),
          const SizedBox(height: 16),
          _buildQuickActions(),
          if (_loadingMyServices || _myServices.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildMyServicesSection(),
          ],
          const SizedBox(height: 16),
          KeyedSubtree(key: _reviewsKey, child: _buildReviewsCard()),
        ],
      ),
    );
  }

  // Replaces the old single oversized "waiting for jobs" box — shows every currently-pending
  // offer as an actionable card (same accept/reject path as the ring-popup, via
  // _respondToOffer), falling back to a compact one-line empty state when there are none.
  Widget _buildJobRequestsSection() {
    if (_offers.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.search_rounded,
                color: AppColors.textMuted, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isBn
                        ? 'এই মুহূর্তে কোনো নতুন অনুরোধ নেই'
                        : 'No new requests right now',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  if (_standing != null && _standing!.weeklyCompleted > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      _isBn
                          ? 'গত ৭ দিনে ${_standing!.weeklyCompleted}টি কাজ সম্পন্ন করেছেন'
                          : 'You completed ${_standing!.weeklyCompleted} job(s) in the last 7 days',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isBn ? 'নতুন কাজের অনুরোধ' : 'New Job Requests',
          style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8),
        ),
        const SizedBox(height: 10),
        ..._offers.map((o) => _buildOfferCard(o)),
      ],
    );
  }

  Widget _buildOfferCard(JobOffer offer) {
    final job = offer.job;
    final amount = job.finalAmount ?? job.quotedAmount ?? job.estimatedAmount;
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
                  child: Text(job.title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                if (amount != null)
                  Text('৳${amount.round()}',
                      style: const TextStyle(
                          color: AppColors.deepBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
              ],
            ),
            if ((job.pickupAddressSnapshot ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(job.isRide ? Icons.trip_origin_rounded : Icons.location_on_outlined,
                      color: AppColors.textMuted, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(job.pickupAddressSnapshot!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ),
                ],
              ),
            ],
            // Where the ride GOES is the single fact a driver decides on, and it was missing
            // from this card entirely — every ride was accepted or skipped blind. distanceKm is
            // road km (see the dispatch-service ROAD_FACTOR fix), so it matches the fare shown.
            if (job.isRide) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.flag_rounded, color: AppColors.deepBlue, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      job.dropoffAddressSnapshot ??
                          (_isBn ? 'গন্তব্য ম্যাপে দেওয়া আছে' : 'Destination pinned on the map'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (job.distanceKm != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      _isBn
                          ? '${job.distanceKm!.toStringAsFixed(1)} কিমি'
                          : '${job.distanceKm!.toStringAsFixed(1)} km',
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _respondToOffer(job, offer.assignmentId, 'rejected'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.glassBorder),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_isBn ? 'বাতিল' : 'Skip',
                        style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _respondToOffer(job, offer.assignmentId, 'accepted'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_isBn ? 'গ্রহণ করুন' : 'Accept',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Aggregate rating already shown in the stats row — this card adds the human element (recent
  // review text). Empty state is mandatory per spec: most providers here have zero reviews.
  Widget _buildReviewsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded,
                  color: AppColors.softAmber, size: 18),
              const SizedBox(width: 8),
              Text(_isBn ? 'রেটিং ও রিভিউ' : 'Rating & Reviews',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_standing?.dispatchAvgRating != null)
                Text(
                    '⭐ ${_standing!.dispatchAvgRating!.toStringAsFixed(1)} (${_standing!.totalCompleted})',
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingReviews)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.deepBlue))),
            )
          else if (_reviews.isEmpty)
            Text(_isBn ? 'এখনো কোনো রিভিউ নেই।' : 'No reviews yet.',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13))
          else
            ..._reviews.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                              r.customerName ?? (_isBn ? 'গ্রাহক' : 'Customer'),
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          if (r.rating != null)
                            Text('⭐ ${r.rating}',
                                style: const TextStyle(
                                    color: AppColors.softAmber,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                        ],
                      ),
                      if ((r.review ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(r.review!,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                                height: 1.4)),
                      ],
                    ],
                  ),
                )),
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

  // Gender is only a meaningful preference filter (and only gates going online — see
  // dispatch-service's startLiveSession) on these 4 kinds — hide the quick action for
  // everyone else so a technician isn't shown a field that does nothing for their service.
  bool get _isGenderRelevantProvider => _myServices.any((s) {
        final id = (s['serviceTypeId'] as String? ?? '');
        return id.contains('caregiver') ||
            id.contains('photograph') ||
            id.contains('cinema') ||
            id.contains('makeup');
      });

  // Commission (GET /dispatch/commissions/mine) only exists for jobs dispatch-service
  // brokers — a tutor or pet-care provider will only ever see "no commissions" here, which
  // reads as broken rather than "not applicable to you".
  static const _kDispatchKinds = {
    'technician',
    'task_runner',
    'caregiver',
    'lawyer',
    'makeup_artist',
    'cinematographer',
    'photographer',
    'quick_help',
    // 2026-08-27: cook and commute became dispatch kinds, so their providers now earn
    // commissioned dispatch jobs and need the Commission/NID tiles like everyone else.
    'cook',
    'commute',
  };
  // MatchRequestsInboxScreen is hard-scoped to these 4 matchmaking-service request types —
  // anyone else always sees an empty inbox.
  static const _kMatchmakingKinds = {
    'home_tutor',
    'pet_care',
    'mess_finder',
    'helping_hand'
  };

  bool _hasServiceKind(Set<String> kinds) => _myServices.any((s) => kinds
      .contains((s['serviceTypeId'] as String? ?? '').replaceFirst('st_', '')));

  bool get _isDispatchProvider => _hasServiceKind(_kDispatchKinds);
  bool get _isMatchmakingProvider => _hasServiceKind(_kMatchmakingKinds);

  Widget _buildQuickActions() {
    void nav(Widget w) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    // Subtitle is a live number pulled from state already loaded elsewhere on this screen
    // (wallet/standing) — no extra network calls, just surfacing data that used to be
    // invisible until you tapped in.
    final walletSub =
        _wallet != null ? '৳${_wallet!.balance.toStringAsFixed(0)}' : null;
    // Coordinated 2-color system (deep green for the primary money action, soft blue/amber for
    // everything else) instead of a different hardcoded hex per tile — the grid used to read as
    // uncoordinated because each tile picked an arbitrary color.
    final actions = [
      (
        Icons.account_balance_wallet_outlined,
        _isBn ? 'ওয়ালেট' : 'Wallet',
        walletSub,
        AppColors.deepBlue,
        () => nav(const WalletScreen())
      ),
      if (_isDispatchProvider)
        (
          Icons.percent_rounded,
          _isBn ? 'কমিশন' : 'Commission',
          null,
          AppColors.softAmber,
          () => nav(const CommissionScreen())
        ),
      if (_isDispatchProvider || _isMatchmakingProvider)
        (
          Icons.credit_card_outlined,
          'NID',
          null,
          AppColors.softBlue,
          () => nav(const NidScreen())
        ),
      if (_isVisualProvider)
        (
          Icons.photo_library_outlined,
          _isBn ? 'পোর্টফোলিও' : 'Portfolio',
          null,
          AppColors.softBlue,
          () => nav(const PortfolioScreen())
        ),
      if (_isMatchmakingProvider)
        (
          Icons.inbox_rounded,
          _isBn ? 'ম্যাচ অনুরোধ' : 'Match Requests',
          null,
          AppColors.softBlue,
          () => nav(const MatchRequestsInboxScreen())
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              color: color.withOpacity(0.75),
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Cook/Laundry aren't part of the onboarding-application flow (_myServices) — they're
        // separate provider tracks (NID-verified cook profile / hub-staff membership, both
        // admin-set), so any provider may want to explore them regardless of _myServices.
        // Kept out of the primary row above (which IS filtered by relevance) so they don't
        // eat two of a technician/lawyer/tutor's slots for tracks they'll never use.
        Row(
          children: [
            Expanded(
                child: _buildMoreIncomeChip(
                    Icons.soup_kitchen_outlined,
                    _isBn ? 'রাঁধুনি' : 'Cook',
                    () => nav(const CookProviderScreen()))),
            const SizedBox(width: 8),
            Expanded(
                child: _buildMoreIncomeChip(
                    Icons.local_laundry_service_outlined,
                    _isBn ? 'লন্ড্রি হাব' : 'Laundry Hub',
                    () => nav(const LaundryHubScreen()))),
          ],
        ),
        const SizedBox(height: 8),
        // Commute had NO provider-side entry point at all before rides moved onto dispatch —
        // a driver could only reach it through the customer tab.
        Row(
          children: [
            // Instant rides are a map-first job — a driver waiting for a fare needs to see
            // where they are and judge a request by pickup distance, which a card list can't do.
            Expanded(
                child: _buildMoreIncomeChip(
                    Icons.two_wheeler_outlined,
                    _isBn ? 'রাইড (ড্রাইভার)' : 'Drive',
                    () => nav(const DriverModeScreen()))),
            const SizedBox(width: 8),
            // The recurring cost-sharing arrangement is a different product from an instant
            // fare, so it keeps its own entry. Tab 1 = "Offer a ride", not the passenger tab.
            Expanded(
                child: _buildMoreIncomeChip(
                    Icons.groups_outlined,
                    _isBn ? 'কমিউট পার্টনার' : 'Commute Partner',
                    () => nav(const CommuteScreen(initialTab: 1)))),
          ],
        ),
      ],
    );
  }

  Widget _buildMoreIncomeChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // Same per-type screens used for the approved deep-link buttons below, reused here so a
  // rejected/needs_changes application can route straight to the form that needs fixing
  // instead of leaving the provider stuck with only a colored status chip.
  Widget? _profileScreenForServiceType(String? serviceTypeId) {
    switch (serviceTypeId) {
      case 'st_home_tutor':
        return const TutorProfileScreen();
      case 'st_photographer':
        return const PhotographerProfileScreen();
      case 'st_cinematographer':
        return const CinematographerProfileScreen();
      case 'st_caregiver':
        return const CaregiverProfileScreen();
      case 'st_technician':
        return const TechnicianOnboardingScreen();
      case 'st_pet_care':
        return const PetCareProfileScreen();
      case 'st_skill_share':
        return const SkillShareProfileScreen();
      case 'st_micro_learning':
        return const MicroLearningProfileScreen();
      case 'st_makeup_artist':
        return const MakeupArtistProfileScreen();
      case 'st_quick_help':
        return const QuickHelpProfileScreen();
      case 'st_helping_hand':
        return const HouseholdHelpProfileScreen();
      default:
        return null;
    }
  }

  Future<void> _fixAndResubmit(Map<String, dynamic> svc) async {
    final screen =
        _profileScreenForServiceType(svc['serviceTypeId'] as String?);
    if (screen == null) {
      _showInfo(_isBn ? 'সাপোর্টে যোগাযোগ করুন' : 'Please contact support');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    final applicationId = svc['applicationId'] as String?;
    if (applicationId == null) return;
    try {
      await OnboardingService.instance.submitApplication(applicationId);
      if (mounted)
        _showInfo(_isBn ? 'পুনরায় জমা দেওয়া হয়েছে' : 'Resubmitted');
      _loadMyServices();
    } catch (e) {
      if (mounted)
        _showError(_isBn
            ? 'জমা দেওয়া যায়নি — আবার চেষ্টা করুন'
            : 'Could not resubmit — try again');
    }
  }

  Widget _buildMyServicesSection() {
    if (_loadingMyServices) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.deepBlue)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(_isBn ? 'আমার সেবাসমূহ' : 'My Services',
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
              // Providers can hold up to 3 approved services (see bulkCreateApplications) —
              // this is the only entry point into that flow from the dashboard itself.
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProviderOnboardingScreen())),
                child: Text(_isBn ? '+ নতুন সেবা যোগ করুন' : '+ Add a service',
                    style: const TextStyle(
                        color: AppColors.deepBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        ..._myServices.map((svc) {
          // GET /onboarding/my-services returns name/nameEn at the top level. This used to
          // look for a nested serviceType object that the endpoint has never sent, so it
          // always fell through to the raw id — every provider saw "st_commute" where the
          // service name belongs.
          final name = (_isBn
                  ? svc['name'] as String?
                  : svc['nameEn'] as String? ?? svc['name'] as String?) ??
              svc['serviceType']?['name'] as String? ??
              svc['serviceTypeId'] as String? ??
              '—';
          final status = svc['status'] as String? ?? 'draft';
          final isApprovedTutor =
              svc['serviceTypeId'] == 'st_home_tutor' && status == 'approved';
          final isApprovedPhotographer =
              svc['serviceTypeId'] == 'st_photographer' && status == 'approved';
          final isApprovedCinematographer =
              svc['serviceTypeId'] == 'st_cinematographer' &&
                  status == 'approved';
          final isApprovedCaregiver =
              svc['serviceTypeId'] == 'st_caregiver' && status == 'approved';
          final isApprovedTechnician =
              svc['serviceTypeId'] == 'st_technician' && status == 'approved';
          final isApprovedPetCare =
              svc['serviceTypeId'] == 'st_pet_care' && status == 'approved';
          final isApprovedSkillShare =
              svc['serviceTypeId'] == 'st_skill_share' && status == 'approved';
          final isApprovedMicroLearning =
              svc['serviceTypeId'] == 'st_micro_learning' &&
                  status == 'approved';
          final isApprovedMakeupArtist =
              svc['serviceTypeId'] == 'st_makeup_artist' &&
                  status == 'approved';
          final isApprovedQuickHelp =
              svc['serviceTypeId'] == 'st_quick_help' && status == 'approved';
          final isApprovedHouseholdHelp =
              svc['serviceTypeId'] == 'st_helping_hand' && status == 'approved';
          final needsFix = status == 'rejected' || status == 'needs_changes';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (isApprovedTutor) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const TutorProfileScreen())),
                          child: Text(
                              _isBn ? 'বিষয় ও লেভেল' : 'Subjects & Levels',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedPhotographer) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const PhotographerProfileScreen())),
                          child: Text(
                              _isBn ? 'গিয়ার প্রোফাইল' : 'Gear Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedCinematographer) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const CinematographerProfileScreen())),
                          child: Text(
                              _isBn ? 'গিয়ার প্রোফাইল' : 'Gear Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedCaregiver) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const CaregiverProfileScreen())),
                          child: Text(
                              _isBn
                                  ? 'সার্টিফিকেট ও বিশেষত্ব'
                                  : 'Certificate & Specializations',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedTechnician) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const TechnicianOnboardingScreen())),
                          child: Text(
                              _isBn
                                  ? 'ক্যাটাগরি ও বিশেষত্ব'
                                  : 'Category & Specializations',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedPetCare) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const PetCareProfileScreen())),
                          child: Text(
                              _isBn
                                  ? 'পোষা প্রাণী প্রোফাইল'
                                  : 'Pet Care Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedSkillShare) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const SkillShareProfileScreen())),
                          child: Text(
                              _isBn ? 'শিক্ষাগত তথ্য' : 'Education Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedMicroLearning) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(
                                  builder: (_) => const CourseAuthoringScreen()))
                              .then((_) => _loadMyCourses()),
                          child: Text(_isBn ? 'আমার কোর্স' : 'My Courses',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const MicroLearningProfileScreen())),
                          child: Text(
                              _isBn ? 'দক্ষতা প্রোফাইল' : 'Expertise Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedMakeupArtist) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const MakeupArtistProfileScreen())),
                          child: Text(
                              _isBn ? 'মেকআপ প্রোফাইল' : 'Makeup Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedQuickHelp) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const QuickHelpProfileScreen())),
                          child: Text(
                              _isBn
                                  ? 'কুইক হেল্প প্রোফাইল'
                                  : 'Quick Help Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isApprovedHouseholdHelp) ...[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const HouseholdHelpProfileScreen())),
                          child: Text(
                              _isBn
                                  ? 'গৃহকর্মী প্রোফাইল'
                                  : 'Household Help Profile',
                              style: const TextStyle(
                                  color: AppColors.deepBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      _statusChip(status),
                    ],
                  ),
                  if (needsFix) ...[
                    const SizedBox(height: 8),
                    Text(
                      (svc['reviewNote'] as String?)?.isNotEmpty == true
                          ? svc['reviewNote'] as String
                          : (_isBn
                              ? 'বিস্তারিত জানতে সাপোর্টে যোগাযোগ করুন'
                              : 'Contact support for details'),
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                          height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _fixAndResubmit(svc),
                        child: Text(
                            _isBn ? 'সংশোধন করে জমা দিন' : 'Fix & resubmit',
                            style: const TextStyle(
                                color: AppColors.deepBlue,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
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
      'approved' => (
          _isBn ? 'অনুমোদিত' : 'Approved',
          const Color(0x2010B981),
          const Color(0xFF10B981)
        ),
      'rejected' => (
          _isBn ? 'প্রত্যাখ্যাত' : 'Rejected',
          const Color(0x20EF4444),
          const Color(0xFFEF4444)
        ),
      'needs_changes' => (
          _isBn ? 'পরিবর্তন দরকার' : 'Needs Changes',
          const Color(0x20F59E0B),
          const Color(0xFFF59E0B)
        ),
      'submitted' || 'under_review' => (
          _isBn ? 'পর্যালোচনায়' : 'Under Review',
          const Color(0x20F97316),
          const Color(0xFFF97316)
        ),
      _ => ('Draft', const Color(0x20888888), AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
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
                decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(_isBn ? 'সক্রিয় কাজ' : 'Active Job',
                  style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          if (job.eventDate != null) ...[
            const SizedBox(height: 12),
            _EventDateBanner(job: job, isBn: _isBn),
          ],
          const SizedBox(height: 12),
          Text(job.title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (job.customerNameSnapshot != null)
            Text(
                '${_isBn ? 'গ্রাহক' : 'Customer'}: ${job.customerNameSnapshot}',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 4),
          Text('${_isBn ? 'অবস্থা' : 'Status'}: ${job.statusLabel(_isBn)}',
              style: const TextStyle(
                  color: AppColors.deepBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          GlassButton(
            label: _isBn ? 'কাজ পরিচালনা করুন' : 'Manage Job',
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
      return const Center(
          child: CircularProgressIndicator(color: AppColors.deepBlue));
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
                Text(_isBn ? 'মোট ব্যালেন্স' : 'Total Balance',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 8),
                Text(
                  '৳ ${_wallet?.balance.toStringAsFixed(0) ?? '0'}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 36,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_wallet?.currency ?? 'BDT',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(_isBn ? 'লেনদেনের ইতিহাস' : 'Transaction History',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          if (_transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text(_isBn ? 'কোনো লেনদেন নেই' : 'No transactions',
                      style: const TextStyle(color: AppColors.textMuted))),
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
                color: isCredit
                    ? const Color(0x2010B981)
                    : const Color(0x20EF4444),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCredit
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: isCredit
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.description ??
                        (_isBn
                            ? (isCredit ? 'জমা' : 'উত্তোলন')
                            : (isCredit ? 'Credit' : 'Withdrawal')),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              '${isCredit ? '+' : '-'}৳ ${t.amount.toStringAsFixed(0)}',
              style: TextStyle(
                color: isCredit
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
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
      return const Center(
          child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: AppColors.deepBlue,
      child: _jobHistory.isEmpty
          ? Center(
              child: Text(_isBn ? 'কোনো কাজের ইতিহাস নেই' : 'No job history',
                  style: const TextStyle(color: AppColors.textMuted)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _jobHistory.length,
              itemBuilder: (_, i) => _buildHistoryTile(_jobHistory[i]),
            ),
    );
  }

  static const _actionableStatuses = {
    'confirmed',
    'accepted',
    'arriving',
    'in_progress'
  };

  Widget _buildHistoryTile(JobModel job) {
    // Only the single most-recent non-lawyer active job surfaces as the dashboard's "Active Job"
    // card (see _poll's `active.first`) — a provider with more than one confirmed advance-booking
    // at once had no way to reach the others at all. Any job still in a workable status opens
    // straight into ActiveJobScreen from here instead.
    final actionable = _actionableStatuses.contains(job.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: actionable
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ActiveJobScreen(
                    job: job,
                    onJobCompleted: () {
                      if (mounted && _activeJob?.id == job.id)
                        setState(() => _activeJob = null);
                      _loadHistory();
                    },
                  ),
                ))
            : null,
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
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(job.statusLabel(_isBn),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ),
                ],
              ),
              if (job.customerNameSnapshot != null) ...[
                const SizedBox(height: 4),
                Text(
                    '${_isBn ? 'গ্রাহক' : 'Customer'}: ${job.customerNameSnapshot}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
              if (job.finalAmount != null || job.estimatedAmount != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${_isBn ? 'মূল্য' : 'Price'}: ৳ ${(job.finalAmount ?? job.estimatedAmount)!.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: AppColors.deepBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
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

bool _hasCaregiverInfo(JobModel job) =>
    (job.caregiverDetail?.patientCondition?.isNotEmpty ?? false) ||
    job.caregiverDetail?.patientAge != null ||
    (job.providerGenderPreference != null &&
        job.providerGenderPreference != 'any');

/// Caregiver-only info block shown to the provider before they accept/respond —
/// patient condition/age + the customer's self-declared gender preference
/// (informational only, never filters who gets the broadcast).
class _CaregiverInfoBlock extends StatelessWidget {
  final JobModel job;
  final bool isBn;
  const _CaregiverInfoBlock({required this.job, required this.isBn});

  @override
  Widget build(BuildContext context) {
    final detail = job.caregiverDetail;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.deepBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail?.patientCondition != null &&
              detail!.patientCondition!.isNotEmpty)
            _row(Icons.medical_information_rounded, detail.patientCondition!),
          if (detail?.patientAge != null)
            _row(
                Icons.cake_rounded,
                isBn
                    ? 'বয়স: ${detail!.patientAge}'
                    : 'Age: ${detail!.patientAge}'),
          if (job.providerGenderPreference != null &&
              job.providerGenderPreference != 'any')
            _row(
                Icons.wc_rounded,
                isBn
                    ? 'পছন্দ: ${job.providerGenderPreference}'
                    : 'Preference: ${job.providerGenderPreference}'),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppColors.deepBlue),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5))),
          ],
        ),
      );
}

class _IncomingJobDialog extends StatelessWidget {
  final JobModel job;
  final bool isBn;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback? onProposeSlots;

  const _IncomingJobDialog({
    required this.job,
    required this.isBn,
    required this.onAccept,
    required this.onReject,
    this.onProposeSlots,
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
                decoration: BoxDecoration(
                    gradient: AppColors.blueGradient, shape: BoxShape.circle),
                child: const Icon(Icons.work_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isBn ? 'নতুন কাজের অনুরোধ!' : 'New Job Request!',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            // Advance-booking jobs — surface the event date BEFORE accept so
            // the provider doesn't book a slot they can't make.
            if (job.eventDate != null) ...[
              const SizedBox(height: 14),
              _EventDateBanner(job: job, isBn: isBn),
            ],
            const SizedBox(height: 12),
            Text(
              job.title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (job.customerNameSnapshot != null) ...[
              const SizedBox(height: 6),
              Text(
                '${isBn ? 'গ্রাহক' : 'Customer'}: ${job.customerNameSnapshot}',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
            if (job.pickupAddressSnapshot != null) ...[
              const SizedBox(height: 4),
              Text(
                job.exactLocationHidden
                    ? '${isBn ? 'আনুমানিক এলাকা' : 'Approximate area'}: ${job.pickupAddressSnapshot}'
                    : job.pickupAddressSnapshot!,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              if (job.exactLocationHidden) ...[
                const SizedBox(height: 4),
                Text(
                  isBn
                      ? 'গ্রহণ করলে সম্পূর্ণ ঠিকানা ও ফোন দেখা যাবে'
                      : 'Full address and phone will show once accepted',
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            if (job.serviceKind == 'caregiver' && _hasCaregiverInfo(job)) ...[
              const SizedBox(height: 12),
              _CaregiverInfoBlock(job: job, isBn: isBn),
            ],
            if (job.estimatedAmount != null) ...[
              const SizedBox(height: 12),
              Text(
                '৳ ${job.estimatedAmount!.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: AppColors.deepBlue,
                    fontSize: 24,
                    fontWeight: FontWeight.w800),
              ),
            ],
            if (onProposeSlots != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onProposeSlots,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.deepBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.deepBlue.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_available_rounded,
                          size: 18, color: AppColors.deepBlue),
                      const SizedBox(width: 8),
                      Text(
                          isBn
                              ? 'ব্যস্ত? এর বদলে সময় প্রস্তাব করুন'
                              : 'Busy? Propose a different time instead',
                          style: const TextStyle(
                              color: AppColors.deepBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5)),
                    ],
                  ),
                ),
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
                        border: Border.all(
                            color: const Color(0xFFEF4444), width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          isBn ? 'প্রত্যাখ্যান' : 'Reject',
                          style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
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
                      child: Center(
                        child: Text(
                          isBn ? 'গ্রহণ করুন' : 'Accept',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
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

// ── Propose 1-3 alternative times for a schedule-mode lawyer job ───
// Each row is a fixed 1-hour window (matches the "7-8pm, 8-9pm" style the
// founder described) — start-only picking keeps this to one tap per slot
// instead of a full date-time-range picker for both ends.
class _ProposeSlotsSheet extends StatefulWidget {
  final JobModel job;
  final bool isBn;
  final VoidCallback onSubmitted;

  const _ProposeSlotsSheet(
      {required this.job, required this.isBn, required this.onSubmitted});

  @override
  State<_ProposeSlotsSheet> createState() => _ProposeSlotsSheetState();
}

class _ProposeSlotsSheetState extends State<_ProposeSlotsSheet> {
  final List<DateTime?> _starts = [null];
  bool _submitting = false;
  String? _error;

  Future<void> _pickStart(int index) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    setState(() {
      _starts[index] =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final chosen = _starts.whereType<DateTime>().toList();
    if (chosen.isEmpty) {
      setState(() => _error = widget.isBn
          ? 'অন্তত একটি সময় বাছাই করুন'
          : 'Select at least one time');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await DispatchService.instance.proposeSlots(
        widget.job.id,
        chosen
            .map((s) => {
                  'start': s.toUtc().toIso8601String(),
                  'end':
                      s.add(const Duration(hours: 1)).toUtc().toIso8601String(),
                })
            .toList(),
      );
      if (mounted) Navigator.pop(context);
      widget.onSubmitted();
    } catch (e) {
      if (mounted)
        setState(() => _error = ApiClient.mapError(e).localized(widget.isBn));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmt(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month} — $h:$mm $ampm (${widget.isBn ? '১ ঘণ্টা' : '1 hour'})';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text(widget.isBn ? 'সময় প্রস্তাব করুন' : 'Propose Time Slots',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  widget.isBn
                      ? '"${widget.job.title}" — সর্বোচ্চ ৩টি সময় দিন, গ্রাহক একটি বেছে নেবেন।'
                      : '"${widget.job.title}" — give up to 3 time slots, the customer will pick one.',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 16),
              for (int i = 0; i < _starts.length; i++) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickStart(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F7F0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(children: [
                      const Icon(Icons.schedule_rounded,
                          size: 18, color: AppColors.deepBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _starts[i] == null
                              ? (widget.isBn
                                  ? 'সময় ${i + 1} বাছাই করুন'
                                  : 'Select time ${i + 1}')
                              : _fmt(_starts[i]!),
                          style: TextStyle(
                            color: _starts[i] == null
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: _starts[i] == null
                                ? FontWeight.w400
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_starts.length > 1)
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: AppColors.textMuted),
                          onPressed: () => setState(() => _starts.removeAt(i)),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_starts.length < 3)
                TextButton.icon(
                  onPressed: () => setState(() => _starts.add(null)),
                  icon: const Icon(Icons.add_rounded,
                      size: 18, color: AppColors.deepBlue),
                  label: Text(
                      widget.isBn ? 'আরেকটি সময় যোগ করুন' : 'Add another time',
                      style: const TextStyle(
                          color: AppColors.deepBlue, fontSize: 13)),
                ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFEF4444), fontSize: 12.5)),
              ],
              const SizedBox(height: 12),
              GlassButton(
                label: widget.isBn ? 'প্রস্তাব পাঠান' : 'Send Proposal',
                icon: Icons.send_rounded,
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ]),
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
  final bool isBn;
  const _EventDateBanner({required this.job, required this.isBn});

  static const _bnMonthsFull = [
    'জানুয়ারি',
    'ফেব্রুয়ারি',
    'মার্চ',
    'এপ্রিল',
    'মে',
    'জুন',
    'জুলাই',
    'আগস্ট',
    'সেপ্টেম্বর',
    'অক্টোবর',
    'নভেম্বর',
    'ডিসেম্বর',
  ];
  static const _enMonthsFull = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
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
    final day = isBn ? _bnDigits(local.day) : local.day.toString();
    final month =
        isBn ? _bnMonthsFull[local.month - 1] : _enMonthsFull[local.month - 1];
    final year = isBn ? _bnDigits(local.year) : local.year.toString();
    final hh =
        isBn ? _bnPad2(local.hour) : local.hour.toString().padLeft(2, '0');
    final mm =
        isBn ? _bnPad2(local.minute) : local.minute.toString().padLeft(2, '0');
    final duration = job.estimatedDurationHours;
    final durationLabel = duration != null
        ? (isBn ? ' (${_bnDigits(duration)} ঘণ্টা)' : ' ($duration hr)')
        : '';

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
                Text(
                  isBn ? 'অনুষ্ঠানের তারিখ' : 'Event Date',
                  style: const TextStyle(
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
