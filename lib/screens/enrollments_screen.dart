import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../models/micro_learning_model.dart';
import '../theme/app_theme.dart';
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
                color: AppColors.bgMid,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: AppColors.blueGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(children: [
                        const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 56),
                        const SizedBox(height: 12),
                        const Text('সম্পন্নের সনদ', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                      label: const Text('বন্ধ করুন', style: TextStyle(color: AppColors.textMuted)),
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
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('আমার কোর্সসমূহ', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : _enrollments.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.school_outlined, color: AppColors.textMuted, size: 64),
                    const SizedBox(height: 12),
                    const Text('কোনো এনরোলমেন্ট নেই', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('কোর্সে ভর্তি হন', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ]),
                )
              : RefreshIndicator(
                  color: AppColors.deepBlue,
                  backgroundColor: AppColors.bgMid,
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
                          color: AppColors.bgMid,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.glassBorder),
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
                                      errorBuilder: (_, __, ___) => Container(height: 80, color: AppColors.glassWhite, child: const Icon(Icons.school_rounded, color: AppColors.textMuted, size: 32)),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(course['title'] as String? ?? 'কোর্স', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: progress.toDouble() / 100,
                                            backgroundColor: AppColors.glassWhite,
                                            color: isComplete ? const Color(0xFF10B981) : AppColors.deepBlue,
                                            minHeight: 6,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${progress.toInt()}%', style: TextStyle(color: isComplete ? const Color(0xFF10B981) : AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w600)),
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
                                            label: const Text('চালিয়ে যান', style: TextStyle(fontSize: 12)),
                                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.deepBlue, side: const BorderSide(color: AppColors.deepBlue), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                          ),
                                        )
                                      else
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _viewCertificate(enrollmentId, course['title'] as String? ?? ''),
                                            icon: const Icon(Icons.workspace_premium_rounded, size: 16, color: Colors.white),
                                            label: const Text('সনদ দেখুন', style: TextStyle(color: Colors.white, fontSize: 12)),
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
