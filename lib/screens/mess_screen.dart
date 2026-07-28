import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/property_model.dart';
import '../theme/app_theme.dart';
import 'post_mess_screen.dart';

// App brand accent (pine) — used for save-heart, host button, price pill, CTA.
const _accent = AppColors.deepBlue;

// ── Screen ────────────────────────────────────────────────────────────────────
class MessScreen extends StatefulWidget {
  const MessScreen({super.key});

  @override
  State<MessScreen> createState() => _MessScreenState();
}

enum _View { list, map }

class _MessScreenState extends State<MessScreen> {
  final _client = ApiClient.instance.dio;
  final _searchCtrl = TextEditingController();
  GoogleMapController? _mapController;

  static const LatLng _dhaka = LatLng(23.8103, 90.4125);

  // মেস-seeker and বাসা-seeker must never see each other's listings — this is
  // always sent to /auth/properties/search.
  String _listingType = 'MESS';

  // Filters — every one of them optional.
  int? _minRent;
  int? _maxRent;
  double _radiusKm = 25;
  String? _gender; // male | female        (MESS: "I am …")
  String? _smoking; // smoker | non_smoker (MESS)
  String? _occupation; // student | job_holder (MESS)
  int? _minBedrooms; // HOUSE: at least N
  String? _tenantType; // family | bachelor (HOUSE)

  List<PropertyListing> _all = [];
  final Set<String> _saved = {};
  bool _isLoading = true;
  String? _error;
  String _query = '';
  _View _view = _View.list;
  LatLng? _userLocation;
  PropertyListing? _selected; // shown as a floating card on the map
  bool _isBn = true;
  Timer? _debounce;
  final Map<String, BitmapDescriptor> _priceIcons = {}; // Airbnb-style price pills

  bool get _isMessTab => _listingType == 'MESS';

  int get _activeFilterCount {
    var n = 0;
    if (_minRent != null || _maxRent != null) n++;
    if (_radiusKm != 25) n++;
    if (_isMessTab) {
      if (_gender != null) n++;
      if (_smoking != null) n++;
      if (_occupation != null) n++;
    } else {
      if (_minBedrooms != null) n++;
      if (_tenantType != null) n++;
    }
    return n;
  }

