import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/commute_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'photographer_profile_screen.dart' show sectionCard, labeledField, uploadRow;

/// Real "become a Commute Partner" onboarding — previously this flow was just a bare
/// verification-request button with zero document/identity collection. Collects the 5
/// mandatory documents (own NID, parent's NID, vehicle registration, driving license,
/// vehicle license) plus an employed/student toggle with the matching pair of text
/// fields, then submits via CommuteService.submitPartnerDetails. Reached from
/// provider_onboarding_screen.dart's "Join as a Commute Partner" tile.
class CommutePartnerOnboardingScreen extends StatefulWidget {
  const CommutePartnerOnboardingScreen({super.key});

  @override
  State<CommutePartnerOnboardingScreen> createState() => _CommutePartnerOnboardingScreenState();
}

class _CommutePartnerOnboardingScreenState extends State<CommutePartnerOnboardingScreen> {
  final _ownPhoneCtrl = TextEditingController();
  final _employerNameCtrl = TextEditingController();
  final _jobIdCtrl = TextEditingController();
  final _instituteNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();

  String? _profilePhotoUrl;
  bool _uploadingProfilePhoto = false;

  String? _ownNidUrl;
  String? _parentNidUrl;
  String? _vehicleRegistrationUrl;
  String? _drivingLicenseUrl;
  String? _vehicleLicenseUrl;

  // null = not chosen yet (mandatory choice)
  String? _employmentStatus;

