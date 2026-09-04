import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/dispatch_model.dart';
import '../services/alarm_notification_service.dart';
import '../services/commute_service.dart';
import '../services/dispatch_service.dart';
import '../theme/status_colors.dart';
import '../widgets/provider_completeness_gate.dart';
import 'active_job_screen.dart';

/// Map-first driver screen — the Uber/Pathao shape.
///
/// The generic provider dashboard is a list of cards, which is right for a technician or a
/// lawyer but wrong for someone sitting on a bike waiting for a fare: a driver needs to see
/// WHERE they are, go online without hunting through a menu, and judge an incoming ride by
/// its pickup distance and fare in one glance.
///
/// Deliberately NOT a replacement for that dashboard — it is the commute-specific view. Once a
/// ride is accepted this hands off to ActiveJobScreen, which already owns the trip lifecycle
/// (route, navigation, start/complete OTP, photo proof).
class DriverModeScreen extends StatefulWidget {
  const DriverModeScreen({super.key});

  @override
  State<DriverModeScreen> createState() => _DriverModeScreenState();
}

class _DriverModeScreenState extends State<DriverModeScreen> {
  GoogleMapController? _map;
  Position? _pos;
  bool _isOnline = false;
  bool _busy = false;
  bool _checkingSession = true;
  String? _userId;
  String? _vehicleType;

  List<JobOffer> _offers = [];
  JobModel? _activeJob;
  Timer? _pollTimer;
  Timer? _locTimer;

  /// Offers already announced — stops the alarm re-ringing every 5s poll for the same ride.
  final Set<String> _alerted = {};

  static const _dhaka = LatLng(23.8103, 90.4125);

