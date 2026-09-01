import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/micro_learning_model.dart';
import '../services/micro_learning_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

class LessonPlayerScreen extends StatefulWidget {
  final EnrollmentModel enrollment;
  final List<LessonModel> lessons;

  const LessonPlayerScreen({
    super.key,
    required this.enrollment,
    required this.lessons,
  });

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _isMarking = false;
  Set<String> _completedIds = {};
  bool _isAllComplete = false;
  // 'loading' | 'ready' | 'processing' | 'failed' | 'none' — the video is never played
  // from lesson.videoUrl directly; that's a private-bucket key/URL, not a playable link.
  // A fresh, short-lived presigned URL is fetched per lesson, gated by enrollment.
  String _playUrlStatus = 'loading';
  bool _isBn = true;

  LessonModel get _currentLesson => widget.lessons[_currentIndex];

  @override
  void initState() {
    super.initState();
    _completedIds = Set.from(widget.enrollment.completedLessonIds);
    _initVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    _videoController?.dispose();
    _videoController = null;
    _isInitialized = false;
    setState(() => _playUrlStatus = 'loading');

    try {
      final res = await MicroLearningService.instance.getLessonPlayUrl(_currentLesson.id);
      if (!mounted) return;
      final status = res['status'] as String? ?? 'none';
      final url = res['url'] as String?;
      setState(() => _playUrlStatus = status);

      if (status == 'ready' && url != null && url.isNotEmpty) {
        final controller = VideoPlayerController.networkUrl(Uri.parse(url));
        _videoController = controller;
        controller.initialize().then((_) {
          if (mounted) setState(() => _isInitialized = true);
        }).catchError((_) {
          if (mounted) setState(() => _isInitialized = false);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _playUrlStatus = 'failed');
    }
  }

  void _selectLesson(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _isInitialized = false;
    });
    _initVideo();
  }

  Future<void> _markComplete() async {
    final colors = Theme.of(context).colorScheme;
    setState(() => _isMarking = true);
    try {
      await MicroLearningService.instance.markLessonComplete(
        enrollmentId: widget.enrollment.id,
        lessonId: _currentLesson.id,
      );
      if (!mounted) return;
      setState(() {
        _completedIds.add(_currentLesson.id);
        _isAllComplete = _completedIds.length >= widget.lessons.length;
        _isMarking = false;
      });
      if (_isAllComplete) {
        _showCertificateBanner();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.mapError(e).localized(_isBn), style: TextStyle(color: colors.onPrimary)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
        setState(() => _isMarking = false);
      }
    }
  }

  void _showCertificateBanner() {
    final colors = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFC107), size: 72),
          const SizedBox(height: 16),
          Text(_isBn ? 'অভিনন্দন!' : 'Congratulations!', textAlign: TextAlign.center, style: TextStyle(color: colors.onSurface, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_isBn ? 'আপনি সফলভাবে কোর্সটি সম্পন্ন করেছেন!' : 'You have successfully completed the course!', textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 24),
          GlassButton(label: _isBn ? 'হোমে ফিরুন' : 'Back to Home', onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    final isCompleted = _completedIds.contains(_currentLesson.id);

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Row(
                  children: [
                    _buildLessonList(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 16, 24),
                        child: Column(children: [
                          _buildVideoPlayer(),
                          const SizedBox(height: 16),
                          GlassCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(_currentLesson.title, style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
                                if (_currentLesson.description?.isNotEmpty ?? false) ...[
                                  const SizedBox(height: 8),
                                  Text(_currentLesson.description!, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13, height: 1.6)),
                                ],
                                const SizedBox(height: 16),
                                if (isCompleted)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4)),
                                    ),
                                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 18),
                                      const SizedBox(width: 8),
                                      Text(_isBn ? 'সম্পন্ন হয়েছে' : 'Completed', style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w600)),
                                    ]),
                                  )
                                else
                                  GlassButton(
                                    label: _isBn ? 'সম্পন্ন হিসেবে চিহ্নিত করুন' : 'Mark as Complete',
                                    isLoading: _isMarking,
                                    onPressed: _markComplete,
                                  ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.outlineVariant, width: 1.5)),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_currentLesson.title, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(_isBn ? '${_completedIds.length}/${widget.lessons.length} সম্পন্ন' : '${_completedIds.length}/${widget.lessons.length} completed', style: TextStyle(color: colors.outline, fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final colors = Theme.of(context).colorScheme;
    if (_playUrlStatus == 'none') {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.videocam_off_rounded, color: colors.outline, size: 48),
          const SizedBox(height: 8),
          Text(_isBn ? 'ভিডিও পাওয়া যায়নি' : 'Video not found', style: TextStyle(color: colors.outline, fontSize: 13)),
        ]),
      );
    }

    if (_playUrlStatus == 'processing') {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.hourglass_top_rounded, color: colors.outline, size: 40),
          const SizedBox(height: 8),
          Text(_isBn ? 'ভিডিও প্রস্তুত হচ্ছে — একটু পর আবার চেষ্টা করুন' : 'Video is being prepared — try again shortly', textAlign: TextAlign.center, style: TextStyle(color: colors.outline, fontSize: 13)),
          const SizedBox(height: 10),
          GestureDetector(onTap: _initVideo, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600))),
        ]),
      );
    }

    if (_playUrlStatus == 'failed') {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 40),
          const SizedBox(height: 8),
          Text(_isBn ? 'ভিডিও লোড করা যায়নি' : 'Could not load video', style: TextStyle(color: colors.outline, fontSize: 13)),
          const SizedBox(height: 10),
          GestureDetector(onTap: _initVideo, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600))),
        ]),
      );
    }

    if (_playUrlStatus == 'loading' || !_isInitialized || _videoController == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)),
        child: Center(child: CircularProgressIndicator(color: colors.primary)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_videoController!),
            VideoProgressIndicator(_videoController!, allowScrubbing: true, colors: VideoProgressColors(playedColor: colors.primary)),
            Positioned(
              bottom: 24,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _videoController!.value.isPlaying
                        ? _videoController!.pause()
                        : _videoController!.play();
                  });
                },
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: Icon(
                    _videoController!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white, size: 30,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonList() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      color: Colors.transparent,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        itemCount: widget.lessons.length,
        itemBuilder: (_, i) {
          final lesson = widget.lessons[i];
          final isDone = _completedIds.contains(lesson.id);
          final isCurrent = i == _currentIndex;
          return GestureDetector(
            onTap: () => _selectLesson(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: isCurrent ? AppGradients.primary(colors) : null,
                color: isCurrent ? null : (isDone ? const Color(0xFF22C55E).withOpacity(0.1) : colors.surface),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrent ? colors.primary : (isDone ? const Color(0xFF22C55E) : colors.outlineVariant),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isDone && !isCurrent
                    ? const Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 18)
                    : Text('${i + 1}', style: TextStyle(color: isCurrent ? colors.onPrimary : colors.outline, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          );
        },
      ),
    );
  }
}