  /// Draws a rounded white "৳rent" pill (accent when selected) to a PNG so it
  /// can be used as a Google Maps marker — the Airbnb map look.
  Future<BitmapDescriptor> _pricePill(String text, {required bool selected}) async {
    const scale = 3.0; // sharp on hi-dpi
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontSize: 13 * scale, fontWeight: FontWeight.w800,
        color: selected ? Colors.white : const Color(0xFF222222))),
      textDirection: TextDirection.ltr,
    )..layout();
    final padH = 12.0 * scale, padV = 7.0 * scale;
    final w = tp.width + padH * 2, h = tp.height + padV * 2;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 3 * scale, w, h), Radius.circular(h / 2));
    canvas.drawRRect(rrect.shift(Offset(0, 1.5 * scale)),
        Paint()..color = Colors.black26..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale));
    canvas.drawRRect(rrect, Paint()..color = selected ? _accent : Colors.white);
    canvas.drawRRect(rrect, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1.5 * scale
      ..color = selected ? _accent : const Color(0xFFDBDBDB));
    tp.paint(canvas, Offset(padH, padV + 3 * scale));
    final img = await rec.endRecording().toImage(w.ceil(), (h + 3 * scale).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  Future<void> _buildPriceIcons() async {
    for (final m in _all) {
      if (m.latLng == null || _priceIcons.containsKey(m.id)) continue;
      final label = m.rent != null ? takaFmt(m.rent!) : (m.isMess ? 'মেস' : 'বাসা');
      _priceIcons[m.id] = await _pricePill(label, selected: false);
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _userLocation = await _resolveLocation();
    await _fetch();
  }

  Future<LatLng?> _resolveLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      final pos = await Geolocator.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetch() async {
    setState(() { _isLoading = true; _error = null; _selected = null; });
    try {
      final loc = _userLocation;
      final res = await _client.get('/auth/properties/search', queryParameters: {
        'listingType': _listingType,
        if (loc != null) 'lat': loc.latitude,
        if (loc != null) 'lon': loc.longitude,
        if (loc != null) 'radiusKm': _radiusKm,
        if (_minRent != null) 'minRent': _minRent,
        if (_maxRent != null) 'maxRent': _maxRent,
        if (_isMessTab && _gender != null) 'genderPreference': _gender,
        if (_isMessTab && _smoking != null) 'smokingPreference': _smoking,
        if (_isMessTab && _occupation != null) 'occupationPreference': _occupation,
        if (!_isMessTab && _minBedrooms != null) 'bedrooms': _minBedrooms,
        if (!_isMessTab && _tenantType != null) 'tenantType': _tenantType,
      });
      final data = res.data;
      final raw = data is List ? data : (data['items'] ?? data['data'] ?? data['results'] ?? []);
      final list = (raw as List).map((e) => PropertyListing.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) {
        setState(() { _all = list; _isLoading = false; });
        _buildPriceIcons(); // Airbnb price pills for the map
      }
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.mapError(e).messageBn; _isLoading = false; });
    }
  }

  List<PropertyListing> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((m) =>
        m.messName.toLowerCase().contains(q) || m.address.toLowerCase().contains(q)).toList();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_query != v.trim()) setState(() => _query = v.trim());
    });
  }

  void _switchType(String type) {
    if (_listingType == type) return;
    setState(() => _listingType = type);
    _fetch();
  }

  // ── Preference display labels ────────────────────────────────────────────────
  String? _prefLabel(String? v) {
    switch (v) {
      case 'male': return _isBn ? 'পুরুষ' : 'Male';
      case 'female': return _isBn ? 'মহিলা' : 'Female';
      case 'smoker': return _isBn ? 'ধূমপায়ী' : 'Smoker';
      case 'non_smoker': return _isBn ? 'অধূমপায়ী' : 'Non-smoker';
      case 'student': return _isBn ? 'ছাত্র' : 'Student';
      case 'job_holder': return _isBn ? 'চাকরিজীবী' : 'Job holder';
      case 'family': return _isBn ? 'ফ্যামিলি' : 'Family';
      case 'bachelor': return _isBn ? 'ব্যাচেলর' : 'Bachelor';
      default: return null; // null / 'any' → no chip
    }
  }

  /// MESS → "৳5,000/সিট" (per seat), HOUSE → "৳25,000/মাস" (whole unit).
  String _rentLabel(PropertyListing m) {
    if (m.rent == null) return '';
    final unit = m.isMess ? (_isBn ? '/সিট' : '/seat') : (_isBn ? '/মাস' : '/mo');
    return '${takaFmt(m.rent!)}$unit';
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _searchHeader(),
            _typeToggle(),
            Expanded(child: _body()),
          ],
        ),
      ),
      floatingActionButton: (_filtered.any((m) => m.latLng != null))
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _view = _view == _View.list ? _View.map : _View.list),
              backgroundColor: AppColors.textPrimary,
              icon: Icon(_view == _View.list ? Icons.map_rounded : Icons.view_list_rounded, color: Colors.white, size: 19),
              label: Text(_view == _View.list ? (_isBn ? 'ম্যাপ' : 'Map') : (_isBn ? 'তালিকা' : 'List'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // Airbnb-style rounded search pill + filter + post buttons.
  Widget _searchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: AppColors.bgMid, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))]),
              child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.bgMid,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.glassBorder, width: 1),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 3))],
              ),
              child: Row(children: [
                const Icon(Icons.search_rounded, color: AppColors.textPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearch,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: _isBn ? 'কোথায় থাকতে চান?' : 'Where do you want to stay?',
                      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          // Filters — every filter is optional.
          GestureDetector(
            onTap: _openFilterSheet,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: AppColors.bgMid, shape: BoxShape.circle,
                    border: Border.all(color: _activeFilterCount > 0 ? _accent : AppColors.glassBorder),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))]),
                child: Icon(Icons.tune_rounded,
                    color: _activeFilterCount > 0 ? _accent : AppColors.textPrimary, size: 19),
              ),
              if (_activeFilterCount > 0)
                Positioned(
                  top: -3, right: -3,
                  child: Container(
                    width: 18, height: 18, alignment: Alignment.center,
                    decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                    child: Text('$_activeFilterCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          // Post an ad (owner side). The main entry lives in Profile → আমার বিজ্ঞাপন.
          GestureDetector(
            onTap: () async {
              final added = await Navigator.push<bool>(
                  context, MaterialPageRoute(builder: (_) => const PostPropertyScreen()));
              if (added == true) _fetch();
            },
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x330F5D45), blurRadius: 10, offset: Offset(0, 3))]),
              child: const Icon(Icons.add_home_rounded, color: Colors.white, size: 21),
            ),
          ),
        ],
      ),
    );
  }

  // [ মেস | বাসা ভাড়া ] — the seeker never sees the other kind.
  Widget _typeToggle() {
    Widget seg(String type, String bn, String en) {
      final on = _listingType == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchType(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(_isBn ? bn : en,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: on ? Colors.white : AppColors.textSecondary,
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(children: [
          seg('MESS', 'মেস', 'Mess'),
          seg('HOUSE_RENT', 'বাসা ভাড়া', 'House rent'),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_error != null && _all.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 16),
          GestureDetector(onTap: _fetch, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again', style: const TextStyle(color: _accent, fontWeight: FontWeight.w700))),
        ]),
      ));
    }
    if (_filtered.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.home_work_outlined, color: AppColors.textMuted, size: 56),
        const SizedBox(height: 12),
        Text(
            _isMessTab
                ? (_isBn ? 'কোনো মেস পাওয়া যায়নি' : 'No mess found')
                : (_isBn ? 'কোনো বাসা পাওয়া যায়নি' : 'No house found'),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
        if (_activeFilterCount > 0) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () { _clearFilters(); _fetch(); },
            child: Text(_isBn ? 'ফিল্টার মুছে ফেলুন' : 'Clear filters',
                style: const TextStyle(color: _accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ]));
    }
    return _view == _View.map ? _mapView() : _listView();
  }

  void _clearFilters() {
    setState(() {
      _minRent = null; _maxRent = null; _radiusKm = 25;
      _gender = null; _smoking = null; _occupation = null;
      _minBedrooms = null; _tenantType = null;
    });
  }

  // ── Filter bottom sheet — every filter optional ───────────────────────────────
  Future<void> _openFilterSheet() async {
    final minCtrl = TextEditingController(text: _minRent?.toString() ?? '');
    final maxCtrl = TextEditingController(text: _maxRent?.toString() ?? '');
    var radius = _radiusKm;
    var gender = _gender, smoking = _smoking, occupation = _occupation;
    var bedrooms = _minBedrooms;
    var tenant = _tenantType;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Widget chips<T>(List<(T, String)> options, T? value, void Function(T?) onPick) {
          return Wrap(
            spacing: 8, runSpacing: 8,
            children: options.map((o) {
              final on = value == o.$1;
              return GestureDetector(
                onTap: () => setSheet(() => onPick(on ? null : o.$1)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? _accent : AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: on ? _accent : AppColors.glassBorder),
                  ),
                  child: Text(o.$2, style: TextStyle(
                      color: on ? Colors.white : AppColors.textSecondary,
                      fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              );
            }).toList(),
          );
        }

        Widget label(String t, {String? hint}) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(t, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(width: 8),
              Expanded(child: Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5))),
            ],
          ]),
        );

        return Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: AppColors.bgMid,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text(_isBn ? 'ফিল্টার' : 'Filters',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800))),
                    GestureDetector(
                      onTap: () => setSheet(() {
                        minCtrl.clear(); maxCtrl.clear(); radius = 25;
                        gender = null; smoking = null; occupation = null;
                        bedrooms = null; tenant = null;
                      }),
                      child: Text(_isBn ? 'সব মুছুন' : 'Clear all',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label(_isBn ? 'ভাড়ার রেঞ্জ' : 'Rent range',
                              hint: _isMessTab
                                  ? (_isBn ? 'প্রতি সিট' : 'per seat')
                                  : (_isBn ? 'পুরো বাসা' : 'whole unit')),
                          Row(children: [
                            Expanded(child: _rentField(minCtrl, _isBn ? 'সর্বনিম্ন ৳' : 'Min ৳')),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('—', style: TextStyle(color: AppColors.textMuted))),
                            Expanded(child: _rentField(maxCtrl, _isBn ? 'সর্বোচ্চ ৳' : 'Max ৳')),
                          ]),
                          label(_isBn ? 'দূরত্ব' : 'Distance'),
                          chips<double>([
                            (5, _isBn ? '৫ কিমি' : '5 km'),
                            (10, _isBn ? '১০ কিমি' : '10 km'),
                            (25, _isBn ? '২৫ কিমি' : '25 km'),
                            (50, _isBn ? '৫০ কিমি' : '50 km'),
                          ], radius, (v) => radius = v ?? 25),
                          if (_isMessTab) ...[
                            const SizedBox(height: 18),
                            const Divider(color: AppColors.glassBorder, height: 1),
                            label(_isBn ? 'আমি কেমন সদস্য' : 'About me',
                                hint: _isBn ? 'নিজের কথা বলুন — মালিকের চাওয়ার সাথে মিলবে'
                                            : 'describe yourself — matched to owner preferences'),
                            chips<String>([
                              ('male', _isBn ? 'পুরুষ' : 'Male'),
                              ('female', _isBn ? 'মহিলা' : 'Female'),
                            ], gender, (v) => gender = v),
                            const SizedBox(height: 8),
                            chips<String>([
                              ('non_smoker', _isBn ? 'অধূমপায়ী' : 'Non-smoker'),
                              ('smoker', _isBn ? 'ধূমপায়ী' : 'Smoker'),
                            ], smoking, (v) => smoking = v),
                            const SizedBox(height: 8),
                            chips<String>([
                              ('student', _isBn ? 'ছাত্র' : 'Student'),
                              ('job_holder', _isBn ? 'চাকরিজীবী' : 'Job holder'),
                            ], occupation, (v) => occupation = v),
                          ] else ...[
                            label(_isBn ? 'বেডরুম' : 'Bedrooms',
                                hint: _isBn ? 'কমপক্ষে' : 'at least'),
                            chips<int>([
                              (1, _isBn ? '১+' : '1+'),
                              (2, _isBn ? '২+' : '2+'),
                              (3, _isBn ? '৩+' : '3+'),
                              (4, _isBn ? '৪+' : '4+'),
                            ], bedrooms, (v) => bedrooms = v),
                            label(_isBn ? 'ভাড়াটে' : 'Tenant type'),
                            chips<String>([
                              ('family', _isBn ? 'ফ্যামিলি' : 'Family'),
                              ('bachelor', _isBn ? 'ব্যাচেলর' : 'Bachelor'),
                            ], tenant, (v) => tenant = v),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(14)),
                      child: Center(child: Text(_isBn ? 'ফলাফল দেখুন' : 'Show results',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );

    if (applied == true) {
      setState(() {
        _minRent = int.tryParse(minCtrl.text.trim());
        _maxRent = int.tryParse(maxCtrl.text.trim());
        _radiusKm = radius;
        _gender = gender; _smoking = smoking; _occupation = occupation;
        _minBedrooms = bedrooms; _tenantType = tenant;
      });
      _fetch();
    }
    minCtrl.dispose();
    maxCtrl.dispose();
  }

  Widget _rentField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: AppColors.glassWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent, width: 1.5)),
      ),
    );
  }

  // ── List (Airbnb photo cards) ─────────────────────────────────────────────────
  Widget _listView() {
    final items = _filtered;
    return RefreshIndicator(
      color: _accent,
      backgroundColor: AppColors.bgMid,
      onRefresh: _fetch,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: items.length,
        itemBuilder: (_, i) => _airbnbCard(items[i]),
      ),
    );
  }

  Widget _airbnbCard(PropertyListing m) {
    final saved = _saved.contains(m.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: GestureDetector(
        onTap: () => _showDetail(m),
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // photo with heart — shorter (landscape) so cards are compact
            AspectRatio(
              aspectRatio: 4.5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _MessPhotos(photos: m.photosUrls),
                  ),
                  Positioned(
                    top: 12, right: 12,
                    child: GestureDetector(
                      onTap: () => setState(() => saved ? _saved.remove(m.id) : _saved.add(m.id)),
                      child: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: saved ? _accent : Colors.white,
                          size: 27,
                          shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)]),
                    ),
                  ),
                  if (m.distanceKm != null)
                    Positioned(
                      top: 12, left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Text('${m.distanceKm!.toStringAsFixed(1)} ${_isBn ? 'কিমি দূরে' : 'km away'}',
                            style: const TextStyle(color: Color(0xFF222222), fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(m.messName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
                if (m.isMess && m.totalSeats != null) ...[
                  const Icon(Icons.event_seat_rounded, size: 15, color: AppColors.textPrimary),
                  const SizedBox(width: 4),
                  Text('${m.totalSeats}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                ] else if (!m.isMess && m.bedrooms != null) ...[
                  const Icon(Icons.bed_rounded, size: 15, color: AppColors.textPrimary),
                  const SizedBox(width: 4),
                  Text('${m.bedrooms}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(m.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(
              m.isMess ? _messInfoLine(m) : _houseInfoLine(m),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            if (m.isMess && _messPrefChips(m).isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: _messPrefChips(m)),
            ],
            const SizedBox(height: 4),
            if (m.rent != null)
              Text(_rentLabel(m),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  String _messInfoLine(PropertyListing m) {
    final seats = m.totalSeats != null
        ? (_isBn ? '${m.totalSeats} সিট' : '${m.totalSeats} seats')
        : '';
    return [seats, if (m.ownerName != null) m.ownerName!].where((s) => s.isNotEmpty).join(' · ');
  }

  String _houseInfoLine(PropertyListing m) {
    final parts = <String>[
      if (m.bedrooms != null) _isBn ? '${m.bedrooms} বেড' : '${m.bedrooms} bed',
      if (m.bathrooms != null) _isBn ? '${m.bathrooms} বাথ' : '${m.bathrooms} bath',
      if (m.sizeSqft != null) '${m.sizeSqft} sqft',
      if (_prefLabel(m.tenantType) != null) _prefLabel(m.tenantType)!,
    ];
    return parts.join(' · ');
  }

  List<Widget> _messPrefChips(PropertyListing m) {
    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
    return [
      for (final v in [m.genderPreference, m.smokingPreference, m.occupationPreference])
        if (_prefLabel(v) != null) chip(_prefLabel(v)!),
    ];
  }

  // ── Map (Google Maps) ─────────────────────────────────────────────────────────
  Widget _mapView() {
    final pinned = _filtered.where((m) => m.latLng != null).toList();
    final center = _userLocation ?? (pinned.isNotEmpty ? pinned.first.latLng! : _dhaka);
    final markers = {
      for (final m in pinned)
        Marker(
          markerId: MarkerId(m.id),
          position: m.latLng!,
          icon: _priceIcons[m.id] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
          anchor: const Offset(0.5, 0.5),
          onTap: () => setState(() => _selected = m),
        ),
    };
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 12.5),
          markers: markers,
          myLocationEnabled: _userLocation != null,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (c) => _mapController = c,
          onTap: (_) => setState(() => _selected = null),
        ),
        if (_selected != null)
          Positioned(
            left: 16, right: 16, bottom: 20,
            child: _mapPreviewCard(_selected!),
          ),
      ],
    );
  }

  Widget _mapPreviewCard(PropertyListing m) {
    return GestureDetector(
      onTap: () => _showDetail(m),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
            child: SizedBox(width: 108, height: 108, child: _MessPhotos(photos: m.photosUrls, dots: false)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(m.messName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(m.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '${m.isMess ? _messInfoLine(m) : _houseInfoLine(m)}${m.distanceKm != null ? ' · ${m.distanceKm!.toStringAsFixed(1)} ${_isBn ? 'কিমি' : 'km'}' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                if (m.rent != null) ...[
                  const SizedBox(height: 3),
                  Text(_rentLabel(m),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Detail sheet ─────────────────────────────────────────────────────────────
  void _showDetail(PropertyListing listing) async {
    PropertyListing detail = listing;
    try {
      final res = await _client.get('/auth/properties/${listing.id}');
      if (res.data is Map<String, dynamic>) {
        detail = PropertyListing.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(
          listing: detail, isBn: _isBn,
          prefLabel: _prefLabel, rentLabel: _rentLabel,
          onCall: () => _showContact(detail.ownerPhone),
          onRequestVisit: detail.ownerUserId == null ? null : () => _requestVisit(detail)),
    );
  }

  // Books a visit slot against a browse-listing (propertyListingId) — separate from the
  // matchmaking mess_finder request/response flow, which uses requestId instead. Owner sees
  // it under their own visit-requests list and confirming opens a chat thread automatically.
  Future<void> _requestVisit(PropertyListing listing) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null || !mounted) return;
    final visitDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    try {
      await _client.post('/matchmaking/mess/visit-requests', data: {
        'propertyListingId': listing.id,
        'ownerId': listing.ownerUserId,
        'visitDate': visitDate.toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBn ? 'ভিজিট রিকোয়েস্ট পাঠানো হয়েছে' : 'Visit request sent', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF22C55E), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBn ? 'পাঠানো যায়নি — আবার চেষ্টা করুন' : 'Could not send — try again', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating));
    }
  }

  void _showContact(String? number) {
    if (number == null || number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBn ? 'যোগাযোগ নম্বর নেই' : 'No contact number', style: const TextStyle(color: Colors.white)),
        backgroundColor: _accent, behavior: SnackBarBehavior.floating));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_isBn ? 'যোগাযোগ নম্বর' : 'Contact number', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(number, style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1)),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: number));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_isBn ? 'নম্বর কপি হয়েছে' : 'Number copied', style: const TextStyle(color: Colors.white)),
                  backgroundColor: AppColors.deepBlue, behavior: SnackBarBehavior.floating));
              }
            },
            child: Text(_isBn ? 'কপি করুন' : 'Copy', style: const TextStyle(color: _accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Swipeable photo carousel (Airbnb-style) ──────────────────────────────────
class _MessPhotos extends StatefulWidget {
  final List<String> photos;
  final bool dots;
  const _MessPhotos({required this.photos, this.dots = true});

  @override
  State<_MessPhotos> createState() => _MessPhotosState();
}

class _MessPhotosState extends State<_MessPhotos> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Container(color: const Color(0xFFEDE8DE), child: const Center(child: Icon(Icons.home_work_rounded, color: AppColors.textMuted, size: 44)));
    }
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        controller: _ctrl,
        onPageChanged: (i) => setState(() => _page = i),
        itemCount: widget.photos.length,
        itemBuilder: (_, i) => Image.network(widget.photos[i], fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFFEDE8DE), child: const Icon(Icons.home_work_rounded, color: AppColors.textMuted, size: 40))),
      ),
      if (widget.dots && widget.photos.length > 1)
        Positioned(
          bottom: 10, left: 0, right: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(widget.photos.length, (i) {
            final on = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: on ? 7 : 6, height: on ? 7 : 6,
              decoration: BoxDecoration(color: on ? Colors.white : Colors.white70, shape: BoxShape.circle),
            );
          })),
        ),
    ]);
  }
}

