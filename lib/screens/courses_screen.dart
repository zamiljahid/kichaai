import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
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

// Categories come from GET /micro-learning/categories now. Keeping a copy here is what
// broke the filter before: the app said tech/arts/lifestyle while the data said
// Technology/Business/Design/Language, so every chip returned nothing.

class _CoursesScreenState extends State<CoursesScreen> {
  List<CourseModel> _courses = [];
  bool _isLoading = true;
  String? _error;
  String _category = 'all';
  bool _isBn = true;

  List<Map<String, String>> _categories = [];
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final list = await MicroLearningService.instance.listCourses(
        category: _category == 'all' ? null : _category,
        search: _searchCtrl.text.trim(),
      );
      if (mounted) setState(() { _courses = list; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.mapError(e).localized(_isBn); _isLoading = false; });
    }
  }

  /// Bengali label for a stored category code, falling back to the code itself.
  String _categoryLabel(String code) {
    for (final c in _categories) {
      if (c['code'] == code) return _isBn ? c['bn']! : c['en']!;
    }
    return code;
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await MicroLearningService.instance.listCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {
      // The chips just stay hidden; the course list below still loads.
    }
  }

  /// Search fires a little after typing stops, so a five-letter word is one request.
  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: _isBn ? 'কোর্স খুঁজুন…' : 'Search courses…',
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _load();
                  },
                ),
          filled: true,
          fillColor: AppColors.glassWhite,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.glassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.glassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.deepBlue, width: 1.4),
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
              _buildHeader(context),
              _buildSearch(),
              if (_categories.isNotEmpty) _buildCategoryFilter(),
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
        itemCount: _categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          // index 0 is the "all" chip; the rest come straight from the backend list.
          final code = i == 0 ? 'all' : _categories[i - 1]['code']!;
          final label = i == 0
              ? (_isBn ? 'সব' : 'All')
              : (_isBn ? _categories[i - 1]['bn']! : _categories[i - 1]['en']!);
          final sel = _category == code;
          return GestureDetector(
            onTap: () {
              if (sel) return;
              setState(() => _category = code);
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
              child: Text(label, style: TextStyle(color: sel ? AppColors.ivory : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
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
            child: Text(_isBn ? 'মাইক্রো লার্নিং' : 'Micro Learning', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1);
  }

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
                      if (c.category != null) _pill(_categoryLabel(c.category!), AppColors.deepBlue),
                      if (c.deliveryMode != null)
                        _pill(
                            c.deliveryMode == 'live_cohort'
                                ? (_isBn ? 'লাইভ কোহোর্ট' : 'Live Cohort')
                                : (_isBn ? 'রেকর্ডেড' : 'Recorded'),
                            AppColors.fuchsia),
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
                      Text(_isBn ? '${c.totalLessons} পাঠ' : '${c.totalLessons} lessons', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
                      Text(_isBn ? '${c.enrollmentCount} জন ভর্তি' : '${c.enrollmentCount} enrolled', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
          _error ?? (_isBn ? 'কোর্স লোড হয়নি' : 'Could not load courses'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        GestureDetector(onTap: _load, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again', style: const TextStyle(color: AppColors.deepBlue))),
      ]),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.school_rounded, color: AppColors.textMuted, size: 56),
      const SizedBox(height: 12),
      Text(_isBn ? 'কোনো কোর্স পাওয়া যায়নি' : 'No courses found', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
    ]),
  );
}
