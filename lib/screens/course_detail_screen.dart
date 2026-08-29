import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../core/utils/jwt_utils.dart';
import '../models/micro_learning_model.dart';
import '../services/micro_learning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'instructor_profile_screen.dart';
import 'lesson_player_screen.dart';
import 'payment_waiting_screen.dart';
import '../widgets/policy_agreement_checkbox.dart';

class CourseDetailScreen extends StatefulWidget {
  final String courseId;
  const CourseDetailScreen({super.key, required this.courseId});

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  CourseModel? _course;
  List<LessonModel> _lessons = [];
  bool _isLoading = true;
  bool _isEnrolling = false;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final course = await MicroLearningService.instance.getCourse(widget.courseId);
      if (mounted) {
        setState(() {
          _course = course;
          _lessons = List<LessonModel>.from(course.lessons)
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enroll() async {
    final token = await ApiClient.getAccessToken();
    final userId = token != null ? decodeJwtSub(token) : null;
    if (userId == null) {
      _showError(_isBn ? 'লগইন তথ্য পাওয়া যায়নি' : 'Login information not found'); return;
    }
    setState(() => _isEnrolling = true);
    try {
      final initiation = await MicroLearningService.instance.initiateEnrollment(courseId: widget.courseId);
      if (!mounted) return;

      if (!initiation.requiresPayment) {
        // Free course — already enrolled by the backend.
        final enrollment = initiation.enrollment;
        if (enrollment == null) throw Exception(_isBn ? 'ভর্তি সম্পন্ন করা যায়নি' : 'Could not complete enrollment');
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => LessonPlayerScreen(enrollment: enrollment, lessons: _lessons),
        ));
        return;
      }

      final gatewayPageUrl = initiation.gatewayPageUrl;
      if (gatewayPageUrl == null) {
        throw Exception(_isBn ? 'পেমেন্ট শুরু করা যায়নি' : 'Could not start payment');
      }

      if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
      if (!mounted) return;

      EnrollmentModel? confirmedEnrollment;
      final waitingNavigator = Navigator.of(context);
      await waitingNavigator.push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _course?.title ?? (_isBn ? 'কোর্স ভর্তি' : 'Course Enrollment'),
          titleEn: _course?.title ?? 'Course Enrollment',
          amount: initiation.amount ?? 0,
          checkStatus: () async {
            try {
              confirmedEnrollment = await MicroLearningService.instance.confirmEnrollment(courseId: widget.courseId);
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
          applyCoupon: (code) async {
            final i = await MicroLearningService.instance
                .initiateEnrollment(courseId: widget.courseId, couponCode: code);
            return {'gatewayPageUrl': i.gatewayPageUrl, 'amount': i.amount ?? 0};
          },
        ),
      ));

      if (!mounted || confirmedEnrollment == null) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LessonPlayerScreen(enrollment: confirmedEnrollment!, lessons: _lessons),
      ));
      return;
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
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
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.deepBlue)))
              else if (_course == null)
                Expanded(child: Center(child: Text(_isBn ? 'তথ্য পাওয়া যায়নি' : 'Information not found', style: const TextStyle(color: AppColors.textMuted))))
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(children: [
                      _buildCourseInfo(_course!),
                      const SizedBox(height: 16),
                      _buildLessonsList(),
                      const SizedBox(height: 24),
                      GlassButton(label: _isBn ? 'ভর্তি হন' : 'Enroll', isLoading: _isEnrolling, onPressed: _enroll),
                    ]),
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
          Text(_isBn ? 'কোর্সের বিবরণ' : 'Course Details', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  static const _categoryLabelsBn = {
    'tech': 'প্রযুক্তি', 'language': 'ভাষা', 'business': 'ব্যবসা',
    'arts': 'কলা ও নকশা', 'lifestyle': 'লাইফস্টাইল', 'other': 'অন্যান্য',
  };
  static const _categoryLabelsEn = {
    'tech': 'Tech', 'language': 'Language', 'business': 'Business',
    'arts': 'Arts & Design', 'lifestyle': 'Lifestyle', 'other': 'Other',
  };

  String _formatDuration(int mins) {
    if (_isBn) {
      if (mins < 60) return '$mins মিনিট';
      final h = mins ~/ 60;
      final m = mins % 60;
      return m == 0 ? '$h ঘণ্টা' : '$h ঘণ্টা $m মিনিট';
    }
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _buildCourseInfo(CourseModel c) {
    final hasDiscount = c.discountPrice != null && c.discountPrice! < c.price;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 140,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.deepBlue.withOpacity(0.5), AppColors.deepBlue.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: (c.coverImageUrl?.isNotEmpty ?? false)
                ? Image.network(
                    c.coverImageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.deepBlue, size: 64)),
                  )
                : const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.deepBlue, size: 64)),
          ),
          const SizedBox(height: 16),
          // Category + delivery-type badges — the data existed on the backend but this screen
          // never showed either, so a customer had no idea what kind of course this was
          // (recorded vs live) before paying.
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (c.category != null)
              _badge((_isBn ? _categoryLabelsBn[c.category] : _categoryLabelsEn[c.category]) ?? c.category!, AppColors.deepBlue),
            if (c.deliveryMode != null)
              _badge(
                  c.deliveryMode == 'live_cohort'
                      ? (_isBn ? 'লাইভ কোহোর্ট' : 'Live Cohort')
                      : (_isBn ? 'রেকর্ডেড' : 'Recorded'),
                  AppColors.fuchsia),
          ]),
          const SizedBox(height: 12),
          Text(c.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          if (c.providerName != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: c.providerId == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => InstructorProfileScreen(
                          providerId: c.providerId!,
                          providerName: c.providerName,
                        ),
                      )),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(c.providerName!,
                    style: TextStyle(
                        color: c.providerId == null
                            ? AppColors.textMuted
                            : AppColors.deepBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (c.providerId != null) ...[
                  const SizedBox(width: 3),
                  Text(_isBn ? '· সব কোর্স দেখুন' : '· see all courses',
                      style: const TextStyle(
                          color: AppColors.deepBlue, fontSize: 12)),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (c.rating != null) ...[
              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
              const SizedBox(width: 4),
              Text(c.rating!.toStringAsFixed(1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
            ],
            if (c.totalLessons != null) ...[
              Text(_isBn ? '${c.totalLessons} পাঠ' : '${c.totalLessons} lessons', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(width: 12),
            ],
            if (c.totalDurationMins != null && c.totalDurationMins! > 0) ...[
              Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 13),
              const SizedBox(width: 3),
              Text(_formatDuration(c.totalDurationMins!), style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ]),
          // Enrollment count as social proof — a customer deciding whether to pay had no signal
          // that anyone else had ever taken this course.
          if ((c.enrollmentCount ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.people_alt_rounded, color: AppColors.textMuted, size: 13),
              const SizedBox(width: 4),
              Text(_isBn ? '${c.enrollmentCount} জন শিক্ষার্থী ভর্তি হয়েছেন' : '${c.enrollmentCount} students enrolled', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: hasDiscount
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('৳ ${c.price.toStringAsFixed(0)}',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13, decoration: TextDecoration.lineThrough)),
                    const SizedBox(width: 8),
                    Text('৳ ${c.discountPrice!.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.w800)),
                  ])
                : Text('৳ ${c.price.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          if (c.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            Divider(color: AppColors.glassBorder, height: 1),
            const SizedBox(height: 12),
            Text(_isBn ? 'বিবরণ' : 'Description', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(c.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.6)),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _buildLessonsList() {
    if (_lessons.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isBn ? 'পাঠ তালিকা' : 'Lesson List', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...List.generate(_lessons.length, (i) {
            final lesson = _lessons[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: lesson.isFree ? const Color(0xFF22C55E).withOpacity(0.1) : AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: lesson.isFree ? const Color(0xFF22C55E).withOpacity(0.4) : AppColors.glassBorder),
                    ),
                    child: Center(child: Text('${i + 1}', style: TextStyle(color: lesson.isFree ? const Color(0xFF22C55E) : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(lesson.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (lesson.durationMinutes != null)
                        Text(_isBn ? '${lesson.durationMinutes} মিনিট' : '${lesson.durationMinutes} min', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ]),
                  ),
                  if (lesson.isFree)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(_isBn ? 'ফ্রি' : 'Free', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.w700)),
                    )
                  else
                    const Icon(Icons.lock_rounded, color: AppColors.textMuted, size: 14),
                ],
              ),
            );
          }),
        ],
      ),
    ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.05);
  }
}