// ── Detail bottom sheet ──────────────────────────────────────────────────────
class _DetailSheet extends StatelessWidget {
  final PropertyListing listing;
  final bool isBn;
  final String? Function(String?) prefLabel;
  final String Function(PropertyListing) rentLabel;
  final VoidCallback onCall;
  // Null for legacy agent-posted listings (no ownerUserId to route the request to).
  final VoidCallback? onRequestVisit;
  const _DetailSheet({
    required this.listing, required this.isBn,
    required this.prefLabel, required this.rentLabel, required this.onCall,
    this.onRequestVisit});

  @override
  Widget build(BuildContext context) {
    final m = listing;
    return DraggableScrollableSheet(
      initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: EdgeInsets.zero,
              children: [
                if (m.photosUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: AspectRatio(
                      aspectRatio: 1.3,
                      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: _MessPhotos(photos: m.photosUrls)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.messName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                    if (m.rent != null) ...[
                      const SizedBox(height: 6),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: takaFmt(m.rent!), style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                        TextSpan(
                            text: m.isMess
                                ? (isBn ? ' / মাস (প্রতি সিট)' : ' / month (per seat)')
                                : (isBn ? ' / মাস (পুরো বাসা)' : ' / month (whole unit)'),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.w500)),
                      ])),
                    ],
                    const SizedBox(height: 12),
                    _row(Icons.location_on_rounded, m.address),
                    if (m.isMess && m.totalSeats != null) ...[
                      const SizedBox(height: 8),
                      _row(Icons.event_seat_rounded, isBn ? 'মোট ${m.totalSeats} সিট' : '${m.totalSeats} seats'),
                    ],
                    if (!m.isMess) ...[
                      if (m.bedrooms != null) ...[
                        const SizedBox(height: 8),
                        _row(Icons.bed_rounded, isBn ? '${m.bedrooms} বেডরুম' : '${m.bedrooms} bedrooms'),
                      ],
                      if (m.bathrooms != null) ...[
                        const SizedBox(height: 8),
                        _row(Icons.bathtub_outlined, isBn ? '${m.bathrooms} বাথরুম' : '${m.bathrooms} bathrooms'),
                      ],
                      if (m.sizeSqft != null) ...[
                        const SizedBox(height: 8),
                        _row(Icons.square_foot_rounded, isBn ? 'আয়তন ${m.sizeSqft} sqft' : '${m.sizeSqft} sqft'),
                      ],
                      if (m.floor != null) ...[
                        const SizedBox(height: 8),
                        _row(Icons.stairs_outlined, isBn ? '${m.floor} তলা' : 'Floor ${m.floor}'),
                      ],
                      if (prefLabel(m.tenantType) != null) ...[
                        const SizedBox(height: 8),
                        _row(Icons.family_restroom_rounded,
                            isBn ? 'ভাড়াটে: ${prefLabel(m.tenantType)}' : 'Tenant: ${prefLabel(m.tenantType)}'),
                      ],
                    ],
                    if (m.isMess) ...[
                      for (final e in [
                        (Icons.wc_rounded, prefLabel(m.genderPreference)),
                        (Icons.smoke_free_rounded, prefLabel(m.smokingPreference)),
                        (Icons.work_outline_rounded, prefLabel(m.occupationPreference)),
                      ])
                        if (e.$2 != null) ...[
                          const SizedBox(height: 8),
                          _row(e.$1, isBn ? 'চাওয়া: ${e.$2}' : 'Wants: ${e.$2}'),
                        ],
                    ],
                    if (m.distanceKm != null) ...[
                      const SizedBox(height: 8),
                      _row(Icons.near_me_rounded, isBn ? 'দূরত্ব ${m.distanceKm!.toStringAsFixed(1)} কিমি' : '${m.distanceKm!.toStringAsFixed(1)} km away'),
                    ],
                    if (m.ownerName != null) ...[
                      const SizedBox(height: 8),
                      _row(Icons.person_rounded, isBn ? 'মালিক: ${m.ownerName}' : 'Owner: ${m.ownerName}'),
                    ],
                    if (m.rules != null && m.rules!.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Divider(color: AppColors.glassBorder, height: 1),
                      const SizedBox(height: 16),
                      Text(isBn ? 'নিয়মকানুন' : 'House rules', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(m.rules!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6)),
                    ],
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onCall,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(14)),
                            child: Center(child: Text(isBn ? 'যোগাযোগ করুন' : 'Contact', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                          ),
                        ),
                      ),
                      if (onRequestVisit != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: onRequestVisit,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: AppColors.glassWhite,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _accent, width: 1.5),
                              ),
                              child: Center(child: Text(isBn ? 'ভিজিট রিকোয়েস্ট' : 'Request Visit', style: const TextStyle(color: _accent, fontSize: 15, fontWeight: FontWeight.w700))),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.textMuted, size: 17),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5))),
    ]);
  }
}
