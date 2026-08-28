import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/micro_learning_model.dart';
import '../services/micro_learning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'course_detail_screen.dart';

/// Everything one instructor teaches, in one place.
///
/// A learner who liked a course previously had no way to see what else that person
/// offers — the name on a course card was plain text. GET /micro-learning/courses/
/// provider/:id has always returned exactly this list; nothing ever called it.
class InstructorProfileScreen extends StatefulWidget {
  final String providerId;
  final String? providerName;

  const InstructorProfileScreen({
    super.key,
    required this.providerId,
    this.providerName,
  });

  @override
  State<InstructorProfileScreen> createState() => _InstructorProfileScreenState();
}

class _InstructorProfileScreenState extends State<InstructorProfileScreen> {
  List<CourseModel> _courses = [];
  bool _loading = true;
  String? _error;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await MicroLearningService.instance.listMyCourses(widget.providerId);
      if (mounted) {
        setState(() {
          _courses = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiClient.mapError(e).localized(_isBn);
          _loading = false;
        });
      }
    }
  }

  /// The name the instructor is shown under. Falls back to whatever the course card
  /// carried, so the header is never blank while the list is still loading.
  String get _name =>
      _courses.isNotEmpty && (_courses.first.providerName?.isNotEmpty ?? false)
          ? _courses.first.providerName!
          : (widget.providerName ?? (_isBn ? 'শিক্ষক' : 'Instructor'));

  int get _totalLearners =>
      _courses.fold(0, (sum, c) => sum + (c.enrollmentCount ?? 0));

  double? get _avgRating {
    final rated = _courses.where((c) => c.rating != null).toList();
    if (rated.isEmpty) return null;
    return rated.fold(0.0, (s, c) => s + c.rating!) / rated.length;
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                    : _error != null
                        ? _errorView()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppColors.deepBlue,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                              children: [
                                _statsCard(),
                                const SizedBox(height: 16),
                                Text(
                                  _isBn
                                      ? 'এই শিক্ষকের কোর্স (${_courses.length})'
                                      : 'Courses by this instructor (${_courses.length})',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                if (_courses.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 40),
                                    child: Center(
                                      child: Text(
                                        _isBn
                                            ? 'এখনো কোনো প্রকাশিত কোর্স নেই'
                                            : 'No published courses yet',
                                        style: const TextStyle(
                                            color: AppColors.textMuted, fontSize: 13.5),
                                      ),
                                    ),
                                  )
                                else
                                  ..._courses.asMap().entries.map(
                                        (e) => _courseTile(e.value, e.key),
                                      ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Text(_isBn ? 'শিক্ষক' : 'Instructor',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsCard() {
    final rating = _avgRating;
    Widget stat(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, color: AppColors.deepBlue, size: 18),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          stat(Icons.menu_book_rounded, '${_courses.length}',
              _isBn ? 'কোর্স' : 'Courses'),
          stat(Icons.people_alt_rounded, '$_totalLearners',
              _isBn ? 'শিক্ষার্থী' : 'Learners'),
          stat(
            Icons.star_rounded,
            rating == null ? '—' : rating.toStringAsFixed(1),
            _isBn ? 'গড় রেটিং' : 'Avg rating',
          ),
        ],
      ),
    );
  }

  Widget _courseTile(CourseModel c, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CourseDetailScreen(courseId: c.id)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.blueGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_circle_fill_rounded,
                    color: AppColors.ivory, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (c.rating != null) ...[
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFFC107), size: 14),
                        const SizedBox(width: 3),
                        Text(c.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11.5)),
                        const SizedBox(width: 10),
                      ],
                      if (c.enrollmentCount != null)
                        Text(
                          _isBn
                              ? '${c.enrollmentCount} জন ভর্তি'
                              : '${c.enrollmentCount} enrolled',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11.5),
                        ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('৳ ${c.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: AppColors.deepBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ).animate(delay: Duration(milliseconds: 40 * index)).fadeIn(duration: 240.ms).slideY(begin: 0.04),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
          const SizedBox(height: 14),
          GlassButton(
              label: _isBn ? 'আবার চেষ্টা' : 'Retry',
              isOutlined: true,
              onPressed: _load),
        ]),
      ),
    );
  }
}
