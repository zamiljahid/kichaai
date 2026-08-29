import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'provider_browse_screen.dart';

class MatchRequestScreen extends StatefulWidget {
  // Null means an open broadcast — every eligible provider can see and respond to this
  // request, instead of it being privately targeted at one provider from their profile page.
  final String? providerId;
  final String kind;
  const MatchRequestScreen({super.key, this.providerId, required this.kind});

  @override
  State<MatchRequestScreen> createState() => _MatchRequestScreenState();
}

class _MatchRequestScreenState extends State<MatchRequestScreen> {
  // requestType ('tutor'/'pet_care'/'mess_finder') → the serviceTypeId the backend requires.
  static const _serviceTypeIds = {
    'tutor': 'st_home_tutor',
    'pet_care': 'st_pet_care',
    'mess_finder': 'st_mess_finder',
    'helping_hand': 'st_helping_hand',
  };
  static const _titles = {
    'tutor': 'হোম টিউটর অনুরোধ',
    'pet_care': 'পেট কেয়ার অনুরোধ',
    'mess_finder': 'মেস/আবাসন অনুরোধ',
    'helping_hand': 'গৃহকর্মী অনুরোধ',
  };
  static const _titlesEn = {
    'tutor': 'Home Tutor Request',
    'pet_care': 'Pet Care Request',
    'mess_finder': 'Mess/Housing Request',
    'helping_hand': 'Household Help Request',
  };
  static const _expiryOptions = [3, 7, 14, 30];
  bool _isBn = true;

  final _descController = TextEditingController();
  final _budgetController = TextEditingController();
  DateTime? _preferredDate;
  double? _latitude;
  double? _longitude;
  bool _isLocating = false;
  bool _locationDetected = false;
  bool _isSubmitting = false;
  int _expiresInDays = 7;

  // ── Tutor-only (widget.kind == 'tutor') ──────────────────────────
  // Individual classes, not ranges — a customer needing "Class 7" shouldn't have to guess
  // whether that falls under a "Class 6-8" bucket a tutor may or may not actually teach.
  static const _studentClasses = [
    'প্লে/নার্সারি', 'কেজি', 'ক্লাস ১', 'ক্লাস ২', 'ক্লাস ৩', 'ক্লাস ৪', 'ক্লাস ৫',
    'ক্লাস ৬', 'ক্লাস ৭', 'ক্লাস ৮', 'ক্লাস ৯', 'ক্লাস ১০', 'SSC', 'HSC', 'ভর্তি পরীক্ষা', 'বিশ্ববিদ্যালয়',
  ];
  final _subjectsController = TextEditingController();
  String? _studentClass;
  // Real Bangladeshi education-system medium categories — "বাংলা/English/উভয়" wasn't how
  // customers actually think about this; it's always one of these three tracks.
  static const _mediumMapBn = {
    'বাংলা মাধ্যম': 'bangla',
    'ইংরেজি মাধ্যম': 'english_medium',
    'ইংরেজি ভার্সন': 'english_version',
  };
  static const _mediumMapEn = {
    'Bangla medium': 'bangla',
    'English medium': 'english_medium',
    'English version': 'english_version',
  };
  String _medium = 'bangla';
  int _sessionsPerWeek = 3;
  int _sessionDurationMinutes = 60;
  String _prefersGender = 'any';
  bool _homeTuition = true;
  bool _onlineTuition = false;
  bool _wantsExamPrep = false;
  final _examNameController = TextEditingController();
  static const _tutorTypeMap = {
    'কোনো পার্থক্য নেই': 'any',
    'প্রাইভেট বিশ্ববিদ্যালয়ের শিক্ষক': 'private_university',
    'পাবলিক বিশ্ববিদ্যালয়ের শিক্ষক': 'public_university',
    'পেশাদার টিউটর': 'professional',
  };
  static const _tutorTypeMapEn = {
    'No preference': 'any',
    'Private university teacher': 'private_university',
    'Public university teacher': 'public_university',
    'Professional tutor': 'professional',
  };
  String _tutorType = 'any';

