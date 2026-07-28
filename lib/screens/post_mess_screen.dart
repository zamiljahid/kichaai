import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/property_model.dart';
import '../theme/app_theme.dart';

const _accent = AppColors.deepBlue;

class _PickedPhoto {
  final XFile file;
  final Uint8List bytes;
  const _PickedPhoto(this.file, this.bytes);
}

/// An owner posts (or edits) their own mess / house-rent advertisement.
/// Plain logged-in user — no agent registration, no provider onboarding.
class PostPropertyScreen extends StatefulWidget {
  final PropertyListing? existing; // non-null → edit mode (PATCH changed fields only)
  const PostPropertyScreen({super.key, this.existing});

  @override
  State<PostPropertyScreen> createState() => _PostPropertyScreenState();
}

class _PostPropertyScreenState extends State<PostPropertyScreen> {
  final _dio = ApiClient.instance.dio;
  final _picker = ImagePicker();

  late String _listingType =
      widget.existing?.listingType ?? 'MESS'; // MESS | HOUSE_RENT

  late final _name = TextEditingController(text: widget.existing?.messName ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _rent = TextEditingController(text: widget.existing?.rent?.toString() ?? '');
  late final _rules = TextEditingController(text: widget.existing?.rules ?? '');
  // MESS
  late final _seats = TextEditingController(text: widget.existing?.totalSeats?.toString() ?? '');
  late String _gender = widget.existing?.genderPreference ?? 'any';
  late String _smoking = widget.existing?.smokingPreference ?? 'any';
  late String _occupation = widget.existing?.occupationPreference ?? 'any';
  // HOUSE
  late final _bedrooms = TextEditingController(text: widget.existing?.bedrooms?.toString() ?? '');
  late final _bathrooms = TextEditingController(text: widget.existing?.bathrooms?.toString() ?? '');
  late final _sqft = TextEditingController(text: widget.existing?.sizeSqft?.toString() ?? '');
  late final _floor = TextEditingController(text: widget.existing?.floor?.toString() ?? '');
  late String _tenantType = widget.existing?.tenantType ?? 'any';

  late final List<String> _existingPhotos = List.of(widget.existing?.photosUrls ?? const []);
  final List<_PickedPhoto> _newPhotos = [];

  bool _saving = false;
  bool _isBn = true;

  bool get _isEdit => widget.existing != null;
  bool get _isMess => _listingType == 'MESS';

  @override
  void dispose() {
    for (final c in [_name, _address, _rent, _rules, _seats, _bedrooms, _bathrooms, _sqft, _floor]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      _newPhotos.add(_PickedPhoto(f, bytes));
    }
    if (mounted) setState(() {});
  }

  /// Upload one picked photo → hosted URL for photosUrls[].
  Future<String> _upload(_PickedPhoto p) async {
    final mime = p.file.mimeType ?? 'image/jpeg';
    final dataUri = 'data:$mime;base64,${base64Encode(p.bytes)}';
    final res = await _dio.post('/onboarding/uploads', data: {
      'file': dataUri,
      'fileName': p.file.name.isNotEmpty ? p.file.name : 'photo.jpg',
    });
    return (res.data as Map)['fileUrl'].toString();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final address = _address.text.trim();
    // Client-side required fields — the user should never see the backend 400.
    if (name.isEmpty || address.isEmpty) {
      _snack(_isBn
          ? (_isMess ? 'নাম ও ঠিকানা দিন' : 'শিরোনাম ও ঠিকানা দিন')
          : 'Enter title and address', error: true);
      return;
    }
    final seats = int.tryParse(_seats.text.trim());
    if (_isMess && seats == null) {
      _snack(_isBn ? 'মোট সিট সংখ্যা দিন' : 'Enter total seats', error: true);
      return;
    }
    final bedrooms = int.tryParse(_bedrooms.text.trim());
    if (!_isMess && bedrooms == null) {
      _snack(_isBn ? 'বেডরুম সংখ্যা দিন' : 'Enter number of bedrooms', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      // Photos first — the listing carries only their URLs.
      final photoUrls = List.of(_existingPhotos);
      for (final p in _newPhotos) {
        photoUrls.add(await _upload(p));
      }

      final rent = int.tryParse(_rent.text.trim());
      final body = <String, dynamic>{
        'listingType': _listingType,
        'messName': name, // title for both kinds (field name is historical)
        'address': address,
        if (rent != null) 'rent': rent,
        'photosUrls': photoUrls,
        'rules': _rules.text.trim(),
        if (_isMess) ...{
          'totalSeats': seats,
          'genderPreference': _gender,
          'smokingPreference': _smoking,
          'occupationPreference': _occupation,
        } else ...{
          'bedrooms': bedrooms,
          if (int.tryParse(_bathrooms.text.trim()) != null) 'bathrooms': int.parse(_bathrooms.text.trim()),
          if (int.tryParse(_sqft.text.trim()) != null) 'sizeSqft': int.parse(_sqft.text.trim()),
          if (int.tryParse(_floor.text.trim()) != null) 'floor': int.parse(_floor.text.trim()),
          'tenantType': _tenantType,
        },
        // latitude/longitude omitted — geocoded server-side from the address.
      };

      if (_isEdit) {
        await _patchChanged(body);
      } else {
        final res = await _dio.post('/auth/properties', data: body);
        final created = res.data is Map ? res.data as Map : const {};
        final id = created['id']?.toString();
        // Geocoder failed → no coordinates → the listing would never appear in
        // the nearby search. Offer a manual map pin.
        if (id != null && created['latitude'] == null) {
          await _offerManualPin(id);
        }
      }

      if (!mounted) return;
      _snack(_isEdit
          ? (_isBn ? 'বিজ্ঞাপন আপডেট হয়েছে' : 'Listing updated')
          : (_isBn
              ? (_isMess ? 'মেস পোস্ট হয়েছে — ম্যাপে দেখা যাবে' : 'বাসার বিজ্ঞাপন পোস্ট হয়েছে — ম্যাপে দেখা যাবে')
              : 'Listing posted — it will show on the map'));
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack(ApiClient.mapError(e).messageBn, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Edit mode: send ONLY the fields that changed.
  Future<void> _patchChanged(Map<String, dynamic> body) async {
    final old = widget.existing!;
    String normPref(String? v) => (v == null || v.isEmpty) ? 'any' : v;
    final patch = <String, dynamic>{};

    void diff(String key, dynamic newVal, dynamic oldVal) {
      if (newVal != oldVal) patch[key] = newVal;
    }

    diff('messName', body['messName'], old.messName);
    diff('address', body['address'], old.address);
    diff('rent', body['rent'], old.rent);
    diff('rules', body['rules'], old.rules ?? '');
    if (_isMess) {
      diff('totalSeats', body['totalSeats'], old.totalSeats);
      diff('genderPreference', body['genderPreference'], normPref(old.genderPreference));
      diff('smokingPreference', body['smokingPreference'], normPref(old.smokingPreference));
      diff('occupationPreference', body['occupationPreference'], normPref(old.occupationPreference));
    } else {
      diff('bedrooms', body['bedrooms'], old.bedrooms);
      diff('bathrooms', body['bathrooms'], old.bathrooms);
      diff('sizeSqft', body['sizeSqft'], old.sizeSqft);
      diff('floor', body['floor'], old.floor);
      diff('tenantType', body['tenantType'], normPref(old.tenantType));
    }
    final newPhotos = (body['photosUrls'] as List).cast<String>();
    if (!listEquals(newPhotos, old.photosUrls)) patch['photosUrls'] = newPhotos;

    if (patch.isEmpty) return; // nothing changed

    final res = await _dio.patch('/auth/properties/${old.id}', data: patch);
    // Changing the address re-geocodes it — if that failed, offer a pin.
    if (patch.containsKey('address') &&
        res.data is Map && (res.data as Map)['latitude'] == null) {
      await _offerManualPin(old.id);
    }
  }

  /// "ঠিকানাটি ম্যাপে পাওয়া যায়নি" → let the owner drop a pin, then PATCH it.
  Future<void> _offerManualPin(String id) async {
    if (!mounted) return;
    final wantsPin = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_isBn ? 'ঠিকানাটি ম্যাপে পাওয়া যায়নি' : 'Address not found on the map',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
            _isBn
                ? 'ম্যাপে পিন না দিলে বিজ্ঞাপনটি আশেপাশের খোঁজে দেখা যাবে না। এখনই ম্যাপে পিন দিন।'
                : 'Without a map pin this listing will not appear in nearby search. Drop a pin now.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isBn ? 'পরে করব' : 'Later', style: const TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isBn ? 'ম্যাপে পিন দিন' : 'Drop a pin',
                style: const TextStyle(color: _accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (wantsPin != true || !mounted) return;

    final pin = await Navigator.push<LatLng>(
        context, MaterialPageRoute(builder: (_) => _PinPickerScreen(isBn: _isBn)));
    if (pin == null) return;
    try {
      await _dio.patch('/auth/properties/$id',
          data: {'latitude': pin.latitude, 'longitude': pin.longitude});
    } catch (e) {
      _snack(ApiClient.mapError(e).messageBn, error: true);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
            _isEdit
                ? (_isBn ? 'বিজ্ঞাপন সম্পাদনা' : 'Edit listing')
                : (_isBn ? 'নতুন বিজ্ঞাপন' : 'New listing'),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          _typeToggle(),
          const SizedBox(height: 16),
          Text(
              _isBn
                  ? 'ঠিকানা দিলেই ম্যাপে নিজে থেকে বসে যাবে — ভাড়া সহ পিন দেখাবে।'
                  : 'Just type the address — it auto-pins on the map with the rent.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 20),
          if (_isMess) ..._messForm() else ..._houseForm(),
          const SizedBox(height: 16),
          _label(_isBn ? 'নিয়মকানুন (ঐচ্ছিক)' : 'House rules (optional)'),
          _field(_rules, _isBn ? 'যেমন: রাত ১১টার পর গেট বন্ধ' : 'e.g. Gate closes at 11pm', maxLines: 2),
          const SizedBox(height: 16),
          _photoSection(),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _saving ? null : _submit,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(14)),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      _isEdit
                          ? (_isBn ? 'সংরক্ষণ করুন' : 'Save changes')
                          : (_isBn ? 'বিজ্ঞাপন পোস্ট করুন' : 'Post listing'),
                      style: const TextStyle(color: AppColors.ivory, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // [ মেস | বাসা ভাড়া ] — swaps the whole form. Locked in edit mode.
  Widget _typeToggle() {
    Widget seg(String type, String bn, String en) {
      final on = _listingType == type;
      return Expanded(
        child: GestureDetector(
          onTap: _isEdit ? null : () => setState(() => _listingType = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: on ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(_isBn ? bn : en,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: on
                        ? Colors.white
                        : (_isEdit ? AppColors.textMuted : AppColors.textSecondary),
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Container(
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
    );
  }

  List<Widget> _messForm() {
    return [
      _label(_isBn ? 'মেসের নাম *' : 'Mess name *'),
      _field(_name, _isBn ? 'যেমন: গুলশান প্রিমিয়াম মেস' : 'e.g. Gulshan Premium Mess'),
      const SizedBox(height: 16),
      _label(_isBn ? 'ঠিকানা *' : 'Address *'),
      _field(_address, _isBn ? 'এলাকা, রোড, ঢাকা' : 'Area, road, Dhaka', maxLines: 2),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(_isBn ? 'মোট সিট *' : 'Total seats *'),
          _field(_seats, _isBn ? 'যেমন: ৮' : 'e.g. 8', keyboard: TextInputType.number, digitsOnly: true),
        ])),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(_isBn ? 'সিট প্রতি ভাড়া (৳)' : 'Rent per seat (৳)'),
          _field(_rent, _isBn ? 'যেমন: ৫০০০' : 'e.g. 5000', keyboard: TextInputType.number, digitsOnly: true),
        ])),
      ]),
      const SizedBox(height: 20),
      _sectionHeader(
          _isBn ? 'কেমন সদস্য চান? (সবই ঐচ্ছিক)' : 'Who do you want? (all optional)',
          _isBn ? 'কিছু না বাছলে সবার জন্য উন্মুক্ত' : 'Leave blank to accept anyone'),
      const SizedBox(height: 10),
      _label(_isBn ? 'জেন্ডার' : 'Gender'),
      _prefChips(
        value: _gender,
        onPick: (v) => setState(() => _gender = v),
        options: [
          ('any', _isBn ? 'যেকোনো' : 'Any'),
          ('male', _isBn ? 'পুরুষ' : 'Male'),
          ('female', _isBn ? 'মহিলা' : 'Female'),
        ],
      ),
      const SizedBox(height: 12),
      _label(_isBn ? 'ধূমপান' : 'Smoking'),
      _prefChips(
        value: _smoking,
        onPick: (v) => setState(() => _smoking = v),
        options: [
          ('any', _isBn ? 'যেকোনো' : 'Any'),
          ('non_smoker', _isBn ? 'অধূমপায়ী' : 'Non-smoker'),
          ('smoker', _isBn ? 'ধূমপায়ী' : 'Smoker'),
        ],
      ),
      const SizedBox(height: 12),
      _label(_isBn ? 'পেশা' : 'Occupation'),
      _prefChips(
        value: _occupation,
        onPick: (v) => setState(() => _occupation = v),
        options: [
          ('any', _isBn ? 'যেকোনো' : 'Any'),
          ('student', _isBn ? 'ছাত্র' : 'Student'),
          ('job_holder', _isBn ? 'চাকরিজীবী' : 'Job holder'),
        ],
      ),
    ];
  }

  List<Widget> _houseForm() {
    return [
      _label(_isBn ? 'শিরোনাম *' : 'Title *'),
      _field(_name, _isBn ? 'যেমন: মিরপুর ৩-বেড ফ্ল্যাট' : 'e.g. Mirpur 3-bed flat'),
      const SizedBox(height: 16),
      _label(_isBn ? 'ঠিকানা *' : 'Address *'),
      _field(_address, _isBn ? 'এলাকা, রোড, ঢাকা' : 'Area, road, Dhaka', maxLines: 2),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(_isBn ? 'বেডরুম *' : 'Bedrooms *'),
          _field(_bedrooms, _isBn ? 'যেমন: ৩' : 'e.g. 3', keyboard: TextInputType.number, digitsOnly: true),
        ])),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(_isBn ? 'বাথরুম' : 'Bathrooms'),
          _field(_bathrooms, _isBn ? 'যেমন: ২' : 'e.g. 2', keyboard: TextInputType.number, digitsOnly: true),
        ])),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(_isBn ? 'আয়তন (sqft)' : 'Size (sqft)'),
          _field(_sqft, _isBn ? 'যেমন: ১২০০' : 'e.g. 1200', keyboard: TextInputType.number, digitsOnly: true),
        ])),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(_isBn ? 'তলা' : 'Floor'),
          _field(_floor, _isBn ? 'যেমন: ৪' : 'e.g. 4', keyboard: TextInputType.number, digitsOnly: true),
        ])),
      ]),
      const SizedBox(height: 16),
      _label(_isBn ? 'ভাড়াটে' : 'Tenant type'),
      _prefChips(
        value: _tenantType,
        onPick: (v) => setState(() => _tenantType = v),
        options: [
          ('any', _isBn ? 'যেকোনো' : 'Any'),
          ('family', _isBn ? 'ফ্যামিলি' : 'Family'),
          ('bachelor', _isBn ? 'ব্যাচেলর' : 'Bachelor'),
        ],
      ),
      const SizedBox(height: 16),
      _label(_isBn ? 'মাসিক ভাড়া (৳)' : 'Monthly rent (৳)'),
      _field(_rent, _isBn ? 'যেমন: ২৫০০০' : 'e.g. 25000', keyboard: TextInputType.number, digitsOnly: true),
    ];
  }

  Widget _photoSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(_isBn ? 'ছবি (ঐচ্ছিক)' : 'Photos (optional)'),
      const SizedBox(height: 4),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < _existingPhotos.length; i++)
          _thumb(
            Image.network(_existingPhotos[i], fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEDE8DE))),
            () => setState(() => _existingPhotos.removeAt(i)),
          ),
        for (var i = 0; i < _newPhotos.length; i++)
          _thumb(
            Image.memory(_newPhotos[i].bytes, fit: BoxFit.cover),
            () => setState(() => _newPhotos.removeAt(i)),
          ),
        GestureDetector(
          onTap: _pickPhotos,
          child: Container(
            width: 84, height: 84,
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary, size: 26),
              SizedBox(height: 4),
              Text('+', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    ]);
  }

  Widget _thumb(Widget image, VoidCallback onRemove) {
    return SizedBox(
      width: 84, height: 84,
      child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
        Positioned(
          top: -6, right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22, height: 22,
              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _sectionHeader(String title, String hint) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(color: AppColors.glassBorder, height: 1),
      const SizedBox(height: 14),
      Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
    ]);
  }

  Widget _prefChips({
    required String value,
    required void Function(String) onPick,
    required List<(String, String)> options,
  }) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: options.map((o) {
        final on = value == o.$1;
        return GestureDetector(
          onTap: () => onPick(o.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
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

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(t, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _field(TextEditingController c, String hint,
      {int maxLines = 1, TextInputType? keyboard, bool digitsOnly = false}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: AppColors.glassWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent, width: 1.5)),
      ),
    );
  }
}

