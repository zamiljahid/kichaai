import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/catalog_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'photographer_profile_screen.dart' show sectionCard, labeledField, uploadRow;

/// Technician group + specialization + group-specific hard-stop gate — the
/// piece the generic document-upload onboarding flow can't express (it only
/// knows required/optional documents, not "Automotive requires a confirmed
/// garage" or "Industrial requires safety training or 2 years experience").
///
/// Reached from the "Select a Service" grid BEFORE the generic document step
/// for st_technician (see provider_onboarding_screen.dart's _onServiceSelected),
/// and from "My Services" afterward for editing. Submitting here also pushes
/// the chosen specializations straight into the job-matching snapshot (see
/// OnboardingService.submitTechnicianDetails on the backend), so a technician
/// doesn't need a separate trip through TechnicianSpecializationsScreen.
class TechnicianOnboardingScreen extends StatefulWidget {
  const TechnicianOnboardingScreen({super.key});

  @override
  State<TechnicianOnboardingScreen> createState() => _TechnicianOnboardingScreenState();
}

class _TechnicianOnboardingScreenState extends State<TechnicianOnboardingScreen> {
  TechnicianSpecializationTaxonomy? _taxonomy;
  bool _loading = true;
  String? _loadError;
  bool _isBn = true;

  String? _group;
  final Set<String> _types = {};
  final _experienceCtrl = TextEditingController();

  // HOME_ELECTRICAL
  String? _workSamplePhotoUrl;
  bool _uploadingWorkSample = false;

  // AUTOMOTIVE
  final _garageAddressCtrl = TextEditingController();
  double? _garageLat;
  double? _garageLng;
  bool _capturingGarageLocation = false;
  String? _garagePhotoUrl;
  bool _uploadingGaragePhoto = false;
  bool _hasWorkshop = false;
  String? _tradeLicenseUrl;
  bool _uploadingTradeLicense = false;
  final _garageWorkerCountCtrl = TextEditingController();
  bool? _hasRecoveryVan;
  final _recoveryVanRadiusCtrl = TextEditingController();
  bool? _hasFuelSupply;

  // IT_COMPUTER / TELECOM
  String? _certificateUrl;
  bool _uploadingCertificate = false;
  bool _hasShop = false;
  final _shopAddressCtrl = TextEditingController();
  double? _shopLat;
  double? _shopLng;
  bool _capturingShopLocation = false;
  String? _shopTradeLicenseUrl;
  bool _uploadingShopTradeLicense = false;
  bool? _canVisitCustomerHome;