  // ── Helping-hand-only (widget.kind == 'helping_hand') ────────────
  static const _workTypeOptions = {
    'ঘর পরিষ্কার': 'cleaning',
    'রান্না': 'cooking',
    'কাপড় ধোয়া/ইস্ত্রি': 'laundry',
    'বাসন মাজা': 'dishwashing',
    'বাচ্চা দেখাশোনা': 'childcare',
    'বৃদ্ধ/রোগীর সেবা': 'elderly_care',
  };
  static const _workTypeOptionsEn = {
    'Cleaning': 'cleaning',
    'Cooking': 'cooking',
    'Laundry/Ironing': 'laundry',
    'Dishwashing': 'dishwashing',
    'Childcare': 'childcare',
    'Elderly/patient care': 'elderly_care',
  };
  final Set<String> _selectedWorkTypes = {};
  String _engagementType = 'part_time';
  String _salaryType = 'monthly';
  int _daysPerWeek = 6;
  String _hhGender = 'any';
  final _familySizeController = TextEditingController();
  bool _hasChildren = false;
  bool _hasElderly = false;
  bool _hasPets = false;
  final _specialRequirementsController = TextEditingController();

  bool get _isHelpingHand => widget.kind == 'helping_hand';

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  @override
  void dispose() {
    _descController.dispose();
    _budgetController.dispose();
    _subjectsController.dispose();
    _examNameController.dispose();
    _familySizeController.dispose();
    _specialRequirementsController.dispose();
    super.dispose();
  }

  bool get _isTutor => widget.kind == 'tutor';

