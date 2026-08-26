import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../core/utils/jwt_utils.dart';
import '../models/dispatch_model.dart';
import '../services/catalog_service.dart';
import '../services/dispatch_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/pin_picker_screen.dart';
import 'advance_booking_browse_screen.dart';
import 'job_tracking_screen.dart';

class JobRequestScreen extends StatefulWidget {
  final String serviceKind;
  final String serviceLabel;

  const JobRequestScreen({
    super.key,
    required this.serviceKind,
    required this.serviceLabel,
  });

  @override
  State<JobRequestScreen> createState() => _JobRequestScreenState();
}

class _JobRequestScreenState extends State<JobRequestScreen> {
  // description state
  List<String> _commonIssues = [];
  String? _selectedIssue;
  final _customController = TextEditingController();

  // Task-category pricing (technician jobs). Sending taskCategory lets the backend resolve
  // estimatedAmount from the platform rate — without it the job has no price and commission is ৳0.
  List<TaskCategoryRate> _rates = [];
  String? _selectedCategory;
  bool _isLoadingRates = false;

  String _urgencyLevel = 'normal';
  bool _isLocating = false;
  bool _locationDetected = false;
  String? _address; // reverse-geocoded Bengali address (fallback: raw coords)

  // Task-runner categories (কাজের লোক) — errand types from GET /dispatch/task-runner/categories.
  // These are NOT the priced TaskCategory enum, so the pick goes into the job TITLE, not taskCategory.
  List<Map<String, dynamic>> _runnerCategories = [];
  String? _selectedRunnerCode;
  bool _isSubmitting = false;
  bool _isLoadingIssues = true;

  // Technician specialization taxonomy (5 groups × 36 types). Two-level picker:
  // group tiles → type chips. Sent to POST /dispatch/jobs as `specialization`
  // so the broadcast only reaches technicians who ticked this type. Without a
  // taxonomy the picker hides itself and the flow falls back to any-technician.
  TechnicianSpecializationTaxonomy? _specTaxonomy;
  bool _isLoadingSpecs = false;
  String? _selectedSpecGroup;
  String? _selectedSpecType;

  // "কতজন অনলাইন" badge — count for the picked specialization, null hides it.
  int? _onlineTechCount;
  int _countSeq = 0; // guards against out-of-order responses
  Timer? _debounce;

  double? _latitude;
  double? _longitude;
  bool _isBn = true;

  // Nearby-providers preview map — awareness only ("is anyone even online for
  // this service"), never a pick-a-provider flow. Booking still goes through
  // the existing broadcast/advance-booking paths.
  List<NearbyProviderModel> _nearbyProviders = [];
  bool _isLoadingNearby = true;

  static const _customLabel = 'কাস্টম';

  /// Only technician jobs are priced by task category.
  bool get _needsCategory => widget.serviceKind == 'technician';

  /// Technician jobs also carry a specialization — WHO fixes it, alongside the
  /// taskCategory (which sets the PRICE). Both coexist.
  bool get _needsSpecialization => widget.serviceKind == 'technician';

  /// কাজের লোক (task runner) picks an errand type — routed into the job title.
  bool get _needsRunnerCategory => widget.serviceKind == 'task_runner';

  /// Photographer/cinematographer/makeup_artist jobs are scheduled in advance
  /// (browse-and-confirm), not nearest-first. Sending eventDate flips the
  /// backend to the advance flow, and the app then routes to the browse screen.
  static const _advanceBookingKinds = {'photographer', 'cinematographer', 'makeup_artist'};
  bool get _isCaregiver => widget.serviceKind == 'caregiver';
  bool get _isAdvanceBooking =>
      _advanceBookingKinds.contains(widget.serviceKind) ||
      (_isCaregiver && _caregiverBookingMode == 'schedule');

  /// providerGenderPreference is shared across caregiver AND the 3 always-advance-booking
  /// kinds — self-declared/informational only, shown to the provider, never filters anyone.
  bool get _needsGenderPreference => _isCaregiver || _advanceBookingKinds.contains(widget.serviceKind);

  /// A ride is the only point-to-point kind — it needs a destination and a vehicle type,
  /// and the backend refuses to create one without both. Every other kind happens AT pickup.
  bool get _isRide => widget.serviceKind == 'commute';

  // Ride state — destination + vehicle. Unlike the pickup (which auto-detects from GPS),
  // a destination is always chosen deliberately on the map.
  double? _dropLatitude;
  double? _dropLongitude;
  String? _dropAddress;
  String _vehicleType = kRideVehicleTypes.first;
  /// Rate cards keyed by vehicle type, so the fare can be previewed BEFORE submitting —
  /// otherwise the customer only learns the price after the job already exists.
  final Map<String, RateCardModel> _rideRates = {};
  bool _loadingRideRates = false;

  // Advance-booking picker state.
  DateTime? _eventDate;
  int _durationHours = 4;

  // Caregiver-only: multi-day booking range end (eventDate above is reused as the range start).
  DateTime? _eventEndDate;

  // Caregiver-only: "এখনই দরকার" (default, existing broadcast flow) vs "পরে বুকিং"
  // (routes into the same browse+pick advance-booking flow as photographer/cinema/makeup).
  String _caregiverBookingMode = 'now';

  // Caregiver-only patient details.
  final _patientConditionCtrl = TextEditingController();
  final _patientAgeCtrl = TextEditingController();

  // Shared self-declared preference (caregiver + the 3 advance-booking kinds).
  // Convention: 'any' = no preference.
  String _providerGenderPreference = 'any';

  String? get _selectedRunnerLabel {
    if (_selectedRunnerCode == null) return null;
    for (final c in _runnerCategories) {
      if (c['code'] == _selectedRunnerCode) return (c['labelBn'] ?? c['label'])?.toString();
    }
    return null;
  }