// ── Manual pin picker — used only when the geocoder failed ───────────────────
class _PinPickerScreen extends StatefulWidget {
  final bool isBn;
  const _PinPickerScreen({required this.isBn});

  @override
  State<_PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends State<_PinPickerScreen> {
  static const _dhaka = LatLng(23.8103, 90.4125);
  LatLng? _pin;

  @override
  Widget build(BuildContext context) {
    final isBn = widget.isBn;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(isBn ? 'ম্যাপে পিন দিন' : 'Drop a pin',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: _dhaka, zoom: 12),
          onTap: (p) => setState(() => _pin = p),
          markers: {
            if (_pin != null)
              Marker(markerId: const MarkerId('pin'), position: _pin!),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        Positioned(
          left: 16, right: 16, bottom: 24,
          child: GestureDetector(
            onTap: _pin == null ? null : () => Navigator.pop(context, _pin),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: _pin == null ? AppColors.textMuted : _accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: Text(
                  _pin == null
                      ? (isBn ? 'ম্যাপে ট্যাপ করে জায়গাটি দেখান' : 'Tap the map to mark the place')
                      : (isBn ? 'এই জায়গাটিই ঠিক আছে' : 'Confirm this location'),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
            ),
          ),
        ),
      ]),
    );
  }
}