  // INDUSTRIAL
  String? _safetyCertificateUrl;
  bool _uploadingSafetyCertificate = false;
  bool _hasSafetyTraining = false;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _experienceCtrl.dispose();
    _garageAddressCtrl.dispose();
    _garageWorkerCountCtrl.dispose();
    _recoveryVanRadiusCtrl.dispose();
    _shopAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tax = await CatalogService.instance.getTechnicianSpecializationsNew();
      if (mounted) setState(() { _taxonomy = tax; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loadError = ApiClient.mapError(e).localized(_isBn); _loading = false; });
    }
  }

  Future<String?> _pickAndUpload() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    final ext = f.name.split('.').last.toLowerCase();
    final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
    return OnboardingService.instance.uploadFile(fileBase64: base64Encode(bytes), fileName: f.name, mimeType: mime);
  }

  Future<void> _uploadWorkSample() async {
    setState(() => _uploadingWorkSample = true);
    try {
      final url = await _pickAndUpload();
      if (mounted && url != null) setState(() => _workSamplePhotoUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingWorkSample = false);
    }
  }

  Future<void> _uploadGaragePhoto() async {
    setState(() => _uploadingGaragePhoto = true);
    try {
      final url = await _pickAndUpload();
      if (mounted && url != null) setState(() => _garagePhotoUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingGaragePhoto = false);
    }
  }

  Future<void> _uploadTradeLicense() async {
    setState(() => _uploadingTradeLicense = true);
    try {
      final url = await _pickAndUpload();
      if (mounted && url != null) setState(() => _tradeLicenseUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingTradeLicense = false);
    }
  }

  Future<void> _uploadShopTradeLicense() async {
    setState(() => _uploadingShopTradeLicense = true);
    try {
      final url = await _pickAndUpload();
      if (mounted && url != null) setState(() => _shopTradeLicenseUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingShopTradeLicense = false);
    }
  }

  Future<void> _uploadCertificate() async {
    setState(() => _uploadingCertificate = true);
    try {
      final url = await _pickAndUpload();
      if (mounted && url != null) setState(() => _certificateUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingCertificate = false);
    }
  }

  Future<void> _uploadSafetyCertificate() async {
    setState(() => _uploadingSafetyCertificate = true);
    try {
      final url = await _pickAndUpload();
      if (mounted && url != null) setState(() => _safetyCertificateUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingSafetyCertificate = false);
    }
  }

  Future<void> _captureGarageLocation() async {
    setState(() => _capturingGarageLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final denied = permission == LocationPermission.denied || permission == LocationPermission.deniedForever;
      if (!serviceEnabled || denied) {
        _snack(_isBn ? 'লোকেশন অনুমতি প্রয়োজন' : 'Location permission required', error: true);
      } else {
        final pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 15));
        setState(() { _garageLat = pos.latitude; _garageLng = pos.longitude; });
      }
    } catch (_) {
      _snack(_isBn ? 'অবস্থান পাওয়া যায়নি' : 'Could not get location', error: true);
    } finally {
      if (mounted) setState(() => _capturingGarageLocation = false);
    }
  }

  Future<void> _captureShopLocation() async {
    setState(() => _capturingShopLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final denied = permission == LocationPermission.denied || permission == LocationPermission.deniedForever;
      if (!serviceEnabled || denied) {
        _snack(_isBn ? 'লোকেশন অনুমতি প্রয়োজন' : 'Location permission required', error: true);
      } else {
        final pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 15));
        setState(() { _shopLat = pos.latitude; _shopLng = pos.longitude; });
      }
    } catch (_) {
      _snack(_isBn ? 'অবস্থান পাওয়া যায়নি' : 'Could not get location', error: true);
    } finally {
      if (mounted) setState(() => _capturingShopLocation = false);
    }
  }

  Future<void> _submit() async {
    if (_group == null) return;
    if (_types.isEmpty) {
      _snack(_isBn ? 'অন্তত একটি কাজের ধরন বেছে নিন' : 'Choose at least one specialization', error: true);
      return;
    }
    final years = double.tryParse(_experienceCtrl.text.trim());
    if (years == null || years < 0) {
      _snack(_isBn ? 'অভিজ্ঞতা সঠিকভাবে দিন' : 'Enter valid years of experience', error: true);
      return;
    }
    int? garageWorkerCount;
    int? recoveryVanRadiusKm;
    if (_group == 'AUTOMOTIVE') {
      if (_garageAddressCtrl.text.trim().isEmpty || _garageLat == null || _garageLng == null) {
        _snack(_isBn ? 'গ্যারেজের ঠিকানা ও অবস্থান দিন' : 'Add your garage address and location', error: true);
        return;
      }
      if (!_hasWorkshop) {
        _snack(_isBn ? 'গাড়ি ক্যাটাগরির জন্য নির্দিষ্ট গ্যারেজ/ওয়ার্কশপ নিশ্চিত করা আবশ্যক' : 'The Automotive category requires confirming a fixed garage/workshop', error: true);
        return;
      }
      if (_tradeLicenseUrl == null) {
        _snack(_isBn ? 'ট্রেড লাইসেন্স আপলোড করুন' : 'Upload your trade license', error: true);
        return;
      }
      garageWorkerCount = int.tryParse(_garageWorkerCountCtrl.text.trim());
      if (garageWorkerCount == null || garageWorkerCount < 0) {
        _snack(_isBn ? 'গ্যারেজে কর্মরত লোকের সংখ্যা দিন' : 'Enter the number of people working at the garage', error: true);
        return;
      }
      if (_hasRecoveryVan != true) {
        _snack(_isBn ? 'রাস্তায় বিকল হওয়া গাড়ির কাছে গাড়ি/লোক পাঠানোর ব্যবস্থা নিশ্চিত করা আবশ্যক' : 'You must confirm you can send a recovery van or someone to a stranded vehicle', error: true);
        return;
      }
      recoveryVanRadiusKm = int.tryParse(_recoveryVanRadiusCtrl.text.trim());
      if (recoveryVanRadiusKm == null || recoveryVanRadiusKm < 0) {
        _snack(_isBn ? 'কত কিলোমিটারের মধ্যে পাঠাতে পারবেন তা লিখুন' : 'Enter within how many kilometers you can send someone', error: true);
        return;
      }
    }
    if (_group == 'IT_COMPUTER' || _group == 'TELECOM') {
      if (_hasShop && (_shopAddressCtrl.text.trim().isEmpty || _shopLat == null || _shopLng == null || _shopTradeLicenseUrl == null)) {
        _snack(_isBn ? 'দোকানের ঠিকানা, অবস্থান ও ট্রেড লাইসেন্স দিন' : 'Add your shop address, location, and trade license', error: true);
        return;
      }
      if (_canVisitCustomerHome != true) {
        _snack(_isBn ? 'গ্রাহকের বাসায় গিয়ে মেরামত করতে পারবেন তা নিশ্চিত করা আবশ্যক' : 'You must confirm you can visit the customer\'s home to fix the product', error: true);
        return;
      }
    }
    if (_group == 'INDUSTRIAL' && !_hasSafetyTraining && years < 2) {
      _snack(_isBn ? 'নিরাপত্তা প্রশিক্ষণ নিশ্চিত করুন অথবা কমপক্ষে ২ বছর অভিজ্ঞতা লিখুন' : 'Confirm safety training, or enter at least 2 years of experience', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await OnboardingService.instance.submitTechnicianDetails(
        group: _group!,
        specializationCodes: _types.toList(),
        experienceYears: years,
        workSamplePhotoUrl: _workSamplePhotoUrl,
        garageAddress: _group == 'AUTOMOTIVE' ? _garageAddressCtrl.text.trim() : null,
        garageLatitude: _garageLat,
        garageLongitude: _garageLng,
        garagePhotoUrl: _garagePhotoUrl,
        hasWorkshop: _group == 'AUTOMOTIVE' ? _hasWorkshop : null,
        tradeLicenseUrl: _group == 'AUTOMOTIVE' ? _tradeLicenseUrl : null,
        garageWorkerCount: _group == 'AUTOMOTIVE' ? garageWorkerCount : null,
        hasRecoveryVan: _group == 'AUTOMOTIVE' ? _hasRecoveryVan : null,
        recoveryVanRadiusKm: _group == 'AUTOMOTIVE' ? recoveryVanRadiusKm : null,
        hasFuelSupply: _group == 'AUTOMOTIVE' ? _hasFuelSupply : null,
        certificateUrl: _certificateUrl,
        hasShop: (_group == 'IT_COMPUTER' || _group == 'TELECOM') ? _hasShop : null,
        shopAddress: (_group == 'IT_COMPUTER' || _group == 'TELECOM') && _hasShop ? _shopAddressCtrl.text.trim() : null,
        shopLatitude: (_group == 'IT_COMPUTER' || _group == 'TELECOM') && _hasShop ? _shopLat : null,
        shopLongitude: (_group == 'IT_COMPUTER' || _group == 'TELECOM') && _hasShop ? _shopLng : null,
        shopTradeLicenseUrl: (_group == 'IT_COMPUTER' || _group == 'TELECOM') && _hasShop ? _shopTradeLicenseUrl : null,
        canVisitCustomerHome: (_group == 'IT_COMPUTER' || _group == 'TELECOM') ? _canVisitCustomerHome : null,
        safetyCertificateUrl: _safetyCertificateUrl,
        hasSafetyTraining: _group == 'INDUSTRIAL' ? _hasSafetyTraining : null,
      );
      if (!mounted) return;
      _snack(_isBn ? 'টেকনিশিয়ান প্রোফাইল সংরক্ষিত হয়েছে' : 'Technician details saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 5),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                    onPressed: () {
                      if (_group != null) {
                        setState(() { _group = null; _types.clear(); });
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  Text(_isBn ? 'টেকনিশিয়ান ক্যাটাগরি' : 'Technician Category', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    if (_loadError != null) {
      return Center(child: Text(_loadError!, style: const TextStyle(color: AppColors.textSecondary)));
    }
    final tax = _taxonomy;
    if (tax == null) return const SizedBox.shrink();

    if (_group == null) return _buildGroupPicker(tax);
    return _buildDetailsForm(tax);
  }

  Widget _buildGroupPicker(TechnicianSpecializationTaxonomy tax) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _isBn ? 'আপনি কোন ক্যাটাগরির টেকনিশিয়ান?' : 'Which category of technician are you?',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        // INDUSTRIAL is temporarily hidden from this picker per the founder ("শিল্পকারখানা
        // আপাতত বাদ দাও") — filtered client-side only, so job-matching/backend hard-stops
        // for it stay intact and it can be re-enabled later by removing this filter.
        ...tax.tree.where((node) => node.group.code != 'INDUSTRIAL').map((node) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => setState(() => _group = node.group.code),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(10)),
                      child: Icon(technicianSpecIcon(node.group.icon), color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_isBn ? node.group.bn : node.group.en, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ]),
                ),
              ),
            )),
      ]),
    );
  }

  Widget _buildDetailsForm(TechnicianSpecializationTaxonomy tax) {
    final node = tax.tree.firstWhere((n) => n.group.code == _group, orElse: () => tax.tree.first);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sectionCard(
          title: _isBn ? 'নির্দিষ্ট কাজের ধরন' : 'Specific specializations',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: node.types.map((t) {
              final active = _types.contains(t.code);
              return GestureDetector(
                onTap: () => setState(() => active ? _types.remove(t.code) : _types.add(t.code)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: active ? AppColors.blueGradient : null,
                    color: active ? null : const Color(0xFFF9F7F0),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                  ),
                  child: Text(_isBn ? t.bn : t.en, style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        sectionCard(
          title: _isBn ? 'অভিজ্ঞতা' : 'Experience',
          child: labeledField(controller: _experienceCtrl, hint: _isBn ? 'অভিজ্ঞতার বছর (যেমন: ২)' : 'Years of experience (e.g. 2)', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ),
        const SizedBox(height: 14),
        ..._groupSpecificFields(),
        const SizedBox(height: 22),
        GlassButton(label: _isBn ? 'সংরক্ষণ করুন' : 'Save', isLoading: _submitting, onPressed: _submitting ? null : _submit),
      ]),
    );
  }

  Widget _yesNoToggle({required String label, required bool? value, required ValueChanged<bool> onChanged}) {
    Widget option(String text, bool v) {
      final active = value == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: active ? AppColors.blueGradient : null,
              color: active ? null : const Color(0xFFF9F7F0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
            ),
            child: Text(text, style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35)),
      const SizedBox(height: 8),
      Row(children: [
        option(_isBn ? 'হ্যাঁ' : 'Yes', true),
        const SizedBox(width: 8),
        option(_isBn ? 'না' : 'No', false),
      ]),
    ]);
  }

  List<Widget> _groupSpecificFields() {
    switch (_group) {
      case 'HOME_ELECTRICAL':
        return [
          sectionCard(
            title: _isBn ? 'কাজের নমুনা ছবি (ঐচ্ছিক)' : 'Work sample photo (optional)',
            child: uploadRow(
              label: _workSamplePhotoUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'ছবি আপলোড করুন' : 'Upload a photo'),
              uploaded: _workSamplePhotoUrl != null,
              loading: _uploadingWorkSample,
              onTap: _uploadWorkSample,
            ),
          ),
        ];
      case 'AUTOMOTIVE':
        return [
          sectionCard(
            title: _isBn ? 'গ্যারেজ/ওয়ার্কশপ' : 'Garage / Workshop',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              labeledField(controller: _garageAddressCtrl, hint: _isBn ? 'গ্যারেজের ঠিকানা' : 'Garage address'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _capturingGarageLocation ? null : _captureGarageLocation,
                icon: _capturingGarageLocation
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_garageLat != null ? Icons.check_circle_rounded : Icons.my_location_rounded, color: _garageLat != null ? const Color(0xFF10B981) : null, size: 18),
                label: Text(_garageLat != null ? (_isBn ? 'অবস্থান যুক্ত হয়েছে' : 'Location captured') : (_isBn ? 'বর্তমান অবস্থান ব্যবহার করুন' : 'Use my current location')),
              ),
              const SizedBox(height: 10),
              uploadRow(
                label: _garagePhotoUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'গ্যারেজের ছবি আপলোড করুন' : 'Upload a photo of your garage'),
                uploaded: _garagePhotoUrl != null,
                loading: _uploadingGaragePhoto,
                onTap: _uploadGaragePhoto,
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => setState(() => _hasWorkshop = !_hasWorkshop),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_hasWorkshop ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: _hasWorkshop ? AppColors.deepBlue : AppColors.textMuted, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isBn ? 'আমার একটি নির্দিষ্ট গ্যারেজ/ওয়ার্কশপ আছে (আবশ্যক)' : 'I have a fixed garage/workshop (required)',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'ট্রেড লাইসেন্স (আবশ্যক)' : 'Trade license (required)',
            child: uploadRow(
              label: _tradeLicenseUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'ট্রেড লাইসেন্স আপলোড করুন' : 'Upload your trade license'),
              uploaded: _tradeLicenseUrl != null,
              loading: _uploadingTradeLicense,
              onTap: _uploadTradeLicense,
            ),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'গ্যারেজের জনবল' : 'Garage staffing',
            child: labeledField(
              controller: _garageWorkerCountCtrl,
              hint: _isBn ? 'গ্যারেজে কতজন কাজ করেন?' : 'Number of people working at the garage',
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'রিকভারি ভ্যান / টো ব্যবস্থা' : 'Recovery van / tow arrangement',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _yesNoToggle(
                label: _isBn
                    ? 'আপনার নিজস্ব রিকভারি ভ্যান আছে বা রাস্তায় বিকল হওয়া গাড়ির কাছে লোক পাঠাতে পারবেন? (আবশ্যক)'
                    : 'Do you have a personal recovery van, or can you arrange to send someone to a stranded vehicle? (required)',
                value: _hasRecoveryVan,
                onChanged: (v) => setState(() => _hasRecoveryVan = v),
              ),
              if (_hasRecoveryVan == true) ...[
                const SizedBox(height: 12),
                labeledField(
                  controller: _recoveryVanRadiusCtrl,
                  hint: _isBn ? 'কত কিলোমিটারের মধ্যে পাঠাতে পারবেন?' : 'Within how many kilometers can you send someone?',
                  keyboardType: TextInputType.number,
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'জ্বালানি সরবরাহ (ঐচ্ছিক)' : 'Fuel supply (optional)',
            child: _yesNoToggle(
              label: _isBn
                  ? 'রাস্তায় বিকল হওয়া গাড়িতে জ্বালানি সরবরাহ করতে পারবেন?'
                  : 'Can you supply fuel to a stranded vehicle in your area?',
              value: _hasFuelSupply,
              onChanged: (v) => setState(() => _hasFuelSupply = v),
            ),
          ),
        ];
      case 'IT_COMPUTER':
      case 'TELECOM':
        return [
          sectionCard(
            title: _isBn ? 'সার্টিফিকেট (ঐচ্ছিক)' : 'Certificate (optional)',
            child: uploadRow(
              label: _certificateUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'সার্টিফিকেট আপলোড করুন' : 'Upload a certificate'),
              uploaded: _certificateUrl != null,
              loading: _uploadingCertificate,
              onTap: _uploadCertificate,
            ),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'দোকান' : 'Shop',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: () => setState(() => _hasShop = !_hasShop),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_hasShop ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: _hasShop ? AppColors.deepBlue : AppColors.textMuted, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isBn ? 'আমার একটি দোকান আছে' : 'I have a shop',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                    ),
                  ),
                ]),
              ),
              if (_hasShop) ...[
                const SizedBox(height: 12),
                labeledField(controller: _shopAddressCtrl, hint: _isBn ? 'দোকানের ঠিকানা' : 'Shop address'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _capturingShopLocation ? null : _captureShopLocation,
                  icon: _capturingShopLocation
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_shopLat != null ? Icons.check_circle_rounded : Icons.my_location_rounded, color: _shopLat != null ? const Color(0xFF10B981) : null, size: 18),
                  label: Text(_shopLat != null ? (_isBn ? 'অবস্থান যুক্ত হয়েছে' : 'Location captured') : (_isBn ? 'বর্তমান অবস্থান ব্যবহার করুন' : 'Use my current location')),
                ),
                const SizedBox(height: 10),
                uploadRow(
                  label: _shopTradeLicenseUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'দোকানের ট্রেড লাইসেন্স আপলোড করুন' : 'Upload your shop trade license'),
                  uploaded: _shopTradeLicenseUrl != null,
                  loading: _uploadingShopTradeLicense,
                  onTap: _uploadShopTradeLicense,
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          sectionCard(
            title: _isBn ? 'হোম ভিজিট' : 'Home visit',
            child: _yesNoToggle(
              label: _isBn
                  ? 'গ্রাহকের বাসায় গিয়ে পণ্য মেরামত করতে পারবেন? (আবশ্যক)'
                  : 'Can you visit the customer\'s home to fix the product? (required)',
              value: _canVisitCustomerHome,
              onChanged: (v) => setState(() => _canVisitCustomerHome = v),
            ),
          ),
        ];
      case 'INDUSTRIAL':
        return [
          sectionCard(
            title: _isBn ? 'নিরাপত্তা প্রশিক্ষণ' : 'Safety training',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              uploadRow(
                label: _safetyCertificateUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'নিরাপত্তা সার্টিফিকেট আপলোড করুন (ঐচ্ছিক)' : 'Upload a safety certificate (optional)'),
                uploaded: _safetyCertificateUrl != null,
                loading: _uploadingSafetyCertificate,
                onTap: _uploadSafetyCertificate,
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => setState(() => _hasSafetyTraining = !_hasSafetyTraining),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_hasSafetyTraining ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: _hasSafetyTraining ? AppColors.deepBlue : AppColors.textMuted, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isBn ? 'আমার নিরাপত্তা প্রশিক্ষণ আছে (না থাকলে কমপক্ষে ২ বছর অভিজ্ঞতা প্রয়োজন)' : 'I have safety training (otherwise at least 2 years of experience is required)',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ];
      default:
        return const [];
    }
  }
}