  TaskCategoryRate? get _selectedRate {
    if (_selectedCategory == null) return null;
    for (final r in _rates) {
      if (r.taskCategory == _selectedCategory) return r;
    }
    return null;
  }

  static const _urgencyOptions = [
    ('normal', 'স্বাভাবিক', 'Normal'),
    ('high', 'জরুরি', 'Urgent'),
    ('emergency', 'অতি জরুরি', 'Emergency'),
  ];

  String _issueLabel(String issue) => issue == _customLabel ? (_isBn ? 'কাস্টম' : 'Custom') : issue;

  @override
  void initState() {
    super.initState();
    _loadCommonIssues();
    _detectLocation();
    _loadNearbyProviders();
    if (_needsCategory) _loadRates();
    if (_needsRunnerCategory) _loadRunnerCategories();
    if (_needsSpecialization) _loadSpecTaxonomy();
    if (_isRide) _loadRideRates();
  }

  Future<void> _loadSpecTaxonomy() async {
    setState(() => _isLoadingSpecs = true);
    try {
      final tax = await CatalogService.instance.getTechnicianSpecializationsNew();
      if (mounted) {
        setState(() {
          _specTaxonomy = tax;
          _isLoadingSpecs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSpecs = false);
    }
  }

  /// Fetch fresh online-tech count for the current specialization + location.
  /// Debounced so rapid group/type taps don't spam the endpoint. Any failure
  /// (endpoint down, 4xx) hides the badge — never blocks submission.
  void _scheduleCountRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _refreshOnlineCount);
  }

  Future<void> _refreshOnlineCount() async {
    final spec = _selectedSpecType;
    if (spec == null) {
      if (mounted) setState(() => _onlineTechCount = null);
      return;
    }
    final seq = ++_countSeq;
    final count = await DispatchService.instance.countOnlineTechnicians(
      specialization: spec,
      lat: _latitude,
      lon: _longitude,
    );
    if (!mounted || seq != _countSeq) return;
    setState(() => _onlineTechCount = count);
  }

  Future<void> _loadRunnerCategories() async {
    try {
      final cats = await DispatchService.instance.getTaskRunnerCategories();
      if (mounted) setState(() => _runnerCategories = cats);
    } catch (_) {}
  }

