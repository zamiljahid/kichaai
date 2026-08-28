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

  // Baby sitting is a Quick Help errand, but the backend needs a BabySittingDetails row
  // alongside the job — it marks those categories with requiresBabySittingDetails and
  // exposes a separate create endpoint. The picker used to ignore that flag, so choosing
  // "বেবি সিটিং" made an ordinary job with no child details attached at all.
  final _childAgeCtrl = TextEditingController();
  final _childCountCtrl = TextEditingController(text: '1');
  final _allergiesCtrl = TextEditingController();
  final _sittingNotesCtrl = TextEditingController();
  int _sittingHours = 4;
  String _sittingLocation = 'AT_HOME';
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

  /// True when the chosen errand is one the backend flags as needing child details.
  bool get _needsBabySittingDetails {
    if (_selectedRunnerCode == null) return false;
    for (final c in _runnerCategories) {
      if (c['code'] == _selectedRunnerCode) {
        return c['requiresBabySittingDetails'] == true;
      }
    }
    return false;
  }

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

  /// Server-computed fare + availability preview, refreshed whenever pickup or destination
  /// moves. The app used to do this arithmetic itself and silently omit the surge multiplier,
  /// so a surging ride was quoted below what createJob then charged — now there is exactly one
  /// pricing implementation, on the server, and this only displays it.
  RideQuoteModel? _rideQuote;
  bool _loadingRideQuote = false;
  int _quoteSeq = 0; // guards against out-of-order quote responses

  GoogleMapController? _rideMapController;

  /// 'cash' | 'online'. Cash stays the default — it is how most rides will actually be paid —
  /// but the choice is now made before the request rather than after a driver accepts.
  String _paymentMethod = 'cash';

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
    // Nothing ride-specific to preload: the fare quote needs a destination, which does not
    // exist yet, and the nearby-driver fetch below already runs for every kind.
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

  /// Quick Help baby sitting goes to its own endpoint so a BabySittingDetails row is
  /// created with the job; everything else about the flow (broadcast, tracking) is identical.
  Future<void> _submitBabySitting(int childAge) async {
    final lat = _latitude;
    final lng = _longitude;
    if (lat == null || lng == null) {
      _showError(_isBn ? 'অবস্থান নির্ধারণ করুন — ম্যাপে দেখিয়ে দিন' : 'Set your location — pick it on the map');
      return;
    }
    final token = await ApiClient.getAccessToken();
    final customerId = token != null ? decodeJwtSub(token) : null;
    if (customerId == null) {
      _showError(_isBn ? 'লগইন তথ্য পাওয়া যায়নি' : 'Login information not found');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final res = await DispatchService.instance.createBabySittingTask({
        'serviceTypeId': 'default',
        'title': _selectedRunnerLabel ?? (_isBn ? 'বেবি সিটিং' : 'Baby sitting'),
        'description': _customController.text.trim(),
        'pickupLatitude': lat,
        'pickupLongitude': lng,
        'pickupAddressSnapshot': _address,
        'childAgeYears': childAge,
        'durationHours': _sittingHours,
        'numberOfChildren': int.tryParse(_childCountCtrl.text.trim()) ?? 1,
        'locationType': _sittingLocation,
        if (_allergiesCtrl.text.trim().isNotEmpty) 'allergies': _allergiesCtrl.text.trim(),
        if (_sittingNotesCtrl.text.trim().isNotEmpty)
          'specialInstructions': _sittingNotesCtrl.text.trim(),
      });
      if (!mounted) return;
      final jobId = (res['id'] ?? res['jobId'])?.toString();
      if (jobId == null) {
        _showError(_isBn ? 'অনুরোধ তৈরি হয়নি' : 'The request was not created');
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: jobId)),
      );
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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

  /// Refresh the fare/availability quote. Needs both ends of the trip, so it is a no-op until
  /// pickup and destination are both known, and it clears any stale quote when they aren't.
  /// A failed fetch leaves the quote null rather than blocking the request — the backend still
  /// prices the ride authoritatively at createJob.
  Future<void> _refreshRideQuote() async {
    if (!_isRide) return;
    if (_latitude == null || _longitude == null || _dropLatitude == null || _dropLongitude == null) {
      if (mounted) setState(() => _rideQuote = null);
      return;
    }
    if (!mounted) return;
    final seq = ++_quoteSeq;
    setState(() => _loadingRideQuote = true);
    final quote = await DispatchService.instance.getRideQuote(
      pickupLat: _latitude!,
      pickupLon: _longitude!,
      dropLat: _dropLatitude!,
      dropLon: _dropLongitude!,
    );
    if (!mounted || seq != _quoteSeq) return;
    setState(() {
      _rideQuote = quote;
      _loadingRideQuote = false;
    });
  }

  /// Road-adjusted trip distance, straight from the quote — the same number the fare is
  /// computed from, so the two can never disagree on screen.
  double? get _rideDistanceKm => _rideQuote?.distanceKm;

  /// Switching vehicle re-fetches the driver pins, because the nearby list is scoped to the
  /// chosen vehicle — showing car pins under a bike fare would promise the wrong drivers.
  void _selectVehicle(String type) {
    if (_vehicleType == type) return;
    setState(() => _vehicleType = type);
    _loadNearbyProviders();
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
    // Fare and map both depend on the destination — update them before the address lookup,
    // which is slower and purely cosmetic.
    _refreshRideQuote();
    _fitRideBounds();
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
        // vehicleType is stored in the provider's specializationsSnapshot and is what the
        // broadcast filters on, so scoping the pins by it shows exactly the drivers who would
        // actually receive this ride — not every commute provider in the area.
        specialization: _isRide ? _vehicleType : null,
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
    _childAgeCtrl.dispose();
    _childCountCtrl.dispose();
    _allergiesCtrl.dispose();
    _sittingNotesCtrl.dispose();
    _debounce?.cancel();
    _rideMapController?.dispose();
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
    if (_isRide) {
      _refreshRideQuote();
      _fitRideBounds();
    }
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

    if (_needsBabySittingDetails) {
      final age = int.tryParse(_childAgeCtrl.text.trim());
      if (age == null || age < 0) {
        _showError(_isBn ? 'শিশুর বয়স লিখুন' : "Enter the child's age");
        return;
      }
      await _submitBabySitting(age);
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

    // Same courtesy the specialization flow gives: never fire a request at a vehicle class
    // with nobody online without saying so first. Falls back to the pin list when the quote
    // failed to load, so a dead quote endpoint doesn't suppress the warning entirely.
    if (_isRide) {
      final quoted = _rideQuote?.forVehicle(_vehicleType);
      final nobodyOnline = quoted != null ? !quoted.hasDrivers : _nearbyProviders.isEmpty;
      if (nobodyOnline) {
        final vehicle = _isBn ? kRideVehicleLabelsBn[_vehicleType]! : kRideVehicleLabelsEn[_vehicleType]!;
        final proceed = await _confirmNoOneOnline(
          _isBn
              ? 'এই মুহূর্তে আশেপাশে কোনো $vehicle চালক অনলাইন নেই — অনুরোধ পাঠালে অপেক্ষা করতে হতে পারে।'
              : 'No $vehicle driver is online nearby right now — sending the request may mean a wait.',
        );
        if (proceed != true) return;
      }
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
        paymentMethod: _isRide ? _paymentMethod : null,
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

  Future<bool?> _confirmNoOneOnline([String? message]) {
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
          message ??
              (_isBn
                  ? 'এই মুহূর্তে এই কাজের কোনো টেকনিশিয়ান অনলাইন নেই — অনুরোধ পাঠালে অপেক্ষা করতে হতে পারে।'
                  : 'No technician for this job is online right now — sending the request may mean a wait.'),
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
    // A ride is the one request that is fundamentally about a ROUTE, so it gets a map-first
    // shell (full-bleed map + a control sheet pinned over it) instead of the shared scrolling
    // form. Same state and same _submit path — only the shell differs.
    if (_isRide) return _buildRideScaffold(context);
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
                          if (_needsBabySittingDetails) _buildBabySittingSection(),
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
                        // Destination/vehicle live in the ride sheet now (_buildRideScaffold),
                        // which is why no _isRide branch appears in this form any more — a ride
                        // never reaches this widget at all, urgency section included. Urgency is
                        // meaningless for a ride: "how urgent?" has one answer, now.
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

  // ── Ride: map-first shell ────────────────────────────────────────
  // Everything below belongs to the ride flow only. The rest of this screen keeps the shared
  // scrolling-form layout; a ride never renders it (see the branch in build()).

  IconData _vehicleIcon(String type) => switch (type) {
        'motorcycle' || 'motorcycle_plus' => Icons.two_wheeler_rounded,
        'cng' || 'cng_plus' => Icons.electric_rickshaw_rounded,
        _ => Icons.directions_car_filled_rounded,
      };

  /// Digits in the reader's own script — ৳১২০ reads as a price to a Bengali user, ৳120 reads
  /// as a foreign string sitting inside a Bengali sentence.
  String _num(num n) => _isBn ? _bnDigits(n.round()) : n.round().toString();

  /// Google's default map is full of hospital/park/transit pins that have nothing to do with
  /// booking a ride, and they compete with the pins that DO matter (pickup, destination,
  /// drivers). Strip the noise, keep the roads.
  static const _rideMapStyle = '''
[
  {"featureType": "poi", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "road", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]}
]
''';

  Widget _buildRideScaffold(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          // The map fills the screen; the sheet floats over its lower half. Camera padding
          // keeps the pins in the strip that is actually visible between header and sheet.
          Positioned.fill(child: _buildRideMap(bottomPadding: size.height * 0.42)),
          SafeArea(bottom: false, child: _buildRideHeader(context)),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height * 0.66),
              child: _buildRideSheet(),
            ),
          ),
        ],
      ),
    );
  }

  /// The shared header assumes an opaque page behind it. Over a live map it needs its own
  /// scrim, or the title disappears against pale roads.
  Widget _buildRideHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgDark, AppColors.bgDark.withOpacity(0.0)],
        ),
      ),
      child: _buildHeader(context),
    );
  }

  Widget _buildRideMap({required double bottomPadding}) {
    final pickup = _latitude != null && _longitude != null ? LatLng(_latitude!, _longitude!) : null;
    final drop = _dropLatitude != null && _dropLongitude != null
        ? LatLng(_dropLatitude!, _dropLongitude!)
        : null;

    final markers = <Marker>{
      if (pickup != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: _isBn ? 'যাত্রা শুরু' : 'Pickup', snippet: _address),
        ),
      if (drop != null)
        Marker(
          markerId: const MarkerId('drop'),
          position: drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: _isBn ? 'গন্তব্য' : 'Destination', snippet: _dropAddress),
        ),
      // Drivers of the SELECTED vehicle only — _loadNearbyProviders scopes the fetch by it.
      for (final driver in _nearbyProviders)
        Marker(
          markerId: MarkerId(driver.id),
          position: LatLng(driver.latitude, driver.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: _isBn ? kRideVehicleLabelsBn[_vehicleType]! : kRideVehicleLabelsEn[_vehicleType]!,
            snippet: driver.etaMinutes != null
                ? (_isBn ? '${_num(driver.etaMinutes!)} মিনিট দূরে' : '${driver.etaMinutes} min away')
                : null,
          ),
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: pickup ?? const LatLng(23.8103, 90.4125), // fallback: Dhaka
        zoom: 14,
      ),
      style: _rideMapStyle,
      markers: markers,
      polylines: {
        if (pickup != null && drop != null)
          Polyline(
            polylineId: const PolylineId('route'),
            points: [pickup, drop],
            color: AppColors.deepBlue,
            width: 4,
            // Dashed deliberately: there is no routing API behind this, so a solid line would
            // claim a road-accurate route nobody computed. The fare is the same kind of
            // estimate — straight-line distance scaled to an approximate road distance.
            // (google_maps_flutter_web ignores patterns and draws it solid; Android/iOS, the
            // platforms that actually ship, honour it.)
            patterns: [PatternItem.dash(24), PatternItem.gap(12)],
          ),
      },
      padding: EdgeInsets.only(top: 88, bottom: bottomPadding),
      myLocationEnabled: _latitude != null,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (c) {
        _rideMapController = c;
        _fitRideBounds();
      },
    );
  }

  /// Frame both ends of the trip at once. Without this the camera sits on the pickup and the
  /// destination is off-screen, which is exactly when a customer wants to sanity-check the route.
  Future<void> _fitRideBounds() async {
    final controller = _rideMapController;
    if (controller == null) return;
    if (_latitude == null || _longitude == null) return;
    if (_dropLatitude == null || _dropLongitude == null) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_latitude!, _longitude!), 14));
      return;
    }
    // A zero-area box (destination pinned essentially on top of the pickup) makes
    // newLatLngBounds misbehave, so pad the box out to a minimum span first.
    const minSpan = 0.002; // ~200m
    final latPad = math.max(0.0, (minSpan - (_dropLatitude! - _latitude!).abs()) / 2);
    final lonPad = math.max(0.0, (minSpan - (_dropLongitude! - _longitude!).abs()) / 2);
    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(_latitude!, _dropLatitude!) - latPad,
        math.min(_longitude!, _dropLongitude!) - lonPad,
      ),
      northeast: LatLng(
        math.max(_latitude!, _dropLatitude!) + latPad,
        math.max(_longitude!, _dropLongitude!) + lonPad,
      ),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  Widget _buildRideSheet() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.glassBorder, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRideAvailabilityLine(),
                    const SizedBox(height: 12),
                    _buildRidePickupCard(),
                    const SizedBox(height: 8),
                    _buildDestinationCard(),
                    const SizedBox(height: 18),
                    _sectionLabel(_isBn ? 'বাহন' : 'Vehicle'),
                    const SizedBox(height: 10),
                    _buildVehicleTypeSelector(),
                    const SizedBox(height: 18),
                    _sectionLabel(_isBn ? 'পেমেন্ট' : 'Payment'),
                    const SizedBox(height: 10),
                    _buildRidePaymentSelector(),
                  ],
                ),
              ),
            ),
            // Pinned: the fare and the action must never scroll out of reach.
            _buildRideBottomBar(),
          ],
        ),
      ),
    );
  }

  /// "Is anyone even out there" — scoped to the chosen vehicle once a quote exists, and to the
  /// (already vehicle-filtered) pin list before that.
  Widget _buildRideAvailabilityLine() {
    final quoted = _rideQuote?.forVehicle(_vehicleType);
    final count = quoted?.onlineCount ?? _nearbyProviders.length;
    final vehicle = _isBn ? kRideVehicleLabelsBn[_vehicleType]! : kRideVehicleLabelsEn[_vehicleType]!;
    final surging = _rideQuote?.isSurging ?? false;

    return Row(
      children: [
        Icon(Icons.circle, size: 9, color: count > 0 ? const Color(0xFF22C55E) : AppColors.textMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            count > 0
                ? (_isBn
                    ? '${_num(count)} জন $vehicle চালক কাছাকাছি আছেন'
                    : '$count $vehicle drivers nearby')
                : (_isBn
                    ? 'এই মুহূর্তে কোনো $vehicle চালক অনলাইন নেই'
                    : 'No $vehicle driver is online right now'),
            style: TextStyle(
              color: count > 0 ? const Color(0xFF067A57) : AppColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Surge is the customer's business — it is already inside every fare shown below, so
        // hiding it would make the prices look arbitrary.
        if (surging)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.softAmber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.softAmber.withOpacity(0.4)),
            ),
            child: Text(
              _isBn ? 'চাহিদা বেশি' : 'High demand',
              style: const TextStyle(color: AppColors.softAmber, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  /// Compact pickup row. The shared _buildLocationWidget is a full section with its own labels;
  /// inside the sheet the pickup is one line of a two-line route, so it reads as the first stop.
  Widget _buildRidePickupCard() {
    final detected = _locationDetected && _latitude != null && _longitude != null;
    return GestureDetector(
      onTap: _pickOnMap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: detected ? const Color(0xFF22C55E).withOpacity(0.5) : AppColors.glassBorder,
            width: detected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              detected ? Icons.trip_origin_rounded : Icons.location_off_rounded,
              color: detected ? const Color(0xFF22C55E) : AppColors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isLocating
                    ? (_isBn ? 'অবস্থান নেওয়া হচ্ছে...' : 'Getting your location...')
                    : detected
                        ? (_address ?? '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}')
                        : (_isBn ? 'যাত্রা শুরুর জায়গা দেখিয়ে দিন' : 'Set your pickup point'),
                style: TextStyle(
                  color: detected ? AppColors.textPrimary : AppColors.textMuted,
                  fontSize: 13.5,
                  fontWeight: detected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: _detectLocation,
              child: const Icon(Icons.my_location_rounded, color: AppColors.deepBlue, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTypeSelector() {
    // Three per row. With six classes a single row leaves each chip too narrow to read
    // the fare, which is the whole point of showing them side by side.
    const perRow = 3;
    final rows = <List<String>>[];
    for (var i = 0; i < kRideVehicleTypes.length; i += perRow) {
      rows.add(kRideVehicleTypes.sublist(
          i, (i + perRow).clamp(0, kRideVehicleTypes.length)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
        Row(
          children: row.map((type) {
            final isSelected = _vehicleType == type;
            final quoted = _rideQuote?.forVehicle(type);
            final unavailable = quoted != null && !quoted.hasDrivers;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _selectVehicle(type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                    decoration: BoxDecoration(
                      gradient: isSelected ? AppColors.blueGradient : null,
                      color: isSelected ? null : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? AppColors.deepBlue : AppColors.glassBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Opacity(
                      // Still tappable when nobody drives it — the request is allowed, it just
                      // means waiting — but it should not look like an equal choice.
                      opacity: unavailable && !isSelected ? 0.5 : 1,
                      child: Column(
                        children: [
                          Icon(_vehicleIcon(type),
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
                          // The fare line only exists once there IS a fare. The old placeholder
                          // em-dash under every vehicle just read as broken UI.
                          if (quoted?.fareMin != null && quoted?.fareMax != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              '৳${_num(quoted!.fareMin!)}–${_num(quoted.fareMax!)}',
                              style: TextStyle(
                                color: isSelected ? AppColors.ivory : AppColors.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ] else if (_loadingRideQuote) ...[
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: isSelected ? AppColors.ivory : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          // A ride app sells minutes as much as taka.
                          if (quoted != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              quoted.hasDrivers && quoted.etaMinutes != null
                                  ? (_isBn ? '${_num(quoted.etaMinutes!)} মিনিট' : '${quoted.etaMinutes} min')
                                  : (_isBn ? 'কেউ নেই' : 'None nearby'),
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.ivory.withOpacity(0.85)
                                    : (quoted.hasDrivers ? AppColors.textMuted : AppColors.softAmber),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        ],
        Text(
          _rideQuote == null
              ? (_isBn ? 'গন্তব্য বেছে নিলে ভাড়া দেখা যাবে' : 'Pick a destination to see the fare')
              : (_isBn
                  ? 'আনুমানিক ভাড়া ও সময় — রাস্তার অবস্থাভেদে কিছুটা বদলাতে পারে'
                  : 'Estimated fare and time — road conditions can shift both a little'),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }

  /// Both options are real. Cash is the default and unchanged. Picking online records the
  /// choice on the job, and the moment a driver accepts, the backend puts the job straight into
  /// the existing SSLCommerz flow (bKash / Nagad / card) — the customer just taps pay on the
  /// tracking screen instead of having to find the opt-in card there first.
  Widget _buildRidePaymentSelector() {
    return Row(
      children: [
        Expanded(
          child: _paymentOption(
            value: 'cash',
            icon: Icons.payments_rounded,
            label: _isBn ? 'নগদ' : 'Cash',
            hint: _isBn ? 'রাইড শেষে চালককে' : 'To the driver, after',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _paymentOption(
            value: 'online',
            icon: Icons.account_balance_wallet_rounded,
            label: _isBn ? 'অনলাইন' : 'Online',
            hint: _isBn ? 'বিকাশ / নগদ / কার্ড' : 'bKash / Nagad / card',
          ),
        ),
      ],
    );
  }

  Widget _paymentOption({
    required String value,
    required IconData icon,
    required String label,
    required String hint,
  }) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.glassBlue : AppColors.glassWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.deepBlue : AppColors.glassBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? AppColors.deepBlue : AppColors.textMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? AppColors.deepBlue : AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    hint,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideBottomBar() {
    final hasPickup = _latitude != null && _longitude != null;
    final hasDrop = _dropLatitude != null && _dropLongitude != null;
    final ready = hasPickup && hasDrop;
    final quoted = _rideQuote?.forVehicle(_vehicleType);
    final distance = _rideDistanceKm;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ready && quoted?.fare != null && distance != null) ...[
            Row(
              children: [
                Icon(_vehicleIcon(_vehicleType), color: AppColors.textMuted, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _isBn
                        ? '${_num(distance)} কিমি • প্রায় ৳${_num(quoted!.fare!)}'
                        : '${distance.toStringAsFixed(1)} km • about ৳${_num(quoted!.fare!)}',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // The button is never a dead grey rectangle: when the request isn't ready it becomes
          // the step that WOULD make it ready, so a tap always does something.
          GlassButton(
            label: !hasPickup
                ? (_isBn ? 'যাত্রা শুরুর জায়গা দিন' : 'Set your pickup')
                : !hasDrop
                    ? (_isBn ? 'গন্তব্য বেছে নিন' : 'Choose a destination')
                    : (_isBn ? 'অনুরোধ পাঠান' : 'Send request'),
            isLoading: _isSubmitting,
            color: ready ? null : AppColors.textMuted,
            onPressed: ready
                ? _submit
                : hasPickup
                    ? _pickDestination
                    : _pickOnMap,
          ),
        ],
      ),
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

  /// Child details, revealed only for an errand the backend flags as baby sitting.
  Widget _buildBabySittingSection() {
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          filled: true,
          fillColor: AppColors.glassWhite,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.glassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.glassBorder),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(_isBn ? 'শিশুর তথ্য' : "Child details",
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _childAgeCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: deco(_isBn ? 'বয়স (বছর) *' : 'Age in years *'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _childCountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: deco(_isBn ? 'কতজন শিশু' : 'How many children'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(_isBn ? 'কত ঘণ্টা' : 'For how many hours',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [2, 4, 6, 8].map((h) {
            final sel = _sittingHours == h;
            return GestureDetector(
              onTap: () => setState(() => _sittingHours = h),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: sel ? AppColors.blueGradient : null,
                  color: sel ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
                ),
                child: Text('$h ' + (_isBn ? 'ঘণ্টা' : 'hr'),
                    style: TextStyle(
                        color: sel ? AppColors.ivory : AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Text(_isBn ? 'কোথায়' : 'Where',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 6),
        Row(children: [
          for (final opt in const [
            ('AT_HOME', 'আমার বাসায়', 'At my home'),
            ('AT_SITTER', 'সিটারের বাসায়', "At the sitter's"),
          ]) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _sittingLocation = opt.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    gradient: _sittingLocation == opt.$1 ? AppColors.blueGradient : null,
                    color: _sittingLocation == opt.$1 ? null : AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _sittingLocation == opt.$1
                            ? AppColors.deepBlue
                            : AppColors.glassBorder,
                        width: 1.5),
                  ),
                  child: Text(_isBn ? opt.$2 : opt.$3,
                      style: TextStyle(
                          color: _sittingLocation == opt.$1
                              ? AppColors.ivory
                              : AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _allergiesCtrl,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: deco(_isBn ? 'অ্যালার্জি (থাকলে)' : 'Allergies, if any'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _sittingNotesCtrl,
          maxLines: 2,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: deco(_isBn
              ? 'বিশেষ নির্দেশনা (খাওয়ানো, ঘুম, ওষুধ…)'
              : 'Special instructions (food, nap, medicine…)'),
        ),
      ],
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
