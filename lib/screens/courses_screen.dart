import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/micro_learning_model.dart';
import '../services/micro_learning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import 'course_detail_screen.dart';

class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

const _categories = [
  ['all', 'সব'],
  ['tech', 'প্রযুক্তি'],
  ['language', 'ভাষা'],
  ['business', 'ব্যবসা'],
  ['arts', 'কলা ও নকশা'],
  ['lifestyle', 'লাইফস্টাইল'],
  ['other', 'অন্যান্য'],
];

const _categoryLabelsBn = {
  'tech': 'প্রযুক্তি', 'language': 'ভাষা', 'business': 'ব্যবসা',
  'arts': 'কলা ও নকশা', 'lifestyle': 'লাইফস্টাইল', 'other': 'অন্যান্য',
};

class _CoursesScreenState extends State<CoursesScreen> {
  List<CourseModel> _courses = [];
  bool _isLoading = true;
  String? _error;
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final list = await MicroLearningService.instance.listCourses(
        category: _category == 'all' ? null : _category,
      );
      if (mounted) setState(() { _courses = list; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildCategoryFilter(),
              const SizedBox(height: 4),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                    : _error != null
                        ? _buildError()
                        : _courses.isEmpty
                            ? _buildEmpty()
                            : RefreshIndicator(
                                onRefresh: _load,
                                color: AppColors.deepBlue,
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: _courses.length,
                                  itemBuilder: (_, i) => _buildCourseCard(_courses[i], i),
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final sel = _category == cat[0];
          return GestureDetector(
            onTap: () {
              if (sel) return;
              setState(() => _category = cat[0]);
              _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: sel ? AppColors.blueGradient : null,
                color: sel ? null : AppColors.glassWhite,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: sel ? Colors.transparent : AppColors.glassBorder),
              ),
              child: Text(cat[1], style: TextStyle(color: sel ? AppColors.ivory : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          );
        },
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
          // Was an unconstrained Column in a Row with no Expanded/Flexible — on a narrow
          // viewport the two lines of text had nothing stopping them from overflowing the
          // available width (RenderFlex overflow, separate from the price-parsing crash below).
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('মাইক্রো লার্নিং', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              Text('Micro Learning Courses', style: TextStyle(color: AppColors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

  String _formatDuration(int mins) {
    if (mins < 60) return '$mins মিনিট';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h ঘণ্টা' : '$h ঘণ্টা $m মিনিট';
  }

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );

  Widget _buildCourseCard(CourseModel c, int index) {
    final hasDiscount = c.discountPrice != null && c.discountPrice! < c.price;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CourseDetailScreen(courseId: c.id),
        )),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Thumbnail strip — real cover image when providers set one, otherwise a
            // consistent placeholder instead of the old bare 72x72 icon box.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.deepBlue.withOpacity(0.45), AppColors.deepBlue.withOpacity(0.12)]),
                ),
                child: Stack(children: [
                  if (c.coverImageUrl?.isNotEmpty ?? false)
                    Positioned.fill(
                      child: Image.network(
                        c.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.deepBlue, size: 44)),
                      ),
                    )
                  else
                    const Center(child: Icon(Icons.play_circle_fill_rounded, color: AppColors.deepBlue, size: 44)),
                  Positioned(
                    left: 10, top: 10,
                    child: Wrap(spacing: 6, children: [
                      if (c.category != null) _pill(_categoryLabelsBn[c.category] ?? c.category!, AppColors.deepBlue),
                      if (c.deliveryMode != null)
                        _pill(c.deliveryMode == 'live_cohort' ? 'লাইভ কোহোর্ট' : 'রেকর্ডেড', AppColors.fuchsia),
                    ]),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (c.providerName != null) ...[
                  const SizedBox(height: 3),
                  Text(c.providerName!, style: TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  if (c.rating != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 14),
                      const SizedBox(width: 2),
                      Text(c.rating!.toStringAsFixed(1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  if (c.totalLessons != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.menu_book_rounded, color: AppColors.textMuted, size: 13),
                      const SizedBox(width: 3),
                      Text('${c.totalLessons} পাঠ', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ]),
                  if (c.totalDurationMins != null && c.totalDurationMins! > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 13),
                      const SizedBox(width: 3),
                      Text(_formatDuration(c.totalDurationMins!), style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ]),
                  if ((c.enrollmentCount ?? 0) > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.people_alt_rounded, color: AppColors.textMuted, size: 13),
                      const SizedBox(width: 3),
                      Text('${c.enrollmentCount} জন ভর্তি', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ]),
                ]),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: hasDiscount
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('৳ ${c.price.toStringAsFixed(0)}',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11, decoration: TextDecoration.lineThrough)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(8)),
                            child: Text('৳ ${c.discountPrice!.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.ivory, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ])
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(gradient: AppColors.blueGradient, borderRadius: BorderRadius.circular(8)),
                          child: Text('৳ ${c.price.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.ivory, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1);
  }

  // Was a hardcoded "কোর্স লোড হয়নি" regardless of cause — _error (AppException.messageBn)
  // already carries the real, specific reason (session expired / no internet / server error /
  // etc.) from ApiClient.mapError, it just was never shown. Showing it now so a failure is
  // actually diagnosable from the screen itself, not just a generic "didn't load".
  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 48),
        const SizedBox(height: 12),
        Text(
          _error ?? 'কোর্স লোড হয়নি',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        GestureDetector(onTap: _load, child: const Text('আবার চেষ্টা করুন', style: TextStyle(color: AppColors.deepBlue))),
      ]),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.school_rounded, color: AppColors.textMuted, size: 56),
      const SizedBox(height: 12),
      Text('কোনো কোর্স পাওয়া যায়নি', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
    ]),
  );
}
