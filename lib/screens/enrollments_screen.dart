import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/micro_learning_model.dart';
import '../theme/app_gradients.dart';
import 'lesson_player_screen.dart';

class EnrollmentsScreen extends StatefulWidget {
  const EnrollmentsScreen({super.key});

  @override
  State<EnrollmentsScreen> createState() => _EnrollmentsScreenState();
}

class _EnrollmentsScreenState extends State<EnrollmentsScreen> {
  final _client = ApiClient.instance.dio;
  List<dynamic> _enrollments = [];
  bool _isLoading = true;
  String? _userId;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await _load();
  }

  Future<void> _load() async {
    if (_userId == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await _client.get('/micro-learning/enrollments', queryParameters: {'userId': _userId});
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      if (mounted) setState(() { _enrollments = list as List; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _viewCertificate(String enrollmentId, String courseName) {
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FutureBuilder(
        future: _client.get('/micro-learning/certificates/$enrollmentId'),
        builder: (ctx, snap) {
          final cert = snap.data?.data as Map<String, dynamic>?;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: colors.surface,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: AppGradients.primary(colors),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(children: [
                        const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 56),
                        const SizedBox(height: 12),
                        Text(_isBn ? 'সম্পন্নের সনদ' : 'Certificate of Completion', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(courseName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        if (cert != null) ...[
                          Text(cert['completionDate']?.toString().substring(0, 10) ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close_rounded, color: colors.outline),
                      label: Text(_isBn ? 'বন্ধ করুন' : 'Close', style: TextStyle(color: colors.outline)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'আমার কোর্সসমূহ' : 'My Courses', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _enrollments.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.school_outlined, color: colors.outline, size: 64),
                    const SizedBox(height: 12),
                    Text(_isBn ? 'কোনো এনরোলমেন্ট নেই' : 'No enrollments', style: TextStyle(color: colors.outline, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(_isBn ? 'কোর্সে ভর্তি হন' : 'Enroll in a course', style: TextStyle(color: colors.outline, fontSize: 13)),
                  ]),
                )
              : RefreshIndicator(
                  color: colors.primary,
                  backgroundColor: colors.surface,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _enrollments.length,
                    itemBuilder: (ctx, i) {
                      final e = _enrollments[i] as Map<String, dynamic>;
                      final course = e['course'] as Map<String, dynamic>? ?? {};
                      final progress = (e['progressPercent'] ?? e['progress'] ?? 0.0) as num;
                      final isComplete = progress >= 100;
                      final enrollmentId = e['id'] as String? ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (course['coverImageUrl'] != null)
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    child: Image.network(
                                      course['coverImageUrl'] as String,
                                      height: 120,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(height: 80, color: colors.surface, child: Icon(Icons.school_rounded, color: colors.outline, size: 32)),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(course['title'] as String? ?? (_isBn ? 'কোর্স' : 'Course'), style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: progress.toDouble() / 100,
                                            backgroundColor: colors.surface,
                                            color: isComplete ? const Color(0xFF10B981) : colors.primary,
                                            minHeight: 6,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${progress.toInt()}%', style: TextStyle(color: isComplete ? const Color(0xFF10B981) : colors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ]),
                                    const SizedBox(height: 12),
                                    Row(children: [
                                      if (!isComplete)
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              final enrollment = EnrollmentModel.fromJson(e);
                                              final lessons = (course['lessons'] as List<dynamic>? ?? [])
                                                  .map((l) => LessonModel.fromJson(l as Map<String, dynamic>))
                                                  .toList();
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => LessonPlayerScreen(enrollment: enrollment, lessons: lessons))).then((_) => _load());
                                            },
                                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                            label: Text(_isBn ? 'চালিয়ে যান' : 'Continue', style: const TextStyle(fontSize: 12)),
                                            style: OutlinedButton.styleFrom(foregroundColor: colors.primary, side: BorderSide(color: colors.primary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                          ),
                                        )
                                      else
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _viewCertificate(enrollmentId, course['title'] as String? ?? ''),
                                            icon: const Icon(Icons.workspace_premium_rounded, size: 16, color: Colors.white),
                                            label: Text(_isBn ? 'সনদ দেখুন' : 'View Certificate', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                          ),
                                        ),
                                    ]),
                                  ]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 60)).slideY(begin: 0.1, end: 0);
                    },
                  ),
                ),
    );
  }
}
