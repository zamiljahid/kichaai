import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/matchmaking_model.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_button.dart';

/// Provider-side "pull" screen for matchmaking — browse open tutor/pet-care/mess
/// requests and respond to them. Previously this half of the pull-based system had
/// no screen at all: customers could create requests but no provider could ever see
/// or respond to one through the app.
class MatchRequestsInboxScreen extends StatefulWidget {
  const MatchRequestsInboxScreen({super.key});

  @override
  State<MatchRequestsInboxScreen> createState() => _MatchRequestsInboxScreenState();
}

class _MatchRequestsInboxScreenState extends State<MatchRequestsInboxScreen> {
  static const _typeFilters = [
    (null, 'সব', 'All'),
    ('tutor', 'হোম টিউটর', 'Home Tutor'),
    ('pet_care', 'পেট কেয়ার', 'Pet Care'),
    ('mess_finder', 'মেস/আবাসন', 'Mess/Housing'),
    ('helping_hand', 'গৃহকর্মী সেবা', 'Household Help'),
  ];
  static const _typeLabels = {
    'tutor': 'হোম টিউটর',
    'pet_care': 'পেট কেয়ার',
    'mess_finder': 'মেস/আবাসন',
    'helping_hand': 'গৃহকর্মী সেবা',
  };
  static const _typeLabelsEn = {
    'tutor': 'Home Tutor',
    'pet_care': 'Pet Care',
    'mess_finder': 'Mess/Housing',
    'helping_hand': 'Household Help',
  };

  String? _selectedType;
  List<MatchRequestModel> _requests = [];
  bool _isLoading = true;
  String? _loadError;
  bool _isBn = true;

  // Providers previously had no way to check back on a response after submitting it — this
  // second mode fills that gap and is also where they act on incoming meet requests.
  bool _showMyResponses = false;
  List<Map<String, dynamic>> _myResponses = [];
  bool _myResponsesLoading = true;
  final Set<String> _acceptingMeet = {};