  final Set<String> _uploading = {};
  bool _submitting = false;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _prefillFromAccount();
  }

  Future<void> _prefillFromAccount() async {
    try {
      final user = await AuthService.instance.getCurrentUser();
      if (!mounted) return;
      setState(() => _ownPhoneCtrl.text = user.phone ?? '');
    } catch (_) {}
  }

  Future<void> _uploadProfilePhoto() async {
    setState(() => _uploadingProfilePhoto = true);
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final url = await AuthService.instance.uploadProviderProfilePhoto(base64Encode(bytes));
      if (mounted) setState(() => _profilePhotoUrl = url);
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploadingProfilePhoto = false);
    }
  }

  @override
  void dispose() {
    _ownPhoneCtrl.dispose();
    _employerNameCtrl.dispose();
    _jobIdCtrl.dispose();
    _instituteNameCtrl.dispose();
    _studentIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload(String key, ValueChanged<String> onUploaded) async {
    setState(() => _uploading.add(key));
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final ext = f.name.split('.').last.toLowerCase();
      final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
      final url = await OnboardingService.instance.uploadFile(fileBase64: base64Encode(bytes), fileName: f.name, mimeType: mime);
      if (mounted) setState(() => onUploaded(url));
    } catch (e) {
      if (mounted) _snack(ApiClient.mapError(e).localized(_isBn), error: true);
    } finally {
      if (mounted) setState(() => _uploading.remove(key));
    }
  }

  Future<void> _submit() async {
    if (_profilePhotoUrl == null) {
      _snack(_isBn ? 'আপনার প্রোফাইল ছবি আপলোড করুন' : 'Upload your profile picture', error: true);
      return;
    }
    if (_ownPhoneCtrl.text.trim().isEmpty) {
      _snack(_isBn ? 'আপনার নিজের ফোন নম্বর লিখুন' : 'Enter your own phone number', error: true);
      return;
    }
    if (_ownNidUrl == null) {
      _snack(_isBn ? 'নিজের NID আপলোড করুন' : 'Upload your own NID', error: true);
      return;
    }
    if (_parentNidUrl == null) {
      _snack(_isBn ? 'বাবা/মায়ের NID আপলোড করুন' : "Upload your parent's NID", error: true);
      return;
    }
    if (_vehicleRegistrationUrl == null) {
      _snack(_isBn ? 'গাড়ির রেজিস্ট্রেশন ডকুমেন্ট আপলোড করুন' : 'Upload the vehicle registration document', error: true);
      return;
    }
    if (_drivingLicenseUrl == null) {
      _snack(_isBn ? 'ড্রাইভিং লাইসেন্স আপলোড করুন' : 'Upload your driving license', error: true);
      return;
    }
    if (_vehicleLicenseUrl == null) {
      _snack(_isBn ? 'ভেহিকল লাইসেন্স আপলোড করুন' : 'Upload the vehicle license', error: true);
      return;
    }
    if (_employmentStatus == null) {
      _snack(_isBn ? 'আপনি চাকরিজীবী নাকি শিক্ষার্থী তা বেছে নিন' : 'Select whether you are employed or a student', error: true);
      return;
    }
    if (_employmentStatus == 'employed') {
      if (_employerNameCtrl.text.trim().isEmpty || _jobIdCtrl.text.trim().isEmpty) {
        _snack(_isBn ? 'প্রতিষ্ঠানের নাম ও জব আইডি দিন' : 'Enter the employer name and job ID', error: true);
        return;
      }
    } else {
      if (_instituteNameCtrl.text.trim().isEmpty || _studentIdCtrl.text.trim().isEmpty) {
        _snack(_isBn ? 'প্রতিষ্ঠানের নাম ও স্টুডেন্ট আইডি দিন' : 'Enter the institute name and student ID', error: true);
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await AuthService.instance.updateProfile(phone: _ownPhoneCtrl.text.trim());
      await CommuteService.instance.submitPartnerDetails(
        ownNidUrl: _ownNidUrl!,
        parentNidUrl: _parentNidUrl!,
        vehicleRegistrationUrl: _vehicleRegistrationUrl!,
        drivingLicenseUrl: _drivingLicenseUrl!,
        vehicleLicenseUrl: _vehicleLicenseUrl!,
        employmentStatus: _employmentStatus!,
        employerName: _employmentStatus == 'employed' ? _employerNameCtrl.text.trim() : null,
        jobId: _employmentStatus == 'employed' ? _jobIdCtrl.text.trim() : null,
        instituteName: _employmentStatus == 'student' ? _instituteNameCtrl.text.trim() : null,
        studentId: _employmentStatus == 'student' ? _studentIdCtrl.text.trim() : null,
      );
      if (!mounted) return;
      _snack(_isBn ? 'আবেদন জমা হয়েছে, যাচাই করা হচ্ছে' : 'Application submitted, under review');
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
              _header(_isBn ? 'কমিউট পার্টনার আবেদন' : 'Commute Partner Application'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionCard(
                      title: _isBn ? 'প্রোফাইল ছবি' : 'Profile picture',
                      child: Row(children: [
                        GestureDetector(
                          onTap: _uploadProfilePhoto,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.glassWhite,
                              border: Border.all(color: _profilePhotoUrl != null ? const Color(0xFF10B981) : AppColors.glassBorder, width: 1.5),
                              image: _profilePhotoUrl != null ? DecorationImage(image: NetworkImage(_profilePhotoUrl!), fit: BoxFit.cover) : null,
                            ),
                            child: _uploadingProfilePhoto
                                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                : (_profilePhotoUrl == null ? const Icon(Icons.add_a_photo_rounded, color: AppColors.textMuted, size: 24) : null),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _profilePhotoUrl != null ? (_isBn ? 'আপলোড হয়েছে ✓' : 'Uploaded ✓') : (_isBn ? 'একটি স্পষ্ট প্রোফাইল ছবি আপলোড করুন — গ্রাহকরা এটা দেখতে পাবেন' : 'Upload a clear profile photo — customers will see this'),
                            style: TextStyle(color: _profilePhotoUrl != null ? const Color(0xFF10B981) : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'আপনার ফোন নম্বর' : 'Your phone number',
                      child: labeledField(controller: _ownPhoneCtrl, hint: _isBn ? 'নিজের ফোন নম্বর' : 'Your own phone number', keyboardType: TextInputType.phone),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'পরিচয় প্রমাণ' : 'Identity documents',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        uploadRow(
                          label: _ownNidUrl != null ? (_isBn ? 'নিজের NID — আপলোড হয়েছে ✓' : 'Own NID — Uploaded ✓') : (_isBn ? 'নিজের NID আপলোড করুন' : 'Upload your own NID'),
                          uploaded: _ownNidUrl != null,
                          loading: _uploading.contains('ownNid'),
                          onTap: () => _pickAndUpload('ownNid', (u) => _ownNidUrl = u),
                        ),
                        const SizedBox(height: 10),
                        uploadRow(
                          label: _parentNidUrl != null ? (_isBn ? "বাবা/মায়ের NID — আপলোড হয়েছে ✓" : "Parent's NID — Uploaded ✓") : (_isBn ? 'বাবা/মায়ের NID আপলোড করুন' : "Upload your parent's (father's or mother's) NID"),
                          uploaded: _parentNidUrl != null,
                          loading: _uploading.contains('parentNid'),
                          onTap: () => _pickAndUpload('parentNid', (u) => _parentNidUrl = u),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'যানবাহন ডকুমেন্ট' : 'Vehicle documents',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        uploadRow(
                          label: _vehicleRegistrationUrl != null ? (_isBn ? 'গাড়ির রেজিস্ট্রেশন — আপলোড হয়েছে ✓' : 'Vehicle registration — Uploaded ✓') : (_isBn ? 'বাইক/গাড়ির রেজিস্ট্রেশন (আপনার নামে) আপলোড করুন' : "Upload the bike/car registration document (in your name)"),
                          uploaded: _vehicleRegistrationUrl != null,
                          loading: _uploading.contains('vehicleReg'),
                          onTap: () => _pickAndUpload('vehicleReg', (u) => _vehicleRegistrationUrl = u),
                        ),
                        const SizedBox(height: 10),
                        uploadRow(
                          label: _drivingLicenseUrl != null ? (_isBn ? 'ড্রাইভিং লাইসেন্স — আপলোড হয়েছে ✓' : 'Driving license — Uploaded ✓') : (_isBn ? 'নিজের ড্রাইভিং লাইসেন্স আপলোড করুন' : 'Upload your own driving license'),
                          uploaded: _drivingLicenseUrl != null,
                          loading: _uploading.contains('drivingLicense'),
                          onTap: () => _pickAndUpload('drivingLicense', (u) => _drivingLicenseUrl = u),
                        ),
                        const SizedBox(height: 10),
                        uploadRow(
                          label: _vehicleLicenseUrl != null ? (_isBn ? 'ভেহিকল লাইসেন্স — আপলোড হয়েছে ✓' : 'Vehicle license — Uploaded ✓') : (_isBn ? 'গাড়ির লাইসেন্স (কমার্শিয়াল/রুট পারমিট) আপলোড করুন' : 'Upload the vehicle license (commercial/route permit)'),
                          uploaded: _vehicleLicenseUrl != null,
                          loading: _uploading.contains('vehicleLicense'),
                          onTap: () => _pickAndUpload('vehicleLicense', (u) => _vehicleLicenseUrl = u),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    sectionCard(
                      title: _isBn ? 'পেশাগত তথ্য' : 'Employment / Student status',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: _toggleOption('employed', _isBn ? 'চাকরিজীবী' : 'Employed')),
                          const SizedBox(width: 10),
                          Expanded(child: _toggleOption('student', _isBn ? 'শিক্ষার্থী' : 'Student')),
                        ]),
                        if (_employmentStatus == 'employed') ...[
                          const SizedBox(height: 14),
                          labeledField(controller: _employerNameCtrl, hint: _isBn ? 'প্রতিষ্ঠান/কোম্পানির নাম' : 'Institution / company name'),
                          const SizedBox(height: 10),
                          labeledField(controller: _jobIdCtrl, hint: _isBn ? 'জব আইডি' : 'Job ID'),
                        ],
                        if (_employmentStatus == 'student') ...[
                          const SizedBox(height: 14),
                          labeledField(controller: _instituteNameCtrl, hint: _isBn ? 'শিক্ষাপ্রতিষ্ঠানের নাম' : 'Institute name'),
                          const SizedBox(height: 10),
                          labeledField(controller: _studentIdCtrl, hint: _isBn ? 'স্টুডেন্ট আইডি' : 'Student ID'),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 22),
                    GlassButton(
                      label: _isBn ? 'আবেদন জমা দিন' : 'Submit Application',
                      isLoading: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleOption(String value, String label) {
    final active = _employmentStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _employmentStatus = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? AppColors.blueGradient : null,
          color: active ? null : const Color(0xFFF9F7F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(color: active ? Colors.white : AppColors.textSecondary, fontSize: 13.5, fontWeight: active ? FontWeight.w700 : FontWeight.w600),
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