  Future<void> _loadRates() async {
    setState(() => _isLoadingRates = true);
    try {
      final raw = await DispatchService.instance.getTaskCategoryRates();
      if (!mounted) return;
      setState(() {
        _rates = raw.map(TaskCategoryRate.fromJson).toList();
        _isLoadingRates = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRates = false);
    }
  }

  /// Ride rate cards, keyed by vehicle type. The backend prices the ride itself at
  /// createJob; this is purely so the customer sees the fare BEFORE committing, the way
  /// every ride-hailing app does. If the fetch fails we simply show no estimate rather
  /// than blocking the request — the real price is still computed server-side.
  Future<void> _loadRideRates() async {
    setState(() => _loadingRideRates = true);
    try {
      final cards = await DispatchService.instance.getRateCards(serviceKind: 'commute');
      if (!mounted) return;
      setState(() {
        _rideRates
          ..clear()
          ..addEntries(cards.where((c) => c.isActive).map((c) => MapEntry(c.rateName, c)));
        _loadingRideRates = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRideRates = false);
    }
  }

  /// Straight-line pickup→dropoff km, mirroring the backend's haversine so the previewed
  /// fare matches what createJob will actually charge.
  double? get _rideDistanceKm {
    if (_latitude == null || _longitude == null || _dropLatitude == null || _dropLongitude == null) {
      return null;
    }
    const r = 6371.0;
    final dLat = (_dropLatitude! - _latitude!) * math.pi / 180;
    final dLon = (_dropLongitude! - _longitude!) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_latitude! * math.pi / 180) *
            math.cos(_dropLatitude! * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Estimated fare for [type]. Null when the distance or rate card isn't known yet.
  /// Surge is deliberately NOT applied here — it's evaluated server-side at createJob,
  /// so quoting it client-side could show a number the backend then disagrees with.
  double? _fareFor(String type) {
    final km = _rideDistanceKm;
    final card = _rideRates[type];
    if (km == null || card == null) return null;
    return card.baseCharge + (card.perKmRate ?? 0) * km;
  }

  Future<void> _pickDestination() async {
    final pin = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => PinPickerScreen(isBn: _isBn)),
    );
    if (pin == null) return;
    setState(() {
      _dropLatitude = pin.latitude;
      _dropLongitude = pin.longitude;
      _dropAddress = null;
    });
    try {
      final addr = await DispatchService.instance.reverseGeocode(pin.latitude, pin.longitude);
      if (mounted && addr != null) setState(() => _dropAddress = addr);
    } catch (_) {
      // Non-fatal — coordinates alone are enough to create the ride.
    }
  }

  /// Awareness-only nearby-providers fetch (see `_nearbyProviders` doc comment).
  /// Called once immediately (unfiltered, so something shows before GPS resolves)
  /// and again once coordinates land (radius-filtered).
  Future<void> _loadNearbyProviders() async {
    try {
      final list = await DispatchService.instance.searchProviders(
        serviceKind: widget.serviceKind,
        lat: _latitude,
        lon: _longitude,
        radiusKm: 15,
      );
      if (!mounted) return;
      setState(() {
        _nearbyProviders = list;
        _isLoadingNearby = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingNearby = false);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _patientConditionCtrl.dispose();
    _patientAgeCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCommonIssues() async {
    try {
      final serviceType = await CatalogService.instance.getServiceType(widget.serviceKind);
      if (!mounted) return;
      final issues = serviceType.commonIssues;
      if (issues.isNotEmpty) {
        setState(() {
          _commonIssues = [...issues, _customLabel];
          _selectedIssue = issues.first;
          _isLoadingIssues = false;
        });
      } else {
        setState(() => _isLoadingIssues = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingIssues = false);
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { setState(() => _isLocating = false); return; }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) { setState(() => _isLocating = false); return; }
      }
      if (permission == LocationPermission.deniedForever) { setState(() => _isLocating = false); return; }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() => _isLocating = false);
        await _onLocationResolved(position.latitude, position.longitude);
      }
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // Shared by live GPS (_detectLocation) and the manual map picker (_pickOnMap) —
  // whichever way the coordinates came in, both refresh the online-tech badge,
  // the nearby-providers map, and the best-effort reverse-geocoded address.
  Future<void> _onLocationResolved(double lat, double lng) async {
    if (!mounted) return;
    setState(() {
      _latitude = lat;
      _longitude = lng;
      _locationDetected = true;
    });
    if (_needsSpecialization && _selectedSpecType != null) {
      _scheduleCountRefresh();
    }
    _loadNearbyProviders();
    final addr = await DispatchService.instance.reverseGeocode(lat, lng);
    if (mounted && addr != null) setState(() => _address = addr);
  }

  // GPS off / permission denied / geocoding unavailable — let the customer drop a
  // pin instead of the old raw-latitude/longitude text fields, which no real user
  // could actually fill in (nobody knows their own coordinates by heart).
  Future<void> _pickOnMap() async {
    final pin = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => PinPickerScreen(isBn: _isBn)),
    );
    if (pin == null) return;
    await _onLocationResolved(pin.latitude, pin.longitude);
  }

  Future<void> _submit() async {
    final description = _commonIssues.isNotEmpty
        ? (_selectedIssue == _customLabel
            ? _customController.text.trim()
            : _selectedIssue ?? '')
        : _customController.text.trim();

    // Specialization first — the category chips are filtered by it now.
    if (_needsSpecialization && _selectedSpecType == null && _specTaxonomy != null) {
      _showError(_isBn ? 'কোন ধরনের টেকনিশিয়ান দরকার তা বেছে নিন' : 'Choose what kind of technician you need');
      return;
    }

    // Only require a category when there IS a relevant one to pick — an unmapped/unseeded
    // specialization renders no chips, and blocking submit on an invisible section would
    // dead-end the request.
    if (_needsCategory && _selectedCategory == null && _visibleRates.isNotEmpty) {
      _showError(_isBn ? 'কাজের ধরন বেছে নিন' : 'Choose a job type');
      return;
    }

    // Warn when nobody with this specialization is online before firing the request.
    if (_needsSpecialization && _onlineTechCount == 0) {
      final proceed = await _confirmNoOneOnline();
      if (proceed != true) return;
    }

    if (_needsRunnerCategory && _selectedRunnerCode == null && _runnerCategories.isNotEmpty) {
      _showError(_isBn ? 'কাজের ধরন বেছে নিন' : 'Choose a job type');
      return;
    }

    if (_isAdvanceBooking) {
      if (_isCaregiver) {
        // Caregiver pre-booking is a date RANGE, not a single event moment — no duration-hours field.
        if (_eventDate == null || _eventEndDate == null) {
          _showError(_isBn ? 'শুরু ও শেষের তারিখ বেছে নিন' : 'Choose the start and end date');
          return;
        }
        if (_eventEndDate!.isBefore(_eventDate!)) {
          _showError(_isBn ? 'শেষের তারিখ শুরুর তারিখের আগে হতে পারবে না' : 'The end date cannot be before the start date');
          return;
        }
      } else {
        if (_eventDate == null) { _showError(_isBn ? 'ইভেন্টের তারিখ ও সময় বেছে নিন' : 'Choose the event date and time'); return; }
        if (!_eventDate!.isAfter(DateTime.now())) { _showError(_isBn ? 'ইভেন্টের সময় ভবিষ্যতে হতে হবে' : 'The event time must be in the future'); return; }
        if (_durationHours < 1) { _showError(_isBn ? 'কতক্ষণের কাজ, তা লিখুন' : 'Enter how long the job will take'); return; }
      }
    }

    // A ride needs a destination — the backend rejects one without it, so catch it here
    // with a clearer message than a round-trip 400.
    if (_isRide && (_dropLatitude == null || _dropLongitude == null)) {
      _showError(_isBn ? 'কোথায় যাবেন সেটা বেছে নিন' : 'Choose where you are going');
      return;
    }

    // Every other kind describes a problem; a ride's "description" is just the route, which
    // the pins already carry — don't force the customer to type something meaningless.
    if (!_isRide && description.isEmpty) {
      _showError(_commonIssues.isNotEmpty
          ? (_isBn ? 'সমস্যা বেছে নিন বা বিস্তারিত লিখুন' : 'Pick an issue or describe it yourself')
          : (_isBn ? 'কাজের বিবরণ লিখুন' : 'Describe the job'));
      return;
    }

    final lat = _latitude;
    final lng = _longitude;
    if (lat == null || lng == null) { _showError(_isBn ? 'অবস্থান নির্ধারণ করুন — ম্যাপে দেখিয়ে দিন' : 'Set your location — pick it on the map'); return; }

    final token = await ApiClient.getAccessToken();
    final customerId = token != null ? decodeJwtSub(token) : null;
    if (customerId == null) { _showError(_isBn ? 'লগইন তথ্য পাওয়া যায়নি' : 'Login information not found'); return; }

    setState(() => _isSubmitting = true);
    try {
      final job = await DispatchService.instance.createJob(
        customerId: customerId,
        serviceTypeId: 'default',
        serviceKind: widget.serviceKind,
        // Task-runner: the errand label becomes the title so the provider instantly knows the task.
        // Ride: the destination is the useful title — a driver scanning offers needs to see
        // where they'd be going, not the word "Request".
        title: _isRide
            ? (_isBn
                ? 'রাইড → ${_dropAddress ?? 'গন্তব্য'}'
                : 'Ride → ${_dropAddress ?? 'destination'}')
            : (_selectedRunnerLabel ?? '${widget.serviceLabel} Request'),
        description: description,
        urgencyLevel: _urgencyLevel,
        pickupLatitude: lat,
        pickupLongitude: lng,
        taskCategory: _selectedCategory,
        specialization: _selectedSpecType,
        pickupAddressSnapshot: _address,
        eventDate: _isAdvanceBooking ? _eventDate : null,
        estimatedDurationHours: (_isAdvanceBooking && !_isCaregiver) ? _durationHours : null,
        eventEndDate: (_isAdvanceBooking && _isCaregiver) ? _eventEndDate : null,
        bookingMode: _isCaregiver ? _caregiverBookingMode : null,
        providerGenderPreference: _needsGenderPreference ? _providerGenderPreference : null,
        patientCondition: _isCaregiver && _patientConditionCtrl.text.trim().isNotEmpty
            ? _patientConditionCtrl.text.trim()
            : null,
        patientAge: _isCaregiver ? int.tryParse(_patientAgeCtrl.text.trim()) : null,
        dropoffLatitude: _isRide ? _dropLatitude : null,
        dropoffLongitude: _isRide ? _dropLongitude : null,
        dropoffAddressSnapshot: _isRide ? _dropAddress : null,
        vehicleType: _isRide ? _vehicleType : null,
      );
      if (!mounted) return;

      // Advance-booking: no broadcast — the customer will now browse providers
      // free for that slot. notifiedProviderCount doesn't apply here.
      if (_isAdvanceBooking) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdvanceBookingBrowseScreen(
              jobId: job.id,
              serviceKind: widget.serviceKind,
              eventDate: _eventDate!,
              eventEndDate: _isCaregiver ? _eventEndDate : null,
            ),
          ),
        );
        return;
      }