  // Tutor-only precision filters — a Math tutor shouldn't have to wade through every
  // subject/class to find requests that actually match what they teach.
  final _subjectController = TextEditingController();
  String? _genderFilter; // null = no filter, 'male' | 'female'
  // Helping-hand-only precision filter — same idea, filtered by work type instead of subject.
  final _workTypeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyResponses();
  }

  Future<void> _loadMyResponses() async {
    setState(() => _myResponsesLoading = true);
    try {
      final list = await MatchmakingService.instance.listMyResponses();
      if (mounted) setState(() { _myResponses = list; _myResponsesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _myResponsesLoading = false);
    }
  }

  Future<void> _acceptMeet(String responseId) async {
    if (_acceptingMeet.contains(responseId)) return;
    setState(() => _acceptingMeet.add(responseId));
    try {
      await MatchmakingService.instance.acceptMeet(responseId);
      if (mounted) _showInfo(_isBn ? 'মিটিং লিংক তৈরি হয়েছে' : 'Meeting link created');
      await _loadMyResponses();
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _acceptingMeet.remove(responseId));
    }
  }

  Future<void> _joinMeet(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _showError(_isBn ? 'মিটিং লিংক খোলা যায়নি' : 'Could not open the meeting link');
    } catch (_) {
      if (mounted) _showError(_isBn ? 'মিটিং লিংক খোলা যায়নি' : 'Could not open the meeting link');
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _workTypeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _loadError = null; });
    try {
      final list = await MatchmakingService.instance.listRequests(
        requestType: _selectedType,
        status: 'open',
        subject: _selectedType == 'tutor' ? _subjectController.text.trim() : null,
        prefersGender: (_selectedType == 'tutor' || _selectedType == 'helping_hand') ? _genderFilter : null,
        workType: _selectedType == 'helping_hand' ? _workTypeController.text.trim() : null,
        browseAsProvider: true,
      );
      if (mounted) setState(() { _requests = list; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _loadError = ApiClient.mapError(e).localized(_isBn); _isLoading = false; });
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

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (_isBn) {
      if (diff.inMinutes < 60) return '${diff.inMinutes} মিনিট আগে';
      if (diff.inHours < 24) return '${diff.inHours} ঘণ্টা আগে';
      return '${diff.inDays} দিন আগে';
    }
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _openResponseSheet(MatchRequestModel request) {
    final coverController = TextEditingController();
    final amountController = TextEditingController();
    String amountType = 'monthly';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.bgMid,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(request.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(request.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
                const SizedBox(height: 18),
                Text(_isBn ? 'আপনার বার্তা' : 'Your message', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: coverController,
                  maxLines: 3,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(hintText: _isBn ? 'নিজের সম্পর্কে ও অভিজ্ঞতা লিখুন...' : 'Write about yourself and your experience...'),
                ),
                const SizedBox(height: 14),
                Text(_isBn ? 'আপনার মূল্য (৳)' : 'Your price (৳)', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _isBn ? 'যেমন ৩০০০' : 'e.g. 3000',
                    prefixIcon: const Icon(Icons.currency_exchange_rounded, color: AppColors.textMuted, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ('fixed', _isBn ? 'একবার' : 'One-time'),
                    ('hourly', _isBn ? 'প্রতি ঘণ্টা' : 'Hourly'),
                    ('monthly', _isBn ? 'মাসিক' : 'Monthly'),
                  ].map((opt) {
                    final active = amountType == opt.$1;
                    return GestureDetector(
                      onTap: () => setSheetState(() => amountType = opt.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: active ? AppColors.blueGradient : null,
                          color: active ? null : AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder),
                        ),
                        child: Text(opt.$2, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                GlassButton(
                  label: _isBn ? 'রেসপন্স পাঠান' : 'Send response',
                  isLoading: isSubmitting,
                  onPressed: () async {
                    setSheetState(() => isSubmitting = true);
                    try {
                      await MatchmakingService.instance.createResponse(
                        request.id,
                        coverMessage: coverController.text.trim().isEmpty ? null : coverController.text.trim(),
                        quotedAmount: double.tryParse(amountController.text.trim()),
                        quotedAmountType: amountType,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showInfo(_isBn ? 'আপনার রেসপন্স পাঠানো হয়েছে!' : 'Your response has been sent!');
                      _load();
                    } catch (e) {
                      setSheetState(() => isSubmitting = false);
                      _showError(ApiClient.mapError(e).localized(_isBn));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              _buildModeToggle(),
              if (!_showMyResponses) ...[
                const SizedBox(height: 10),
                _buildFilterChips(),
                if (_selectedType == 'tutor') ...[
                  const SizedBox(height: 10),
                  _buildTutorFilters(),
                ],
                if (_selectedType == 'helping_hand') ...[
                  const SizedBox(height: 10),
                  _buildHelpingHandFilters(),
                ],
              ],
              const SizedBox(height: 10),
              Expanded(child: _showMyResponses ? _buildMyResponsesBody() : _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_isBn ? 'ম্যাচ অনুরোধ' : 'Match Requests', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(_isBn ? 'টিউটর • পেট কেয়ার • মেস • গৃহকর্মী' : 'Tutor • Pet Care • Mess • Household Help', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _showMyResponses = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: !_showMyResponses ? AppColors.deepBlue : AppColors.glassWhite,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(_isBn ? 'খোলা রিকোয়েস্ট' : 'Open requests', style: TextStyle(color: !_showMyResponses ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _showMyResponses = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _showMyResponses ? AppColors.deepBlue : AppColors.glassWhite,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(_isBn ? 'আমার রেসপন্স' : 'My responses', style: TextStyle(color: _showMyResponses ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildMyResponsesBody() {
    if (_myResponsesLoading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_myResponses.isEmpty) return Center(child: Text(_isBn ? 'আপনি এখনো কোনো রিকোয়েস্টে সাড়া দেননি' : 'You haven\'t responded to any requests yet', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)));
    return RefreshIndicator(
      onRefresh: _loadMyResponses,
      color: AppColors.deepBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _myResponses.length,
        itemBuilder: (_, i) => _buildMyResponseCard(_myResponses[i]),
      ),
    );
  }

  Widget _buildMyResponseCard(Map<String, dynamic> resp) {
    final req = resp['request'] as Map<String, dynamic>?;
    final status = resp['status'] as String? ?? 'interested';
    final meetRequestedAt = resp['meetRequestedAt'];
    final meetLink = resp['meetLink'] as String?;
    final responseId = resp['id'] as String;
    final accepting = _acceptingMeet.contains(responseId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.glassBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(req?['title'] as String? ?? '—', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.deepBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: const TextStyle(color: AppColors.deepBlue, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (resp['quotedAmount'] != null) ...[
          const SizedBox(height: 4),
          Text('৳${resp['quotedAmount']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
        if (meetRequestedAt != null && meetLink == null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: _isBn ? 'মিটিং-এ রাজি হন' : 'Accept the meet request',
              isLoading: accepting,
              onPressed: accepting ? null : () => _acceptMeet(responseId),
            ),
          ),
        ],
        if (meetLink != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _joinMeet(meetLink),
              icon: const Icon(Icons.video_camera_front_rounded, color: Color(0xFF10B981), size: 16),
              label: Text(_isBn ? 'মিটিং-এ যোগ দিন' : 'Join the meet', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF10B981)), padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _typeFilters.map((f) {
          final active = _selectedType == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () { setState(() => _selectedType = f.$1); _load(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: active ? AppColors.blueGradient : null,
                  color: active ? null : AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder, width: active ? 1.5 : 1),
                ),
                child: Text(_isBn ? f.$2 : f.$3, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTutorFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _subjectController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                isDense: true,
                hintText: _isBn ? 'বিষয় খুঁজুন (যেমন Math)...' : 'Search subject (e.g. Math)...',
                hintStyle: const TextStyle(fontSize: 12.5),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.glassWhite,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
                suffixIcon: _subjectController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                        onPressed: () { _subjectController.clear(); _load(); },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _genderChip(null, _isBn ? 'সবাই' : 'Any'),
        const SizedBox(width: 6),
        _genderChip('male', _isBn ? 'পুরুষ' : 'Male'),
        const SizedBox(width: 6),
        _genderChip('female', _isBn ? 'নারী' : 'Female'),
      ]),
    );
  }

  Widget _buildHelpingHandFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _workTypeController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                isDense: true,
                hintText: _isBn ? 'কাজের ধরন (যেমন cooking)...' : 'Work type (e.g. cooking)...',
                hintStyle: const TextStyle(fontSize: 12.5),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.glassWhite,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
                suffixIcon: _workTypeController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                        onPressed: () { _workTypeController.clear(); _load(); },
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _genderChip(null, _isBn ? 'সবাই' : 'Any'),
        const SizedBox(width: 6),
        _genderChip('male', _isBn ? 'পুরুষ' : 'Male'),
        const SizedBox(width: 6),
        _genderChip('female', _isBn ? 'নারী' : 'Female'),
      ]),
    );
  }

  Widget _genderChip(String? value, String label) {
    final active = _genderFilter == value;
    return GestureDetector(
      onTap: () { setState(() => _genderFilter = value); _load(); },
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? AppColors.blueGradient : null,
          color: active ? null : AppColors.glassWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? AppColors.deepBlue : AppColors.glassBorder),
        ),
        child: Text(label, style: TextStyle(color: active ? AppColors.ivory : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    }
    if (_loadError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_isBn ? 'লোড করা যায়নি: $_loadError' : 'Could not load: $_loadError', style: const TextStyle(color: AppColors.textMuted, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          TextButton(onPressed: _load, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again', style: const TextStyle(color: AppColors.deepBlue))),
        ]),
      );
    }
    if (_requests.isEmpty) {
      return Center(
        child: Text(_isBn ? 'এই মুহূর্তে কোনো খোলা অনুরোধ নেই' : 'No open requests right now', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.deepBlue,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _requests.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _openResponseSheet(_requests[i]),
            child: _buildRequestCard(_requests[i]),
          ),
        ),
      ),
    );
  }

  String? _genderLabel(dynamic g, {bool forHelpingHand = false}) {
    if (g == 'male') return forHelpingHand ? (_isBn ? 'পুরুষ কাম্য' : 'Male preferred') : (_isBn ? 'পুরুষ টিউটর কাম্য' : 'Male tutor preferred');
    if (g == 'female') return forHelpingHand ? (_isBn ? 'নারী কাম্য' : 'Female preferred') : (_isBn ? 'নারী টিউটর কাম্য' : 'Female tutor preferred');
    return null;
  }

  // 'bangla'/'english_medium'/'english_version' are the codes newer requests store; older
  // requests (created before medium became language-neutral) still hold the raw label text,
  // so an unrecognized value just falls back to showing it as-is.
  static const _mediumLabels = {
    'bangla': 'বাংলা মাধ্যম', 'english_medium': 'ইংরেজি মাধ্যম', 'english_version': 'ইংরেজি ভার্সন',
  };
  static const _mediumLabelsEn = {
    'bangla': 'Bangla medium', 'english_medium': 'English medium', 'english_version': 'English version',
  };

  Widget _tutorDetailsRow(Map<String, dynamic> d) {
    final medium = d['medium'] as String?;
    final bits = <String>[
      if (d['studentClass'] != null) d['studentClass'] as String,
      if (d['subjects'] != null) d['subjects'] as String,
      if (medium != null) ((_isBn ? _mediumLabels : _mediumLabelsEn)[medium] ?? medium),
      if (d['sessionsPerWeek'] != null) (_isBn ? 'সপ্তাহে ${d['sessionsPerWeek']} দিন' : '${d['sessionsPerWeek']} days/week'),
      if (_genderLabel(d['prefersGender']) != null) _genderLabel(d['prefersGender'])!,
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: bits.map((b) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.deepBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Text(b, style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w600)),
      )).toList(),
    );
  }

  static const _workTypeLabels = {
    'cleaning': 'ঘর পরিষ্কার', 'cooking': 'রান্না', 'laundry': 'কাপড় ধোয়া/ইস্ত্রি',
    'dishwashing': 'বাসন মাজা', 'childcare': 'বাচ্চা দেখাশোনা', 'elderly_care': 'বৃদ্ধ/রোগীর সেবা',
  };
  static const _workTypeLabelsEn = {
    'cleaning': 'Cleaning', 'cooking': 'Cooking', 'laundry': 'Laundry/ironing',
    'dishwashing': 'Dishwashing', 'childcare': 'Childcare', 'elderly_care': 'Elderly/patient care',
  };

  Widget _helpingHandDetailsRow(Map<String, dynamic> d) {
    final workTypes = (d['workTypes'] as List?)?.cast<String>() ?? [];
    final bits = <String>[
      ...workTypes.map((w) => (_isBn ? _workTypeLabels[w] : _workTypeLabelsEn[w]) ?? w),
      if (d['engagementType'] == 'full_time_live_out') (_isBn ? 'ফুল-টাইম' : 'Full-time') else (_isBn ? 'পার্ট-টাইম' : 'Part-time'),
      if (d['salaryType'] != null) (_isBn ? switch (d['salaryType']) { 'daily' => 'দৈনিক বেতন', 'hourly' => 'ঘণ্টাভিত্তিক বেতন', _ => 'মাসিক বেতন' } : '${d['salaryType']} salary'),
      if (_genderLabel(d['genderPreference'], forHelpingHand: true) != null) _genderLabel(d['genderPreference'], forHelpingHand: true)!,
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: bits.map((b) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.deepBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Text(b, style: const TextStyle(color: AppColors.deepBlue, fontSize: 11, fontWeight: FontWeight.w600)),
      )).toList(),
    );
  }

  Widget _buildRequestCard(MatchRequestModel r) {
    final budget = r.budgetMin != null || r.budgetMax != null
        ? '৳${(r.budgetMin ?? r.budgetMax)!.toStringAsFixed(0)}${r.budgetMax != null && r.budgetMin != null && r.budgetMax != r.budgetMin ? '-${r.budgetMax!.toStringAsFixed(0)}' : ''}'
        : null;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.deepBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text((_isBn ? _typeLabels[r.requestType] : _typeLabelsEn[r.requestType]) ?? r.requestType, style: const TextStyle(color: AppColors.deepBlue, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            Text(_timeAgo(r.createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Text(r.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
          if (r.requestType == 'tutor' && r.tutorDetails != null) ...[
            const SizedBox(height: 8),
            _tutorDetailsRow(r.tutorDetails!),
          ],
          if (r.requestType == 'helping_hand' && r.helpingHandDetails != null) ...[
            const SizedBox(height: 8),
            _helpingHandDetailsRow(r.helpingHandDetails!),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (budget != null) ...[
              const Icon(Icons.currency_exchange_rounded, color: AppColors.textMuted, size: 14),
              const SizedBox(width: 4),
              Text(budget, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
            ],
            const Icon(Icons.people_outline_rounded, color: AppColors.textMuted, size: 14),
            const SizedBox(width: 4),
            Text(_isBn ? '${r.responseCount}/${r.maxResponses} রেসপন্স' : '${r.responseCount}/${r.maxResponses} responses', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}
