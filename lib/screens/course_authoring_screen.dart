import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../core/network/api_client.dart';
import '../models/micro_learning_model.dart';
import '../services/micro_learning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// Instructor-facing course authoring: list my courses, create a course,
/// then manage its lessons + schedule a live session.
class CourseAuthoringScreen extends StatefulWidget {
  const CourseAuthoringScreen({super.key});

  @override
  State<CourseAuthoringScreen> createState() => _CourseAuthoringScreenState();
}

const _categories = [
  ['tech', 'প্রযুক্তি'],
  ['language', 'ভাষা'],
  ['business', 'ব্যবসা'],
  ['arts', 'কলা ও নকশা'],
  ['lifestyle', 'লাইফস্টাইল'],
  ['other', 'অন্যান্য'],
];

class _CourseAuthoringScreenState extends State<CourseAuthoringScreen> {
  final _svc = MicroLearningService.instance;
  bool _loading = true;
  String? _error;
  List<CourseModel> _courses = [];
  String? _userId;
  String? _fullName;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    _fullName = await ApiClient.getFullName();
    await _load();
  }

  Future<void> _load() async {
    if (_userId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final courses = await _svc.listMyCourses(_userId!);
      if (mounted) setState(() { _courses = courses; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCourse,
        backgroundColor: AppColors.deepBlue,
        icon: const Icon(Icons.add_rounded, color: AppColors.ivory),
        label: const Text('নতুন কোর্স', style: TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w700)),
      ),
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 20, 12),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder, width: 1.5),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('আমার কোর্স', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
              Text('Instructor studio', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
        ]),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('আবার চেষ্টা করুন')),
        ]),
      ));
    }
    if (_courses.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.menu_book_rounded, color: AppColors.textMuted, size: 56),
        const SizedBox(height: 14),
        const Text('এখনো কোনো কোর্স নেই', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
        const SizedBox(height: 6),
        const Text('“নতুন কোর্স” দিয়ে শুরু করুন', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ]));
    }
    return RefreshIndicator(
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: _courses.length,
        itemBuilder: (_, i) => _courseCard(_courses[i], i),
      ),
    );
  }

  static const _statusLabelsBn = {
    'draft': 'খসড়া', 'pending_review': 'পর্যালোচনাধীন', 'published': 'প্রকাশিত', 'archived': 'আর্কাইভড',
  };

  Widget _courseCard(CourseModel c, int index) {
    final statusColor = c.status == 'published'
        ? const Color(0xFF10B981)
        : c.status == 'pending_review'
            ? const Color(0xFFF59E0B)
            : c.status == 'archived'
                ? const Color(0xFFEF4444)
                : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => _CourseLessonsScreen(courseId: c.id, courseTitle: c.title),
          ));
          _load();
        },
        onLongPress: () => _showEditCourse(c),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.play_lesson_rounded, color: AppColors.ivory, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                      child: Text(_statusLabelsBn[c.status] ?? c.status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text('${c.lessons.isNotEmpty ? c.lessons.length : (c.totalLessons ?? 0)} লেসন',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(width: 8),
                    Text('৳${c.price.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
            ]),
            if (c.status == 'draft' && c.rejectionReason != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                child: Text('বাতিলের কারণ: ${c.rejectionReason}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
              ),
            ],
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _CourseEnrollmentsScreen(courseId: c.id, courseTitle: c.title),
              )),
              child: Row(children: [
                const Icon(Icons.people_alt_rounded, color: AppColors.deepBlue, size: 15),
                const SizedBox(width: 6),
                Text('${c.enrollmentCount ?? 0} জন শিক্ষার্থী — তালিকা দেখুন',
                    style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
            // Providers self-publish directly — no admin approval step. Without this button a
            // draft course could never go live at all (nothing else ever sets status:published).
            if (c.status == 'draft') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _publishCourse(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.deepBlue,
                    side: const BorderSide(color: AppColors.deepBlue),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('প্রকাশ করুন', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ]),
        ),
      ),
    ).animate(delay: Duration(milliseconds: 40 * index)).fadeIn(duration: 260.ms).slideY(begin: 0.05);
  }

  Future<void> _publishCourse(CourseModel c) async {
    if (c.lessons.isEmpty && (c.totalLessons ?? 0) == 0) {
      _snack('প্রকাশ করার আগে অন্তত একটি লেসন যোগ করুন', error: true);
      return;
    }
    try {
      await _svc.updateCourse(c.id, {'status': 'published'});
      _snack('কোর্স প্রকাশিত হয়েছে — কাস্টমাররা এখন দেখতে পাবে');
      _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  /// Long-press a course card → edit its metadata (PATCH, only changed fields).
  void _showEditCourse(CourseModel c) {
    final titleCtrl = TextEditingController(text: c.title);
    final descCtrl = TextEditingController(text: c.description);
    final priceCtrl = TextEditingController(text: c.price.toStringAsFixed(0));
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.bgMid,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 18),
                const Text('কোর্স সম্পাদনা করুন', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                _field(titleCtrl, 'কোর্সের নাম'),
                const SizedBox(height: 12),
                _field(descCtrl, 'বিবরণ', maxLines: 3),
                const SizedBox(height: 12),
                _field(priceCtrl, 'মূল্য (৳)', keyboard: TextInputType.number),
                const SizedBox(height: 22),
                GlassButton(
                  label: 'সংরক্ষণ করুন',
                  isLoading: saving,
                  onPressed: saving ? null : () async {
                    final title = titleCtrl.text.trim();
                    final desc = descCtrl.text.trim();
                    final price = double.tryParse(priceCtrl.text.trim());
                    if (title.isEmpty || desc.isEmpty || price == null) {
                      _snack('নাম, বিবরণ ও মূল্য দিন', error: true);
                      return;
                    }
                    // PATCH semantics — only send what actually changed.
                    final changes = <String, dynamic>{
                      if (title != c.title) 'title': title,
                      if (desc != c.description) 'description': desc,
                      if (price != c.price) 'price': price,
                    };
                    if (changes.isEmpty) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      return;
                    }
                    setS(() => saving = true);
                    try {
                      await _svc.updateCourse(c.id, changes);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('কোর্স আপডেট হয়েছে');
                      _load();
                    } catch (e) {
                      setS(() => saving = false);
                      _snack(e.toString(), error: true);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateCourse() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final discountCtrl = TextEditingController();
    final minEnrollCtrl = TextEditingController(text: '5');
    String category = 'tech';
    // recorded = pre-uploaded video lessons, access immediately on enrollment.
    // live_cohort = a live class the provider runs once enough students join — no video.
    String courseType = 'recorded';
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.bgMid,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 18),
                const Text('নতুন কোর্স তৈরি করুন', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                _field(titleCtrl, 'কোর্সের নাম'),
                const SizedBox(height: 12),
                _field(descCtrl, 'বিবরণ', maxLines: 3),
                const SizedBox(height: 12),
                const Text('বিভাগ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _categories.map((cat) {
                  final sel = category == cat[0];
                  return GestureDetector(
                    onTap: () => setS(() => category = cat[0]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: sel ? AppColors.blueGradient : null,
                        color: sel ? null : AppColors.glassWhite,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: sel ? Colors.transparent : AppColors.glassBorder),
                      ),
                      child: Text(cat[1], style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(priceCtrl, 'মূল্য (৳)', keyboard: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(discountCtrl, 'ছাড় মূল্য (ঐচ্ছিক)', keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 16),
                const Text('কোর্সের ধরন', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _typeChip('রেকর্ডেড ভিডিও', 'recorded', courseType, (v) => setS(() => courseType = v))),
                  const SizedBox(width: 8),
                  Expanded(child: _typeChip('লাইভ সেশন', 'live_cohort', courseType, (v) => setS(() => courseType = v))),
                ]),
                if (courseType == 'live_cohort') ...[
                  const SizedBox(height: 10),
                  Text('ভিডিও লেসন নেই — যথেষ্ট শিক্ষার্থী ভর্তি হলে আপনি একটা লাইভ ক্লাস করাবেন।',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 10),
                  _field(minEnrollCtrl, 'কতজন ভর্তি হলে সেশন খোলা হবে', keyboard: TextInputType.number),
                ],
                const SizedBox(height: 22),
                GlassButton(
                  label: 'তৈরি করুন',
                  isLoading: saving,
                  onPressed: saving ? null : () async {
                    final title = titleCtrl.text.trim();
                    final desc = descCtrl.text.trim();
                    final price = double.tryParse(priceCtrl.text.trim());
                    if (title.isEmpty || desc.isEmpty || price == null) {
                      _snack('নাম, বিবরণ ও মূল্য দিন', error: true);
                      return;
                    }
                    final minEnroll = courseType == 'live_cohort' ? int.tryParse(minEnrollCtrl.text.trim()) : null;
                    if (courseType == 'live_cohort' && (minEnroll == null || minEnroll < 1)) {
                      _snack('সঠিক শিক্ষার্থী সংখ্যা দিন', error: true);
                      return;
                    }
                    setS(() => saving = true);
                    try {
                      await _svc.createCourse(
                        providerId: _userId ?? '',
                        providerName: _fullName ?? 'Instructor',
                        title: title,
                        description: desc,
                        category: category,
                        price: price,
                        discountPrice: double.tryParse(discountCtrl.text.trim()),
                        type: courseType,
                        minEnrollments: minEnroll,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('কোর্স তৈরি হয়েছে — এখন লেসন যোগ করুন');
                      _load();
                    } catch (e) {
                      setS(() => saving = false);
                      _snack(e.toString(), error: true);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _field(TextEditingController c, String hint, {int maxLines = 1, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: AppColors.glassWhite,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.deepBlue)),
      ),
    );
  }

  static Widget _typeChip(String label, String value, String current, void Function(String) onTap) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: sel ? AppColors.blueGradient : null,
          color: sel ? null : AppColors.glassWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? Colors.transparent : AppColors.glassBorder),
        ),
        child: Text(label, style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Lesson management for one course ──────────────────────────────

class _CourseLessonsScreen extends StatefulWidget {
  final String courseId;
  final String courseTitle;
  const _CourseLessonsScreen({required this.courseId, required this.courseTitle});

  @override
  State<_CourseLessonsScreen> createState() => _CourseLessonsScreenState();
}

class _CourseLessonsScreenState extends State<_CourseLessonsScreen> {
  final _svc = MicroLearningService.instance;
  bool _loading = true;
  List<LessonModel> _lessons = [];
  String? _courseType;
  Map<String, dynamic>? _liveSession;
  bool _liveActionBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final course = await _svc.getCourse(widget.courseId);
      final lessons = [...course.lessons]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      Map<String, dynamic>? liveSession;
      if (course.deliveryMode == 'live_cohort') {
        try {
          liveSession = await _svc.getLiveSession(widget.courseId);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _lessons = lessons;
          _courseType = course.deliveryMode;
          _liveSession = liveSession;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestEarlyLiveSession() async {
    setState(() => _liveActionBusy = true);
    try {
      await _svc.requestEarlyLiveSession(widget.courseId);
      _snack('মিটিং লিংক সেট করার জন্য অনুরোধ পাঠানো হয়েছে — এখন শিডিউল করুন');
      await _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _liveActionBusy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLessonSheet(),
        backgroundColor: AppColors.deepBlue,
        icon: const Icon(Icons.add_rounded, color: AppColors.ivory),
        label: const Text('লেসন', style: TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w700)),
      ),
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 20, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(widget.courseTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700))),
              ]),
            ),
            if (_courseType == 'live_cohort') _liveSessionSection(),
            Expanded(child: _body()),
          ]),
        ),
      ),
    );
  }

  Widget _liveSessionSection() {
    final status = _liveSession?['status'] as String?;
    Widget content;
    if (status == null) {
      // No pending/scheduled session yet — either minEnrollments hasn't been hit,
      // or the provider hasn't asked for a link early. Both funnel into the same action.
      content = GlassButton(
        label: 'মিটিং লিংকের জন্য এখনই অনুরোধ করুন',
        icon: Icons.add_link_rounded,
        isOutlined: true,
        isLoading: _liveActionBusy,
        onPressed: _liveActionBusy ? null : _requestEarlyLiveSession,
      );
    } else if (status == 'pending') {
      content = GlassButton(
        label: 'লাইভ সেশন শিডিউল করুন',
        icon: Icons.videocam_rounded,
        isOutlined: true,
        onPressed: _showScheduleLive,
      );
    } else if (status == 'scheduled') {
      final scheduledAt = _liveSession?['scheduledAt'] as String?;
      final meetingUrl = _liveSession?['meetingUrl'] as String?;
      content = GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          const Icon(Icons.videocam_rounded, color: AppColors.deepBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('লাইভ সেশন শিডিউল হয়েছে', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
              if (scheduledAt != null)
                Text(scheduledAt.substring(0, 16).replaceFirst('T', ' '), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (meetingUrl != null)
                Text(meetingUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
        ]),
      );
    } else {
      content = const GlassCard(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
          SizedBox(width: 10),
          Text('লাইভ সেশন সম্পন্ন হয়েছে', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: content,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_lessons.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('এখনো কোনো লেসন নেই — “লেসন” বাটনে যোগ করুন', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
      ));
    }
    return RefreshIndicator(
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: _lessons.length,
        itemBuilder: (_, i) => _lessonTile(_lessons[i], i),
      ),
    );
  }

  Widget _lessonTile(LessonModel l, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.glassBorder)),
            child: Text('${index + 1}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                if (l.durationMinutes != null) ...[
                  const Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 12),
                  const SizedBox(width: 3),
                  Text('${l.durationMinutes} মিনিট', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(width: 8),
                ],
                if (l.isFree) ...[
                  const Text('ফ্রি প্রিভিউ', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                ],
                if (l.videoProcessingStatus == 'processing' || l.videoProcessingStatus == 'uploaded')
                  const Text('ওয়াটারমার্ক প্রসেসিং হচ্ছে...', style: TextStyle(color: Color(0xFFD98A0B), fontSize: 11)),
                if (l.videoProcessingStatus == 'failed')
                  const Text('ভিডিও প্রসেসিং ব্যর্থ হয়েছে', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
              ]),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.textMuted, size: 18),
            onPressed: () => _showLessonSheet(existing: l),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
            onPressed: () => _deleteLesson(l),
          ),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: 30 * index)).fadeIn(duration: 240.ms).slideX(begin: 0.04);
  }

  Future<void> _deleteLesson(LessonModel l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('লেসন মুছবেন?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('“${l.title}” মুছে ফেলা হবে।', style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('মুছুন', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.deleteLesson(l.id);
      _snack('লেসন মুছে ফেলা হয়েছে');
      _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  void _showLessonSheet({LessonModel? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final videoCtrl = TextEditingController(text: existing?.videoUrl ?? '');
    final durationCtrl = TextEditingController(text: existing?.durationMinutes?.toString() ?? '');
    bool isFree = existing?.isFree ?? false;
    bool saving = false;
    XFile? pickedVideo;
    String? uploadStage; // null | 'picking' | 'uploading' | 'processing'

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              Text(existing == null ? 'নতুন লেসন' : 'লেসন সম্পাদনা',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              _CourseAuthoringScreenState._field(titleCtrl, 'লেসনের নাম'),
              const SizedBox(height: 12),
              const Text('ভিডিও (আপলোড করলে স্বয়ংক্রিয়ভাবে KiChaai ওয়াটারমার্ক যুক্ত হয়)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: uploadStage != null ? null : () async {
                  final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
                  if (file != null) setS(() => pickedVideo = file);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
                  child: Row(children: [
                    Icon(pickedVideo != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                        color: pickedVideo != null ? const Color(0xFF10B981) : AppColors.textMuted, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pickedVideo != null ? pickedVideo!.name : (existing?.videoProcessingStatus == 'ready' ? 'ভিডিও সেট করা আছে — বদলাতে চাপুন' : 'ভিডিও ফাইল বাছুন'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pickedVideo != null ? AppColors.textPrimary : AppColors.textMuted, fontSize: 14),
                      ),
                    ),
                  ]),
                ),
              ),
              if (existing != null && (existing.videoProcessingStatus == 'processing' || existing.videoProcessingStatus == 'uploaded')) ...[
                const SizedBox(height: 6),
                const Text('আগের ভিডিওটি এখনো ওয়াটারমার্ক প্রসেসিং হচ্ছে...', style: TextStyle(color: Color(0xFFD98A0B), fontSize: 11)),
              ],
              const SizedBox(height: 12),
              const Text('অথবা বাইরের ভিডিও লিংক (YouTube/Drive) — এতে কোনো সুরক্ষা/watermark থাকবে না',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 6),
              _CourseAuthoringScreenState._field(videoCtrl, 'ভিডিও লিংক (ঐচ্ছিক)', keyboard: TextInputType.url),
              const SizedBox(height: 12),
              _CourseAuthoringScreenState._field(durationCtrl, 'সময়কাল (মিনিট)', keyboard: TextInputType.number),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.deepBlue,
                title: const Text('ফ্রি প্রিভিউ', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                value: isFree,
                onChanged: (v) => setS(() => isFree = v),
              ),
              const SizedBox(height: 12),
              GlassButton(
                label: uploadStage == 'uploading' ? 'ভিডিও আপলোড হচ্ছে...' : (existing == null ? 'যোগ করুন' : 'সংরক্ষণ করুন'),
                isLoading: saving,
                onPressed: saving ? null : () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) { _snack('লেসনের নাম দিন', error: true); return; }
                  final dur = int.tryParse(durationCtrl.text.trim());
                  final video = videoCtrl.text.trim().isNotEmpty ? videoCtrl.text.trim() : null;
                  setS(() => saving = true);
                  try {
                    String? rawVideoKey;
                    if (pickedVideo != null) {
                      setS(() => uploadStage = 'uploading');
                      final bytes = await pickedVideo!.readAsBytes();
                      final urlInfo = await _svc.requestVideoUploadUrl(
                        courseId: widget.courseId,
                        filename: pickedVideo!.name,
                        contentType: pickedVideo!.mimeType,
                      );
                      await _svc.uploadVideoBytes(urlInfo['uploadUrl']!, bytes, contentType: pickedVideo!.mimeType);
                      rawVideoKey = urlInfo['key'];
                    }
                    if (existing == null) {
                      await _svc.addLesson(
                        courseId: widget.courseId,
                        title: title,
                        videoUrl: rawVideoKey == null ? video : null,
                        rawVideoKey: rawVideoKey,
                        durationMins: dur,
                        sortOrder: _lessons.length + 1,
                        isFree: isFree,
                      );
                    } else {
                      await _svc.updateLesson(existing.id, {
                        'title': title,
                        if (rawVideoKey != null) 'rawVideoKey': rawVideoKey
                        else if (video != null) 'videoUrl': video,
                        if (dur != null) 'durationMins': dur,
                        'isFree': isFree,
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack(rawVideoKey != null
                        ? 'লেসন সংরক্ষণ হয়েছে — ভিডিও ওয়াটারমার্ক প্রসেসিং চলছে'
                        : (existing == null ? 'লেসন যোগ হয়েছে' : 'লেসন আপডেট হয়েছে'));
                    _load();
                  } catch (e) {
                    setS(() { saving = false; uploadStage = null; });
                    _snack(e.toString(), error: true);
                  }
                },
              ),
              const SizedBox(height: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showScheduleLive() {
    final urlCtrl = TextEditingController();
    DateTime? when;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: AppColors.bgMid, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              const Text('লাইভ সেশন শিডিউল', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d == null) return;
                  if (!ctx.mounted) return;
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                  if (t == null) return;
                  setS(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, color: AppColors.textMuted, size: 18),
                    const SizedBox(width: 10),
                    Text(when == null ? 'তারিখ ও সময় বাছুন' : when!.toString().substring(0, 16),
                        style: TextStyle(color: when == null ? AppColors.textMuted : AppColors.textPrimary, fontSize: 14)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _CourseAuthoringScreenState._field(urlCtrl, 'মিটিং লিংক (Google Meet/Zoom)', keyboard: TextInputType.url),
              const SizedBox(height: 22),
              GlassButton(
                label: 'শিডিউল করুন',
                isLoading: saving,
                onPressed: saving ? null : () async {
                  final url = urlCtrl.text.trim();
                  if (when == null || !url.startsWith('http')) {
                    _snack('তারিখ ও সঠিক মিটিং লিংক দিন', error: true);
                    return;
                  }
                  setS(() => saving = true);
                  try {
                    await _svc.scheduleLiveSession(widget.courseId,
                        scheduledAt: when!.toUtc().toIso8601String(), meetingUrl: url);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('লাইভ সেশন শিডিউল হয়েছে');
                  } catch (e) {
                    setS(() => saving = false);
                    _snack(e.toString(), error: true);
                  }
                },
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Who's enrolled — reachable from the course card AND from the "নতুন ভর্তি!"
// notification. Before this there was no screen at all showing WHO enrolled,
// only a generic push saying "someone did".
class _CourseEnrollmentsScreen extends StatefulWidget {
  final String courseId;
  final String courseTitle;
  const _CourseEnrollmentsScreen({required this.courseId, required this.courseTitle});

  @override
  State<_CourseEnrollmentsScreen> createState() => _CourseEnrollmentsScreenState();
}

class _CourseEnrollmentsScreenState extends State<_CourseEnrollmentsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _enrollments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await MicroLearningService.instance.listCourseEnrollments(widget.courseId);
      if (mounted) setState(() { _enrollments = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 20, 12),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.glassWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder, width: 1.5)),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('শিক্ষার্থী তালিকা', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(widget.courseTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            Expanded(child: _body()),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.deepBlue));
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('আবার চেষ্টা করুন')),
        ]),
      ));
    }
    if (_enrollments.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.people_outline_rounded, color: AppColors.textMuted, size: 56),
        const SizedBox(height: 14),
        const Text('এখনো কেউ ভর্তি হননি', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
      ]));
    }
    return RefreshIndicator(
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _enrollments.length,
        itemBuilder: (_, i) => _tile(_enrollments[i], i),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> e, int index) {
    final name = e['studentName'] as String? ?? 'অজানা শিক্ষার্থী';
    final paidAmount = _asDouble(e['paidAmount']);
    final paidAt = DateTime.tryParse(e['paidAt'] as String? ?? '');
    final completed = e['completedAt'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.deepBlue,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              if (paidAt != null)
                Text('${paidAt.day}/${paidAt.month}/${paidAt.year} তারিখে ভর্তি', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('৳${paidAmount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w700)),
            if (completed) ...[
              const SizedBox(height: 2),
              const Text('সম্পন্ন', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ]),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: 30 * index)).fadeIn(duration: 240.ms).slideY(begin: 0.04);
  }
}