  static const _genderMap = {
    'কোনো পার্থক্য নেই': 'any',
    'পুরুষ শিক্ষক': 'male',
    'মহিলা শিক্ষক': 'female',
  };
  static const _genderMapEn = {
    'No preference': 'any',
    'Male teacher': 'male',
    'Female teacher': 'female',
  };
  static const _hhGenderMap = {
    'কোনো পার্থক্য নেই': 'any',
    'পুরুষ': 'male',
    'মহিলা': 'female',
  };
  static const _hhGenderMapEn = {
    'No preference': 'any',
    'Male': 'male',
    'Female': 'female',
  };

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      bool ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) { setState(() => _isLocating = false); return; }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _isLocating = false); return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() { _latitude = pos.latitude; _longitude = pos.longitude; _locationDetected = true; _isLocating = false; });
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.deepBlue)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _preferredDate = picked);
  }

  Future<void> _submit() async {
    if (_descController.text.trim().isEmpty) { _showError(_isBn ? 'বিবরণ লিখুন' : 'Enter a description'); return; }

    final serviceTypeId = _serviceTypeIds[widget.kind];
    if (serviceTypeId == null) { _showError(_isBn ? 'অজানা সেবার ধরন' : 'Unknown service type'); return; }

    if (_isTutor) {
      if (_studentClass == null) { _showError(_isBn ? 'ক্লাস/লেভেল বেছে নিন' : 'Choose a class/level'); return; }
      if (_subjectsController.text.trim().isEmpty) { _showError(_isBn ? 'বিষয়(সমূহ) লিখুন' : 'Enter the subject(s)'); return; }
    }
    if (_isHelpingHand && _selectedWorkTypes.isEmpty) {
      _showError(_isBn ? 'অন্তত একটি কাজের ধরন বেছে নিন' : 'Choose at least one work type');
      return;
    }

    final budget = double.tryParse(_budgetController.text.trim());
    setState(() => _isSubmitting = true);
    try {
      final request = await MatchmakingService.instance.createRequest(
        requestType: widget.kind,
        serviceTypeId: serviceTypeId,
        title: (_isBn ? _titles[widget.kind] : _titlesEn[widget.kind]) ?? (_isBn ? 'অনুরোধ' : 'Request'),
        description: _descController.text.trim(),
        budgetMin: budget,
        budgetMax: budget,
        preferredStartDate: _preferredDate?.toIso8601String(),
        serviceLatitude: _latitude,
        serviceLongitude: _longitude,
        // This screen is only ever opened from a specific provider's profile ("Book") — without
        // this the request silently became a public broadcast instead of reaching just them.
        targetProviderId: widget.providerId,
        tutorDetails: _isTutor
            ? {
                'studentClass': _studentClass,
                'subjects': _subjectsController.text.trim(),
                'medium': _medium,
                'sessionsPerWeek': _sessionsPerWeek,
                'sessionDurationMinutes': _sessionDurationMinutes,
                if (_prefersGender != 'any') 'prefersGender': _prefersGender,
                'homeTuition': _homeTuition,
                'onlineTuition': _onlineTuition,
                'wantsExamPrep': _wantsExamPrep,
                if (_wantsExamPrep && _examNameController.text.trim().isNotEmpty) 'examName': _examNameController.text.trim(),
                if (_tutorType != 'any') 'preferredTutorType': _tutorType,
              }
            : null,
        helpingHandDetails: _isHelpingHand
            ? {
                'workTypes': _selectedWorkTypes.toList(),
                'engagementType': _engagementType,
                'salaryType': _salaryType,
                'daysPerWeek': _daysPerWeek,
                if (_hhGender != 'any') 'genderPreference': _hhGender,
                if (_familySizeController.text.trim().isNotEmpty) 'familySize': int.tryParse(_familySizeController.text.trim()),
                'hasChildren': _hasChildren,
                'hasElderly': _hasElderly,
                'hasPets': _hasPets,
                if (_specialRequirementsController.text.trim().isNotEmpty) 'specialRequirements': _specialRequirementsController.text.trim(),
              }
            : null,
      );
      // draft → open, otherwise no provider will ever see this request.
      await MatchmakingService.instance.publishRequest(request.id, expiresInDays: _expiresInDays);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBn ? 'অনুরোধ পাঠানো হয়েছে!' : 'Request sent!', style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory)),
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
              // Only relevant when this screen was reached directly from the service list
              // (open broadcast) — booking a specific provider (widget.providerId set) already
              // came FROM a browse/profile screen, so this link would be redundant there.
              if (widget.providerId == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProviderBrowseScreen(kind: widget.kind, label: (_isBn ? _titles[widget.kind] : _titlesEn[widget.kind]) ?? widget.kind),
                      )),
                      icon: const Icon(Icons.search_rounded, size: 16, color: AppColors.deepBlue),
                      label: Text(_isBn ? 'অথবা বিদ্যমান প্রোভাইডার ব্রাউজ করুন' : 'Or browse existing providers', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(_isBn ? 'বিস্তারিত লিখুন' : 'Enter details'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descController,
                          maxLines: 4,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                          decoration: InputDecoration(hintText: _isBn ? 'আপনার প্রয়োজন বিস্তারিত লিখুন...' : 'Describe what you need...'),
                        ),
                        if (_isTutor) ..._buildTutorFields(),
                        if (_isHelpingHand) ..._buildHelpingHandFields(),
                        const SizedBox(height: 20),
                        _label(_isBn ? 'পছন্দের তারিখ' : 'Preferred date'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppColors.glassWhite,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _preferredDate != null ? AppColors.deepBlue : AppColors.glassBorder, width: 1.5),
                            ),
                            child: Row(children: [
                              Icon(Icons.calendar_today_rounded, color: _preferredDate != null ? AppColors.deepBlue : AppColors.textMuted, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                _preferredDate != null
                                    ? '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}'
                                    : (_isBn ? 'তারিখ বেছে নিন' : 'Choose a date'),
                                style: TextStyle(color: _preferredDate != null ? AppColors.textPrimary : AppColors.textMuted, fontSize: 14),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _label(_isBn ? 'বাজেট (টাকা)' : 'Budget (BDT)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _budgetController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: _isBn ? 'আনুমানিক বাজেট' : 'Estimated budget',
                            prefixIcon: const Icon(Icons.currency_exchange_rounded, color: AppColors.textMuted, size: 20),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _label(_isBn ? 'কতদিন খোলা রাখতে চান?' : 'How long to keep it open?'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: _expiryOptions.map((days) {
                            final active = _expiresInDays == days;
                            return GestureDetector(
                              onTap: () => setState(() => _expiresInDays = days),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: active ? AppColors.blueGradient : null,
                                  color: active ? null : AppColors.glassWhite,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: active ? AppColors.deepBlue : AppColors.glassBorder,
                                    width: active ? 1.5 : 1,
                                  ),
                                ),
                                child: Text(
                                  _isBn ? '$days দিন' : '$days days',
                                  style: TextStyle(
                                    color: active ? AppColors.ivory : AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        _label(_isBn ? 'অবস্থান' : 'Location'),
                        const SizedBox(height: 8),
                        _isLocating
                            ? Row(children: [
                                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue)),
                                const SizedBox(width: 10),
                                Text(_isBn ? 'অবস্থান খুঁজছে...' : 'Locating...', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                              ])
                            : _locationDetected
                                ? Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4), width: 1.5),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.location_pin, color: Color(0xFF22C55E), size: 18),
                                      const SizedBox(width: 8),
                                      Text(_isBn ? 'অবস্থান শনাক্ত হয়েছে' : 'Location detected', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.w600)),
                                    ]),
                                  )
                                : GestureDetector(
                                    onTap: _detectLocation,
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
                                      child: Row(children: [
                                        const Icon(Icons.location_off_rounded, color: AppColors.textMuted, size: 18),
                                        const SizedBox(width: 8),
                                        Text(_isBn ? 'অবস্থান চালু করুন' : 'Turn on location', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                      ]),
                                    ),
                                  ),
                        const SizedBox(height: 24),
                        GlassButton(label: _isBn ? 'অনুরোধ পাঠান' : 'Send request', isLoading: _isSubmitting, onPressed: _submit),
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
          Text(_isBn ? 'অনুরোধ পাঠান' : 'Send Request', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _label(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
  );

  static String _bnDigit(int n) =>
      n.toString().split('').map((d) => '০১২৩৪৫৬৭৮৯'[int.parse(d)]).join();

  // Bilingual variant of _chipRow for maps built as {label: backendCode} — the selected/
  // returned value is always the language-neutral code, while the displayed chip label
  // switches with _isBn, same convention as _workTypeOptions/_workTypeOptionsEn below.
  Widget _codeChipRow(
    Map<String, String> bnMap,
    Map<String, String> enMap,
    String selectedValue,
    ValueChanged<String> onSelect,
  ) {
    final bnEntries = bnMap.entries.toList();
    final enEntries = enMap.entries.toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(bnEntries.length, (i) {
        final code = bnEntries[i].value;
        final label = _isBn ? bnEntries[i].key : enEntries[i].key;
        final active = selectedValue == code;
        return GestureDetector(
          onTap: () => onSelect(code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              gradient: active ? AppColors.blueGradient : null,
              color: active ? null : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
            ),
            child: Text(label, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ),
        );
      }),
    );
  }

  Widget _chipRow(List<String> options, String selected, ValueChanged<String> onSelect) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: options.map((opt) {
      final active = selected == opt;
      return GestureDetector(
        onTap: () => onSelect(opt),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            gradient: active ? AppColors.blueGradient : null,
            color: active ? null : AppColors.glassWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
          ),
          child: Text(opt, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
    }).toList(),
  );

  // Tutor-only fields — studentClass/subjects feed matchmaking-service's TutorDetails, shown to
  // any tutor who opens this request (see match_requests_inbox_screen.dart) and to the customer
  // themselves in my_match_requests_screen.dart. Previously nothing here captured this at all —
  // every tutor request had a description and nothing else structured to search/filter/show.
  List<Widget> _buildTutorFields() => [
    const SizedBox(height: 20),
    _label(_isBn ? 'ক্লাস / লেভেল' : 'Class / Level'),
    const SizedBox(height: 8),
    DropdownButtonFormField<String>(
      initialValue: _studentClass,
      isExpanded: true,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(hintText: _isBn ? 'ক্লাস বেছে নিন' : 'Choose a class'),
      items: _studentClasses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: (v) => setState(() => _studentClass = v),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'বিষয়(সমূহ)' : 'Subject(s)'),
    const SizedBox(height: 8),
    TextFormField(
      controller: _subjectsController,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(hintText: _isBn ? 'যেমন: গণিত, ইংরেজি, বিজ্ঞান' : 'e.g. Math, English, Science'),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'মাধ্যম' : 'Medium'),
    const SizedBox(height: 8),
    _codeChipRow(_mediumMapBn, _mediumMapEn, _medium, (v) => setState(() => _medium = v)),
    const SizedBox(height: 20),
    _label(_isBn ? 'কেমন শিক্ষক খুঁজছেন' : 'What kind of tutor are you looking for'),
    const SizedBox(height: 8),
    _codeChipRow(_tutorTypeMap, _tutorTypeMapEn, _tutorType, (v) => setState(() => _tutorType = v)),
    const SizedBox(height: 20),
    _label(_isBn ? 'সপ্তাহে কয়দিন' : 'Days per week'),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [2, 3, 4, 5, 6].map((n) {
        final active = _sessionsPerWeek == n;
        return GestureDetector(
          onTap: () => setState(() => _sessionsPerWeek = n),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              gradient: active ? AppColors.blueGradient : null,
              color: active ? null : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
            ),
            child: Text(_isBn ? _bnDigit(n) : '$n', style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ),
        );
      }).toList(),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'প্রতি সেশন কতক্ষণ' : 'Minutes per session'),
    const SizedBox(height: 8),
    _chipRow(
      const ['৩০ মিনিট', '৪৫ মিনিট', '৬০ মিনিট', '৯০ মিনিট'],
      switch (_sessionDurationMinutes) { 30 => '৩০ মিনিট', 45 => '৪৫ মিনিট', 90 => '৯০ মিনিট', _ => '৬০ মিনিট' },
      (v) => setState(() => _sessionDurationMinutes = switch (v) { '৩০ মিনিট' => 30, '৪৫ মিনিট' => 45, '৯০ মিনিট' => 90, _ => 60 }),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'শিক্ষক পছন্দ' : 'Teacher preference'),
    const SizedBox(height: 8),
    _codeChipRow(_genderMap, _genderMapEn, _prefersGender, (v) => setState(() => _prefersGender = v)),
    const SizedBox(height: 20),
    _label(_isBn ? 'কোথায় পড়াবেন' : 'Where to teach'),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: CheckboxListTile(
        value: _homeTuition, onChanged: (v) => setState(() => _homeTuition = v ?? true),
        title: Text(_isBn ? 'বাসায় এসে' : 'At home', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
        controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, dense: true,
      )),
      Expanded(child: CheckboxListTile(
        value: _onlineTuition, onChanged: (v) => setState(() => _onlineTuition = v ?? false),
        title: Text(_isBn ? 'অনলাইনে' : 'Online', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
        controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, dense: true,
      )),
    ]),
    CheckboxListTile(
      value: _wantsExamPrep, onChanged: (v) => setState(() => _wantsExamPrep = v ?? false),
      title: Text(_isBn ? 'পরীক্ষার প্রস্তুতি প্রয়োজন' : 'Need exam preparation', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, dense: true,
    ),
    if (_wantsExamPrep) ...[
      const SizedBox(height: 4),
      TextFormField(
        controller: _examNameController,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(hintText: _isBn ? 'কোন পরীক্ষা? যেমন: SSC, HSC, ভর্তি পরীক্ষা' : 'Which exam? e.g. SSC, HSC, admission test'),
      ),
    ],
  ];

  // Helping-hand-only fields — feed matchmaking-service's HelpingHandDetails. v1 scope
  // deliberately excludes live-in (see schema comment on HelpingHandDetails).
  List<Widget> _buildHelpingHandFields() => [
    const SizedBox(height: 20),
    _label(_isBn ? 'কাজের ধরন (একাধিক বেছে নিতে পারেন)' : 'Work type(s) — select all that apply'),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: (_isBn ? _workTypeOptions : _workTypeOptionsEn).entries.map((e) {
        final active = _selectedWorkTypes.contains(e.value);
        return GestureDetector(
          onTap: () => setState(() => active ? _selectedWorkTypes.remove(e.value) : _selectedWorkTypes.add(e.value)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              gradient: active ? AppColors.blueGradient : null,
              color: active ? null : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
            ),
            child: Text(e.key, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ),
        );
      }).toList(),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'এনগেজমেন্ট টাইপ' : 'Engagement type'),
    const SizedBox(height: 8),
    _chipRow(
      _isBn ? ['পার্ট-টাইম', 'ফুল-টাইম (রাতে বাড়ি চলে যায়)'] : ['Part-time', 'Full-time (goes home at night)'],
      _engagementType == 'part_time' ? (_isBn ? 'পার্ট-টাইম' : 'Part-time') : (_isBn ? 'ফুল-টাইম (রাতে বাড়ি চলে যায়)' : 'Full-time (goes home at night)'),
      (v) => setState(() => _engagementType = (v == 'পার্ট-টাইম' || v == 'Part-time') ? 'part_time' : 'full_time_live_out'),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'বেতন কাঠামো' : 'Salary structure'),
    const SizedBox(height: 8),
    _chipRow(
      _isBn ? ['মাসিক', 'দৈনিক', 'ঘণ্টাভিত্তিক'] : ['Monthly', 'Daily', 'Hourly'],
      switch (_salaryType) { 'daily' => (_isBn ? 'দৈনিক' : 'Daily'), 'hourly' => (_isBn ? 'ঘণ্টাভিত্তিক' : 'Hourly'), _ => (_isBn ? 'মাসিক' : 'Monthly') },
      (v) => setState(() => _salaryType = switch (v) { 'দৈনিক' || 'Daily' => 'daily', 'ঘণ্টাভিত্তিক' || 'Hourly' => 'hourly', _ => 'monthly' }),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'সপ্তাহে কয়দিন' : 'Days per week'),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [3, 4, 5, 6, 7].map((n) {
        final active = _daysPerWeek == n;
        return GestureDetector(
          onTap: () => setState(() => _daysPerWeek = n),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              gradient: active ? AppColors.blueGradient : null,
              color: active ? null : AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
            ),
            child: Text(_isBn ? _bnDigit(n) : '$n', style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ),
        );
      }).toList(),
    ),
    const SizedBox(height: 20),
    _label(_isBn ? 'পছন্দ' : 'Preference'),
    const SizedBox(height: 8),
    _codeChipRow(_hhGenderMap, _hhGenderMapEn, _hhGender, (v) => setState(() => _hhGender = v)),
    const SizedBox(height: 20),
    _label(_isBn ? 'পরিবারের সদস্য সংখ্যা (ঐচ্ছিক)' : 'Family size (optional)'),
    const SizedBox(height: 8),
    TextFormField(
      controller: _familySizeController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(hintText: _isBn ? 'যেমন: ৪' : 'e.g. 4'),
    ),
    const SizedBox(height: 12),
    CheckboxListTile(
      value: _hasChildren, onChanged: (v) => setState(() => _hasChildren = v ?? false),
      title: Text(_isBn ? 'বাসায় বাচ্চা আছে' : 'Children at home', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, dense: true,
    ),
    CheckboxListTile(
      value: _hasElderly, onChanged: (v) => setState(() => _hasElderly = v ?? false),
      title: Text(_isBn ? 'বাসায় বয়স্ক/অসুস্থ ব্যক্তি আছে' : 'Elderly/sick person at home', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, dense: true,
    ),
    CheckboxListTile(
      value: _hasPets, onChanged: (v) => setState(() => _hasPets = v ?? false),
      title: Text(_isBn ? 'বাসায় পোষা প্রাণী আছে' : 'Pets at home', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero, dense: true,
    ),
    const SizedBox(height: 8),
    _label(_isBn ? 'বিশেষ প্রয়োজন (ঐচ্ছিক)' : 'Special requirements (optional)'),
    const SizedBox(height: 8),
    TextFormField(
      controller: _specialRequirementsController,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(hintText: _isBn ? 'যেমন: এলার্জি, খাবারের নিয়ম' : 'e.g. allergies, dietary rules'),
    ),
  ];
}