      // Backend broadcast reached 0 providers — surface it here instead of
      // leaving the customer on a spinner in the tracking screen.
      if (job.notifiedProviderCount == 0) {
        _showError(_isBn ? 'এই মুহূর্তে এই কাজের জন্য কেউ পাওয়া যায়নি — একটু পরে আবার চেষ্টা করুন' : 'No one is available for this job right now — try again shortly');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBn ? 'আপনার অনুরোধ পাঠানো হয়েছে!' : 'Your request has been sent!', style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: job.id)),
      );
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool?> _confirmNoOneOnline() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _isBn ? 'কেউ অনলাইন নেই' : 'No one is online',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          _isBn
              ? 'এই মুহূর্তে এই কাজের কোনো টেকনিশিয়ান অনলাইন নেই — অনুরোধ পাঠালে অপেক্ষা করতে হতে পারে।'
              : 'No technician for this job is online right now — sending the request may mean a wait.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_isBn ? 'তবুও পাঠান' : 'Send anyway',
                style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: AppColors.ivory)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionLabel(_isBn ? 'আশেপাশে উপলব্ধ ${widget.serviceLabel}' : 'Nearby ${widget.serviceLabel}'),
                        const SizedBox(height: 10),
                        _buildNearbyProvidersMap(),
                        const SizedBox(height: 20),
                        if (_needsSpecialization) ...[
                          _sectionLabel(_isBn ? 'কোন ধরনের টেকনিশিয়ান দরকার?' : 'What kind of technician do you need?'),
                          const SizedBox(height: 10),
                          _buildSpecializationSection(),
                          if (_selectedSpecType != null) ...[
                            const SizedBox(height: 12),
                            _buildOnlineTechBadge(),
                          ],
                          const SizedBox(height: 20),
                        ],
                        if (_needsCategory && (_isLoadingRates || _visibleRates.isNotEmpty)) ...[
                          _sectionLabel(_isBn ? 'কাজের ধরন' : 'Job type'),
                          const SizedBox(height: 10),
                          _buildCategorySection(),
                          const SizedBox(height: 20),
                        ],
                        if (_needsRunnerCategory && _runnerCategories.isNotEmpty) ...[
                          _sectionLabel(_isBn ? 'কাজের ধরন' : 'Job type'),
                          const SizedBox(height: 10),
                          _buildRunnerCategorySection(),
                          const SizedBox(height: 20),
                        ],
                        if (_isCaregiver) ...[
                          _sectionLabel(_isBn ? 'রোগীর তথ্য' : 'Patient details'),
                          const SizedBox(height: 10),
                          _buildPatientFields(),
                          const SizedBox(height: 20),
                          _sectionLabel(_isBn ? 'কখন দরকার?' : 'When do you need this?'),
                          const SizedBox(height: 10),
                          _buildCaregiverModeToggle(),
                          if (_caregiverBookingMode == 'schedule') ...[
                            const SizedBox(height: 16),
                            _sectionLabel(_isBn ? 'শুরু ও শেষের তারিখ' : 'Start and end date'),
                            const SizedBox(height: 10),
                            _buildCaregiverDateRangePicker(),
                          ],
                          const SizedBox(height: 20),
                        ],
                        if (_needsGenderPreference) ...[
                          _sectionLabel(_isCaregiver
                              ? (_isBn ? 'কেমন caregiver চান?' : 'Provider preference')
                              : (_isBn ? 'প্রোভাইডার পছন্দ' : 'Provider preference')),
                          const SizedBox(height: 10),
                          _buildGenderPreferenceChips(),
                          const SizedBox(height: 20),
                        ],
                        if (_isAdvanceBooking && !_isCaregiver) ...[
                          _sectionLabel(_isBn ? 'ইভেন্টের তারিখ ও সময়' : 'Event date and time'),
                          const SizedBox(height: 10),
                          _buildEventDatePicker(),
                          const SizedBox(height: 20),
                          _sectionLabel(_isBn ? 'কতক্ষণের কাজ? (ঘণ্টা)' : 'How long? (hours)'),
                          const SizedBox(height: 10),
                          _buildDurationPicker(),
                          const SizedBox(height: 20),
                        ],
                        if (_isRide) ...[
                          _sectionLabel(_isBn ? 'কোথায় যাবেন?' : 'Where are you going?'),
                          const SizedBox(height: 10),
                          _buildDestinationCard(),
                          const SizedBox(height: 20),
                          _sectionLabel(_isBn ? 'বাহন' : 'Vehicle'),
                          const SizedBox(height: 10),
                          _buildVehicleTypeSelector(),
                          const SizedBox(height: 20),
                        ],
                        // A ride's route already says everything a driver needs — no free-text
                        // description step (see the matching skip in _submit's validation).
                        if (!_isRide) ...[
                          _sectionLabel(_isBn ? 'কাজের বিবরণ' : 'Job description'),
                          const SizedBox(height: 8),
                          _buildDescriptionSection(),
                          const SizedBox(height: 20),
                        ],
                        if (!_isAdvanceBooking) ...[
                          _sectionLabel(_isBn ? 'জরুরি মাত্রা' : 'Urgency'),
                          const SizedBox(height: 10),
                          _buildUrgencySelector(),
                          const SizedBox(height: 20),
                        ],
                        _sectionLabel(_isBn ? 'অবস্থান' : 'Location'),
                        const SizedBox(height: 10),
                        _buildLocationWidget(),
                        const SizedBox(height: 24),
                        GlassButton(
                          label: _isAdvanceBooking
                              ? (_isBn ? 'উপলব্ধ প্রোভাইডার দেখুন' : 'View available providers')
                              : (_isBn ? 'অনুরোধ পাঠান' : 'Send request'),
                          isLoading: _isSubmitting,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.serviceLabel, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(_isBn ? 'সেবার অনুরোধ' : 'Service request', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _sectionLabel(String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
  );

  // ── Nearby-providers preview map ─────────────────────────────────
  // Shows online providers of this exact serviceKind as pins on a small map,
  // purely so the customer can see whether anyone's around before requesting.
  // No tap-to-book — the actual match still goes through broadcast (nearest-first)
  // or, for advance-booking kinds, the browse-and-confirm screen.
  Widget _buildNearbyProvidersMap() {
    if (_isLoadingNearby) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue)),
        ),
      );
    }

    final count = _nearbyProviders.length;
    final center = _latitude != null && _longitude != null
        ? LatLng(_latitude!, _longitude!)
        : (_nearbyProviders.isNotEmpty
            ? LatLng(_nearbyProviders.first.latitude, _nearbyProviders.first.longitude)
            : const LatLng(23.8103, 90.4125)); // fallback: Dhaka

    final markers = {
      for (final p in _nearbyProviders)
        Marker(
          markerId: MarkerId(p.id),
          position: LatLng(p.latitude, p.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: widget.serviceLabel,
            snippet: p.rating != null ? '⭐ ${p.rating!.toStringAsFixed(1)}' : null,
          ),
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.circle,
              size: 9,
              color: count > 0 ? const Color(0xFF22C55E) : AppColors.textMuted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                count > 0
                    ? (_isBn ? '${_bnDigits(count)} জন এখন অনলাইন আছেন — কাছেরজনের কাছে অনুরোধ যাবে' : '$count online now — the request goes to the nearest one')
                    : (_isBn ? 'এই মুহূর্তে কেউ অনলাইন নেই — অনুরোধ পাঠালে অপেক্ষা করতে হতে পারে' : 'No one is online right now — sending a request may mean a wait'),
                style: TextStyle(
                  color: count > 0 ? const Color(0xFF067A57) : AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 160,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: 12.5),
              markers: markers,
              myLocationEnabled: _latitude != null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
        ),
      ],
    );
  }

  // ── Caregiver-only fields ─────────────────────────────────────────

  Widget _buildPatientFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _patientConditionCtrl,
          maxLines: 2,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: _isBn ? 'রোগীর সমস্যা/অসুখ কী?' : "What's the patient's condition?",
            prefixIcon: const Icon(Icons.medical_information_rounded, color: AppColors.textMuted, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _patientAgeCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: _isBn ? 'রোগীর বয়স' : "Patient's age",
            prefixIcon: const Icon(Icons.cake_rounded, color: AppColors.textMuted, size: 20),
          ),
        ),
      ],
    );
  }

  // Two-segment toggle — same visual pattern as match_requests_inbox_screen.dart's
  // _buildModeToggle(): deepBlue-filled active side, glassWhite inactive side.
  Widget _buildCaregiverModeToggle() {
    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _caregiverBookingMode = 'now'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _caregiverBookingMode == 'now' ? AppColors.deepBlue : AppColors.glassWhite,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              _isBn ? 'এখনই দরকার' : 'Need it now',
              style: TextStyle(
                color: _caregiverBookingMode == 'now' ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _caregiverBookingMode = 'schedule'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _caregiverBookingMode == 'schedule' ? AppColors.deepBlue : AppColors.glassWhite,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              _isBn ? 'পরে বুকিং' : 'Pre-book for later',
              style: TextStyle(
                color: _caregiverBookingMode == 'schedule' ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Future<void> _pickCaregiverDateRange() async {
    final now = DateTime.now();
    final initialRange = (_eventDate != null && _eventEndDate != null)
        ? DateTimeRange(start: _eventDate!, end: _eventEndDate!)
        : null;
    final range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: initialRange,
    );
    if (range == null || !mounted) return;
    setState(() {
      _eventDate = range.start;
      _eventEndDate = range.end;
    });
  }

  Widget _buildCaregiverDateRangePicker() {
    final hasRange = _eventDate != null && _eventEndDate != null;
    final label = hasRange
        ? '${_formatDateOnly(_eventDate!)}  →  ${_formatDateOnly(_eventEndDate!)}'
        : (_isBn ? 'শুরু ও শেষের তারিখ বেছে নিন' : 'Choose start and end date');
    return GestureDetector(
      onTap: _pickCaregiverDateRange,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasRange ? AppColors.deepBlue : AppColors.glassBorder,
            width: hasRange ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range_rounded, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: hasRange ? AppColors.textPrimary : AppColors.textMuted,
                  fontSize: 13.5,
                  fontWeight: hasRange ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Shared: provider gender preference (caregiver + advance-booking kinds) ──
  // Self-declared/informational only — see backend doc comment on providerGenderPreference.
  static const _genderOptions = [
    ('any', 'পছন্দ নেই', 'No preference'),
    ('male', 'পুরুষ', 'Male'),
    ('female', 'নারী', 'Female'),
  ];

  Widget _buildGenderPreferenceChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _genderOptions.map((option) {
        final (value, labelBn, labelEn) = option;
        final isSelected = _providerGenderPreference == value;
        return GestureDetector(
          onTap: () => setState(() => _providerGenderPreference = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              gradient: isSelected ? AppColors.blueGradient : null,
              color: isSelected ? null : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? AppColors.deepBlue : AppColors.glassBorder, width: isSelected ? 1.5 : 1),
            ),
            child: Text(
              _isBn ? labelBn : labelEn,
              style: TextStyle(
                color: isSelected ? AppColors.ivory : AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Ride: destination + vehicle ─────────────────────────────────

  Widget _buildDestinationCard() {
    final picked = _dropLatitude != null && _dropLongitude != null;
    return GestureDetector(
      onTap: _pickDestination,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: picked ? AppColors.deepBlue : AppColors.glassBorder,
            width: picked ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(picked ? Icons.flag_rounded : Icons.add_location_alt_outlined,
                color: picked ? AppColors.deepBlue : AppColors.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    picked
                        ? (_dropAddress ??
                            '${_dropLatitude!.toStringAsFixed(4)}, ${_dropLongitude!.toStringAsFixed(4)}')
                        : (_isBn ? 'ম্যাপে গন্তব্য দেখিয়ে দিন' : 'Pick your destination on the map'),
                    style: TextStyle(
                      color: picked ? AppColors.textPrimary : AppColors.textMuted,
                      fontSize: 13.5,
                      fontWeight: picked ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (picked && _rideDistanceKm != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      _isBn
                          ? 'প্রায় ${_rideDistanceKm!.toStringAsFixed(1)} কিমি'
                          : 'About ${_rideDistanceKm!.toStringAsFixed(1)} km',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            Icon(picked ? Icons.edit_rounded : Icons.chevron_right_rounded,
                color: AppColors.deepBlue, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: kRideVehicleTypes.map((type) {
            final isSelected = _vehicleType == type;
            final fare = _fareFor(type);
            final icon = switch (type) {
              'motorcycle' => Icons.two_wheeler_rounded,
              'cng' => Icons.electric_rickshaw_rounded,
              _ => Icons.directions_car_filled_rounded,
            };
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _vehicleType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      gradient: isSelected ? AppColors.blueGradient : null,
                      color: isSelected ? null : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? AppColors.deepBlue : AppColors.glassBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(icon,
                            color: isSelected ? AppColors.ivory : AppColors.textSecondary, size: 22),
                        const SizedBox(height: 5),
                        Text(
                          _isBn ? kRideVehicleLabelsBn[type]! : kRideVehicleLabelsEn[type]!,
                          style: TextStyle(
                            color: isSelected ? AppColors.ivory : AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fare != null ? '৳${fare.round()}' : '—',
                          style: TextStyle(
                            color: isSelected ? AppColors.ivory : AppColors.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_loadingRideRates) ...[
          const SizedBox(height: 8),
          const Text('...', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ] else if (_rideDistanceKm == null) ...[
          const SizedBox(height: 8),
          Text(
            _isBn
                ? 'গন্তব্য বেছে নিলে ভাড়া দেখা যাবে'
                : 'Pick a destination to see the fare',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            _isBn
                ? 'আনুমানিক ভাড়া — চাহিদা বেশি থাকলে সামান্য বাড়তে পারে'
                : 'Estimated fare — may rise slightly during high demand',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  // ── Advance-booking pickers ─────────────────────────────────────

  Future<void> _pickEventDate() async {
    final now = DateTime.now();
    final initialDate = _eventDate ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now) ? now : initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final initialTime = TimeOfDay.fromDateTime(_eventDate ?? initialDate);
    final time = await showTimePicker(context: context, initialTime: initialTime);
    if (time == null || !mounted) return;
    setState(() {
      _eventDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Widget _buildEventDatePicker() {
    final label = _eventDate == null
        ? (_isBn ? 'তারিখ ও সময় বেছে নিন' : 'Choose date and time')
        : _formatEventDate(_eventDate!);
    return GestureDetector(
      onTap: _pickEventDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _eventDate == null ? AppColors.glassBorder : AppColors.deepBlue,
            width: _eventDate == null ? 1 : 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _eventDate == null ? AppColors.textMuted : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: _eventDate == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationPicker() {
    void bump(int delta) {
      final next = (_durationHours + delta).clamp(1, 24);
      setState(() => _durationHours = next);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          _stepButton(icon: Icons.remove_rounded, onTap: () => bump(-1)),
          Expanded(
            child: Text(
              _isBn ? '$_durationHours ঘণ্টা' : '$_durationHours hours',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stepButton(icon: Icons.add_rounded, onTap: () => bump(1), primary: true),
        ],
      ),
    );
  }

  Widget _stepButton({required IconData icon, required VoidCallback onTap, bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: primary ? AppColors.blueGradient : null,
          color: primary ? null : AppColors.deepBlue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: primary ? AppColors.ivory : AppColors.textPrimary, size: 18),
      ),
    );
  }

  static const _bnMonths = [
    'জানু', 'ফেব', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
    'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
  ];
  static const _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatEventDate(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final month = (_isBn ? _bnMonths : _enMonths)[d.month - 1];
    return '${d.day} $month ${d.year}, $hh:$mm';
  }

  // Caregiver date-range — a day, not a moment, so no time-of-day in the label.
  String _formatDateOnly(DateTime d) {
    final month = (_isBn ? _bnMonths : _enMonths)[d.month - 1];
    return '${d.day} $month ${d.year}';
  }

  Widget _buildDescriptionSection() {
    if (_isLoadingIssues) {
      return const SizedBox(
        height: 48,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))),
      );
    }

    // Fallback: no commonIssues from API
    if (_commonIssues.isEmpty) {
      return _buildFallbackTextField();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _commonIssues.map((issue) {
            final isSelected = _selectedIssue == issue;
            final isCustom = issue == _customLabel;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedIssue = issue;
                if (!isCustom) _customController.clear();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.blueGradient : null,
                  color: isSelected ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.deepBlue : AppColors.glassBorder,
                    width: isSelected ? 2 : 1.5,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: AppColors.deepBlue.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCustom)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.edit_rounded, size: 13, color: isSelected ? Colors.white : AppColors.textMuted),
                      ),
                    Text(
                      _issueLabel(issue),
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_selectedIssue == _customLabel) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _customController,
            maxLines: 4,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            autofocus: true,
            decoration: InputDecoration(
              hintText: _isBn ? 'সমস্যার বিস্তারিত বিবরণ লিখুন...' : 'Describe the issue in detail...',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 60),
                child: Icon(Icons.notes_rounded, color: AppColors.textMuted, size: 20),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFallbackTextField() {
    return TextFormField(
      controller: _customController,
      maxLines: 4,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: const InputDecoration(
        hintText: 'সমস্যার বিস্তারিত বিবরণ লিখুন...',
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: 60),
          child: Icon(Icons.notes_rounded, color: AppColors.textMuted, size: 20),
        ),
      ),
    );
  }

  // Two-level specialization picker: Step 1 = 5 group tiles, Step 2 = types of
  // the picked group as chips. Sends only the chosen type's code as
  // `specialization` on POST /dispatch/jobs. Coexists with taskCategory —
  // specialization is WHO fixes it, taskCategory is the PRICE.
  Widget _buildSpecializationSection() {
    if (_isLoadingSpecs) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue),
          ),
        ),
      );
    }
    final tax = _specTaxonomy;
    if (tax == null || tax.tree.isEmpty) return const SizedBox.shrink();

    if (_selectedSpecGroup == null) {
      return _buildSpecGroupTiles(tax);
    }
    final node = tax.tree.firstWhere(
      (n) => n.group.code == _selectedSpecGroup,
      orElse: () => tax.tree.first,
    );
    return _buildSpecTypesStep(node);
  }

  Widget _buildSpecGroupTiles(TechnicianSpecializationTaxonomy tax) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: tax.tree.map((n) {
        final g = n.group;
        return GestureDetector(
          onTap: () => setState(() {
            _selectedSpecGroup = g.code;
            _selectedSpecType = null;
            _onlineTechCount = null;
            // Category chips are group-filtered — drop a pick that no longer applies.
            final allowed = taskCategoriesForSpecGroup(g.code);
            if (_selectedCategory != null && !allowed.contains(_selectedCategory)) {
              _selectedCategory = null;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    gradient: AppColors.blueGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(technicianSpecIcon(g.icon), color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isBn ? g.bn : g.en,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isBn ? '${n.types.length} টি বিকল্প' : '${n.types.length} options',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSpecTypesStep(TechnicianSpecTreeNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumb / back to group picker.
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _selectedSpecGroup = null;
                _selectedSpecType = null;
                _onlineTechCount = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textMuted, size: 14),
                    const SizedBox(width: 6),
                    Icon(technicianSpecIcon(node.group.icon),
                        color: AppColors.deepBlue, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      _isBn ? node.group.bn : node.group.en,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: node.types.map((t) {
            final isSelected = _selectedSpecType == t.code;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSpecType = t.code;
                  // The category chips are filtered by specialization — a pick made
                  // under the old specialization may not exist in the new list.
                  final allowed = taskCategoriesForSpecialization(t.code);
                  if (_selectedCategory != null && !allowed.contains(_selectedCategory)) {
                    _selectedCategory = null;
                  }
                });
                _scheduleCountRefresh();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.blueGradient : null,
                  color: isSelected ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.deepBlue
                        : AppColors.glassBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected) ...[
                      const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      _isBn ? t.bn : t.en,
                      style: TextStyle(
                        color:
                            isSelected ? Colors.white : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOnlineTechBadge() {
    final count = _onlineTechCount;
    if (count == null) return const SizedBox.shrink();
    final typeLabel = _specTaxonomy?.typeLabel(_selectedSpecType ?? '', _isBn) ?? '';
    if (count == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x14D98A0B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x40D98A0B)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB27107)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isBn
                  ? 'এই মুহূর্তে এই কাজের কোনো টেকনিশিয়ান অনলাইন নেই — অনুরোধ পাঠালে অপেক্ষা করতে হতে পারে।'
                  : 'No technician for this job is online right now — sending the request may mean a wait.',
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
            width: 8, height: 8,
            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            _isBn
                ? '${_bnDigits(count)} জন ${typeLabel.isNotEmpty ? '$typeLabel ' : ''}টেকনিশিয়ান অনলাইন'
                : '$count ${typeLabel.isNotEmpty ? '$typeLabel ' : ''}technician${count == 1 ? '' : 's'} online',
            style: const TextStyle(
                color: Color(0xFF067A57), fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    ]);
  }

  static String _bnDigits(int n) =>
      n.toString().split('').map((d) => '০১২৩৪৫৬৭৮৯'[int.parse(d)]).join();

  /// Rates narrowed to what makes sense for the customer's pick — a car owner
  /// must never be offered এসি সার্ভিস or বেবি সিটিং. Filtering kicks in at the
  /// GROUP tile already (গাড়ি ও যানবাহন → only vehicle job types) and narrows
  /// further once a specific type is picked. Full list only before any pick.
  List<TaskCategoryRate> get _visibleRates {
    if (!_needsSpecialization) return _rates;
    final allowed = _selectedSpecType != null
        ? taskCategoriesForSpecialization(_selectedSpecType)
        : _selectedSpecGroup != null
            ? taskCategoriesForSpecGroup(_selectedSpecGroup)
            : null;
    if (allowed == null) return _rates;
    // If the backend hasn't seeded a rate for a mapped category yet, showing the
    // unfiltered list again would resurrect the nonsense chips — show none instead.
    return _rates.where((r) => allowed.contains(r.taskCategory)).toList();
  }

  // Task-category chips + live platform price. Picking one sets `taskCategory`, which the backend
  // uses to resolve estimatedAmount (and therefore the commission).
  Widget _buildCategorySection() {
    if (_isLoadingRates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))),
      );
    }
    if (_visibleRates.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _visibleRates.map((r) {
            final isSelected = _selectedCategory == r.taskCategory;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = r.taskCategory),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.blueGradient : null,
                  color: isSelected ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.labelBn,
                        style: TextStyle(
                            color: isSelected ? AppColors.ivory : AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('৳${r.fixedPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                            color: isSelected ? AppColors.ivory.withOpacity(0.9) : AppColors.deepBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_selectedRate != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.deepBlue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.deepBlue.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: AppColors.deepBlue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('আনুমানিক ৳${_selectedRate!.fixedPrice.toStringAsFixed(0)}',
                          style: const TextStyle(color: AppColors.deepBlue, fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        'ভিজিটিং ফি ৳${_selectedRate!.visitingFee.toStringAsFixed(0)} • কিছু টেকনিশিয়ান কাজ দেখে দাম দেবেন, আপনি অনুমোদন করবেন',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Errand chips (ওষুধ আনা, বাজার, ব্যাংক লাইন…) for কাজের লোক.
  Widget _buildRunnerCategorySection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _runnerCategories.map((c) {
        final code = c['code'] as String;
        final label = (c['labelBn'] ??
                c['label'] ??
                code)
            .toString();
        final isSelected = _selectedRunnerCode == code;
        return GestureDetector(
          onTap: () => setState(() => _selectedRunnerCode = code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            decoration: BoxDecoration(
              gradient: isSelected ? AppColors.blueGradient : null,
              color: isSelected ? null : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
            ),
            child: Text(label,
                style: TextStyle(
                    color: isSelected ? AppColors.ivory : AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUrgencySelector() {
    return Row(
      children: _urgencyOptions.map((option) {
        final (value, labelBn, labelEn) = option;
        final label = _isBn ? labelBn : labelEn;
        final isSelected = _urgencyLevel == value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: value != 'emergency' ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() => _urgencyLevel = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.blueGradient : null,
                  color: isSelected ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
                  boxShadow: isSelected ? [BoxShadow(color: AppColors.deepBlue.withOpacity(0.3), blurRadius: 8)] : null,
                ),
                child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: isSelected ? AppColors.ivory : AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLocationWidget() {
    if (_isLocating) {
      return Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue)),
        const SizedBox(width: 10),
        Text(_isBn ? '📍 বর্তমান অবস্থান নেওয়া হচ্ছে...' : '📍 Getting your location...', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]);
    }
    if (_locationDetected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_pin, color: Color(0xFF22C55E), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_isBn ? 'বর্তমান অবস্থান শনাক্ত হয়েছে' : 'Current location detected', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  _address ?? '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            GestureDetector(onTap: _detectLocation, child: const Icon(Icons.refresh_rounded, color: AppColors.deepBlue, size: 18)),
          ],
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
        child: Row(children: [
          const Icon(Icons.location_off_rounded, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_isBn ? 'অবস্থান পাওয়া যায়নি' : 'Location not found', style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
          GestureDetector(onTap: _detectLocation, child: const Icon(Icons.refresh_rounded, color: AppColors.deepBlue, size: 18)),
        ]),
      ),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: _pickOnMap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.deepBlue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.deepBlue.withOpacity(0.4), width: 1.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.map_rounded, color: AppColors.deepBlue, size: 18),
            const SizedBox(width: 8),
            Text(_isBn ? 'ম্যাপে দেখিয়ে দিন' : 'Pick on map', style: const TextStyle(color: AppColors.deepBlue, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    ]);
  }
}