  bool get _isBn => context.read<LanguageNotifier>().isBengali;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locTimer?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await _locate();
    // The backend session is the source of truth — a driver who went online, closed the app and
    // came back is still online server-side, so never render a confident "offline" first.
    try {
      final s = await DispatchService.instance.getMySession();
      if (mounted && s.isActive) {
        setState(() => _isOnline = true);
        _startPolling();
      }
    } catch (_) {
      // No live session — genuinely offline.
    }
    if (mounted) setState(() => _checkingSession = false);
  }

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final p = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _pos = p);
      _map?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 15));
    } catch (_) {
      // Map falls back to the Dhaka default; going online re-checks and blocks if still absent.
    }
  }

  // ── Online / offline ────────────────────────────────────────────

  Future<void> _toggleOnline() async {
    if (_userId == null) return;
    setState(() => _busy = true);
    try {
      if (_isOnline) {
        await DispatchService.instance.endSession(providerId: _userId!);
        DispatchService.instance.stopLocationTracking();
        _pollTimer?.cancel();
        _locTimer?.cancel();
        if (mounted) {
          setState(() {
            _isOnline = false;
            _offers = [];
            _activeJob = null;
          });
        }
        return;
      }

      if (!await ensureProviderCompleteness(context, _isBn)) return;

      await _locate();
      if (_pos == null) {
        _snack(
          _isBn
              ? 'লোকেশন ছাড়া অনলাইন হওয়া যাবে না — GPS চালু করুন'
              : 'Location is required to go online — turn on GPS',
          error: true,
        );
        return;
      }

      final vehicle = await _resolveVehicle();
      if (vehicle == null) return;

      await DispatchService.instance.startSession(
        providerId: _userId!,
        serviceKinds: const ['commute'],
        currentLatitude: _pos!.latitude,
        currentLongitude: _pos!.longitude,
        // Vehicle type IS the broadcast filter — a ride only reaches drivers whose session
        // lists the vehicle the passenger asked for.
        specializations: [vehicle],
      );
      if (!mounted) return;
      setState(() {
        _isOnline = true;
        _vehicleType = vehicle;
      });
      DispatchService.instance.startLocationTracking();
      _startPolling();
    } catch (e) {
      _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Vehicle comes from the commute profile; ask once when it is missing or is legacy free text.
  Future<String?> _resolveVehicle() async {
    final colors = Theme.of(context).colorScheme;
    if (_vehicleType != null) return _vehicleType;
    String? stored;
    try {
      final p = await CommuteService.instance.getMyProfile();
      stored = (p['vehicleType'] as String?)?.trim().toLowerCase();
    } catch (_) {
      // Fall through to the picker rather than blocking go-online on a profile fetch.
    }
    if (stored != null && kRideVehicleTypes.contains(stored)) return stored;

    if (!mounted) return null;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          _isBn ? 'আপনি কী চালান?' : 'What do you drive?',
          style: TextStyle(color: colors.onSurface, fontSize: 17),
        ),
        content: Text(
          _isBn
              ? 'যাত্রী যে বাহন চান, সেই বাহনের চালকদের কাছেই রাইড যায়।'
              : 'Rides only reach drivers with the vehicle the passenger asked for.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        // A dialog action per class was fine with three; with six it needs the
        // requirement spelled out, or a driver cannot tell Bike from Bike Plus.
        actions: [
          for (final t in kRideVehicleTypes)
            TextButton(
              onPressed: () => Navigator.pop(ctx, t),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isBn ? kRideVehicleLabelsBn[t]! : kRideVehicleLabelsEn[t]!,
                      style: TextStyle(
                          color: colors.primary, fontWeight: FontWeight.w700),
                    ),
                    if (_isBn && kRideVehicleHintBn[t] != null)
                      Text(
                        kRideVehicleHintBn[t]!,
                        style: TextStyle(
                            color: colors.outline, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return null;
    try {
      await CommuteService.instance.upsertMyProfile(vehicleType: picked);
    } catch (_) {
      // A failed save just means they get asked again next time.
    }
    return picked;
  }

  // ── Polling ─────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    _poll();
    // Keep the driver's own marker moving while they wait, independent of the session ping.
    _locTimer?.cancel();
    _locTimer = Timer.periodic(const Duration(seconds: 15), (_) => _locate());
  }

  Future<void> _poll() async {
    try {
      final jobs =
          await DispatchService.instance.listJobs(assignedProviderId: _userId);
      const live = {'assigned', 'accepted', 'arriving', 'in_progress'};
      final active = jobs
          .where((j) => j.serviceKind == 'commute' && live.contains(j.status))
          .toList();
      if (!mounted) return;

      if (active.isNotEmpty) {
        // On a trip — stop advertising new rides.
        setState(() {
          _activeJob = active.first;
          _offers = [];
        });
        return;
      }
      setState(() => _activeJob = null);

      final offers = (await DispatchService.instance.getMyOffers())
          .where((o) => o.job.serviceKind == 'commute')
          .toList();
      if (!mounted) return;
      setState(() => _offers = offers);

      final fresh =
          offers.where((o) => !_alerted.contains(o.assignmentId)).toList();
      if (fresh.isNotEmpty) {
        _alerted.addAll(fresh.map((o) => o.assignmentId));
        AlarmNotificationService.instance.startRinging(
          title: _isBn ? 'নতুন রাইডের অনুরোধ' : 'New ride request',
          body: fresh.first.job.dropoffAddressSnapshot ??
              (_isBn ? 'গ্রহণ করতে ট্যাপ করুন' : 'Tap to accept'),
          payload: fresh.first.job.id,
        );
      }
    } catch (_) {
      // A dropped poll just retries in 5s.
    }
  }

  Future<void> _respond(JobOffer offer, String response) async {
    AlarmNotificationService.instance.stopRinging();
    setState(() => _offers =
        _offers.where((o) => o.assignmentId != offer.assignmentId).toList());
    try {
      await DispatchService.instance.respondToAssignment(
        offer.assignmentId,
        response: response,
        jobId: offer.job.id,
      );
      if (!mounted || response != 'accepted') return;
      setState(() => _activeJob = offer.job);
      _openTrip(offer.job);
    } catch (e) {
      _snack(ApiClient.mapError(e).localized(_isBn), error: true);
      _poll();
    }
  }

  Future<void> _openTrip(JobModel job) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => ActiveJobScreen(job: job, onJobCompleted: _poll)),
    );
    _poll();
  }

  Future<void> _navigateTo(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack(_isBn ? 'ম্যাপ খোলা যায়নি' : 'Could not open maps', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? colors.error : colors.primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Map layers ──────────────────────────────────────────────────

  /// The job whose route is worth drawing: the trip in progress, else the offer on screen.
  JobModel? get _focusJob =>
      _activeJob ?? (_offers.isNotEmpty ? _offers.first.job : null);

  Set<Marker> _markers() {
    final m = <Marker>{};
    if (_pos != null) {
      m.add(Marker(
        markerId: const MarkerId('me'),
        position: LatLng(_pos!.latitude, _pos!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: _isBn ? 'আপনি' : 'You'),
      ));
    }
    final job = _focusJob;
    if (job != null) {
      m.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(job.pickupLatitude, job.pickupLongitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: _isBn ? 'যাত্রী' : 'Passenger'),
      ));
      if (job.isRide) {
        m.add(Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(job.dropoffLatitude!, job.dropoffLongitude!),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: _isBn ? 'গন্তব্য' : 'Destination'),
        ));
      }
    }
    return m;
  }

  Set<Polyline> _lines() {
    final colors = Theme.of(context).colorScheme;
    final job = _focusJob;
    if (job == null || !job.isRide) return const {};
    // Prefer the real driving route Directions returned at quote time; fall back to a straight
    // dashed line only when routing was unavailable, so the map never silently implies a road
    // that doesn't exist.
    final encoded = job.rideDetail?.routePolyline;
    final decoded = (encoded != null && encoded.isNotEmpty) ? decodePolyline(encoded) : const <List<double>>[];
    final hasRoute = decoded.length > 1;
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: hasRoute
            ? decoded.map((p) => LatLng(p[0], p[1])).toList()
            : [
                LatLng(job.pickupLatitude, job.pickupLongitude),
                LatLng(job.dropoffLatitude!, job.dropoffLongitude!),
              ],
        color: colors.primary,
        width: hasRoute ? 5 : 4,
        patterns: hasRoute ? const [] : [PatternItem.dash(18), PatternItem.gap(10)],
      ),
    };
  }

  // ── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target:
                  _pos != null ? LatLng(_pos!.latitude, _pos!.longitude) : _dhaka,
              zoom: 15,
            ),
            onMapCreated: (c) => _map = c,
            markers: _markers(),
            polylines: _lines(),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(isBn),
                const Spacer(),
                if (_activeJob != null)
                  _buildActiveTripCard(_activeJob!, isBn)
                else if (_offers.isNotEmpty)
                  _buildOfferCard(_offers.first, isBn)
                else
                  _buildStatusCard(isBn),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isBn) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: colors.onSurface, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _checkingSession
                  ? colors.outline
                  : (_isOnline ? const Color(0xFF22C55E) : colors.outline),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _checkingSession
                ? (isBn ? 'দেখা হচ্ছে…' : 'Checking…')
                : (_isOnline
                    ? (isBn ? 'অনলাইন' : 'Online')
                    : (isBn ? 'অফলাইন' : 'Offline')),
            style: TextStyle(
                color: colors.onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w700),
          ),
          if (_isOnline && _vehicleType != null) ...[
            const SizedBox(width: 8),
            Text(
              isBn
                  ? kRideVehicleLabelsBn[_vehicleType]!
                  : kRideVehicleLabelsEn[_vehicleType]!,
              style: TextStyle(color: colors.outline, fontSize: 12),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: Icon(Icons.my_location_rounded,
                color: colors.primary, size: 20),
            onPressed: _locate,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isBn) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isOnline
                ? (isBn ? 'রাইডের অপেক্ষায়…' : 'Waiting for rides…')
                : (isBn ? 'অনলাইন হলে রাইড পাবেন' : 'Go online to receive rides'),
            style: TextStyle(
                color: colors.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _isOnline
                ? (isBn
                    ? 'কাছাকাছি কেউ রাইড চাইলে এখানেই দেখা যাবে'
                    : 'Nearby ride requests will appear here')
                : (isBn
                    ? 'অনলাইন থাকলে আপনার বাহনের রাইড আপনার কাছে আসবে'
                    : 'While online, rides for your vehicle come to you'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: colors.outline, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _toggleOnline,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isOnline ? colors.error : colors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Text(
                      _isOnline
                          ? (isBn ? 'অফলাইন হন' : 'Go offline')
                          : (isBn ? 'অনলাইন হন' : 'Go online'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(JobOffer offer, bool isBn) {
    final colors = Theme.of(context).colorScheme;
    final job = offer.job;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: colors.primary.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isBn ? 'নতুন রাইড' : 'New ride',
                  style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              if (job.estimatedAmount != null)
                Text('৳${job.estimatedAmount!.round()}',
                    style: TextStyle(
                        color: colors.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          _pointRow(
              Icons.trip_origin_rounded,
              const Color(0xFF22C55E),
              job.pickupAddressSnapshot ??
                  (isBn ? 'যাত্রীর অবস্থান' : 'Passenger location')),
          const SizedBox(height: 6),
          _pointRow(Icons.flag_rounded, StatusColors.amber,
              job.dropoffAddressSnapshot ?? (isBn ? 'গন্তব্য' : 'Destination')),
          const SizedBox(height: 10),
          Row(
            children: [
              if (offer.distanceKm != null) ...[
                Icon(Icons.directions_walk_rounded,
                    size: 15, color: colors.outline),
                const SizedBox(width: 4),
                Text(
                  isBn
                      ? '${offer.distanceKm!.toStringAsFixed(1)} কিমি দূরে'
                      : '${offer.distanceKm!.toStringAsFixed(1)} km away',
                  style: TextStyle(
                      color: colors.onSurfaceVariant, fontSize: 12.5),
                ),
                const SizedBox(width: 14),
              ],
              if (job.distanceKm != null) ...[
                Icon(Icons.route_rounded,
                    size: 15, color: colors.outline),
                const SizedBox(width: 4),
                Text(
                  isBn
                      ? 'যাত্রা ${job.distanceKm!.toStringAsFixed(1)} কিমি'
                      : 'Trip ${job.distanceKm!.toStringAsFixed(1)} km',
                  style: TextStyle(
                      color: colors.onSurfaceVariant, fontSize: 12.5),
                ),
              ],
              if (job.rideDetail?.durationMinutes != null) ...[
                const SizedBox(width: 14),
                Icon(Icons.schedule_rounded,
                    size: 15, color: colors.outline),
                const SizedBox(width: 4),
                Text(
                  '~${job.rideDetail!.durationMinutes} ${isBn ? 'মিনিট' : 'min'}',
                  style: TextStyle(
                      color: colors.onSurfaceVariant, fontSize: 12.5),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respond(offer, 'rejected'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.outlineVariant),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(isBn ? 'বাদ দিন' : 'Skip',
                      style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _respond(offer, 'accepted'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(isBn ? 'রাইড নিন' : 'Accept ride',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTripCard(JobModel job, bool isBn) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isBn ? 'চলমান রাইড' : 'Active ride',
                  style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              if (job.estimatedAmount != null)
                Text('৳${job.estimatedAmount!.round()}',
                    style: TextStyle(
                        color: colors.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          _pointRow(
              Icons.trip_origin_rounded,
              const Color(0xFF22C55E),
              job.pickupAddressSnapshot ??
                  (isBn ? 'যাত্রীর অবস্থান' : 'Passenger location')),
          const SizedBox(height: 6),
          _pointRow(Icons.flag_rounded, StatusColors.amber,
              job.dropoffAddressSnapshot ?? (isBn ? 'গন্তব্য' : 'Destination')),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Before the trip starts navigate to the passenger; after that, to the
                    // destination — otherwise the driver has to work out which end they need.
                    final toDest = job.status == 'in_progress' && job.isRide;
                    _navigateTo(
                      toDest ? job.dropoffLatitude! : job.pickupLatitude,
                      toDest ? job.dropoffLongitude! : job.pickupLongitude,
                    );
                  },
                  icon: Icon(Icons.navigation_rounded,
                      size: 17, color: colors.primary),
                  label: Text(isBn ? 'নেভিগেট' : 'Navigate',
                      style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _openTrip(job),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(isBn ? 'রাইড পরিচালনা' : 'Manage ride',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pointRow(IconData icon, Color color, String text) {
    final colors = Theme.of(context).colorScheme;
    return Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: colors.onSurface, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
  }
}
