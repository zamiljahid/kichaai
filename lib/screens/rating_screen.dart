import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/dispatch_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

class RatingScreen extends StatefulWidget {
  final String jobId;
  const RatingScreen({super.key, required this.jobId});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _rating = 5;
  final _reviewController = TextEditingController();
  bool _isSubmitting = false;
  bool _isBn = true;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await DispatchService.instance.rateJob(
        widget.jobId,
        rating: _rating,
        review: _reviewController.text.trim().isNotEmpty ? _reviewController.text.trim() : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBn ? 'রিভিউ দেওয়ার জন্য ধন্যবাদ!' : 'Thanks for your review!', style: const TextStyle(color: AppColors.ivory)),
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.mapError(e).localized(_isBn), style: const TextStyle(color: AppColors.ivory)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 32),
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    gradient: AppColors.blueGradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.deepBlue.withOpacity(0.4), blurRadius: 24)],
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: AppColors.ivory, size: 48),
                ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
                const SizedBox(height: 24),
                Text(_isBn ? 'কাজ সম্পন্ন হয়েছে!' : 'Job Completed!', style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800))
                    .animate(delay: 200.ms).fadeIn().slideY(begin: 0.1),
                const SizedBox(height: 8),
                Text(_isBn ? 'Provider-কে রেটিং দিন' : 'Rate the Provider', style: const TextStyle(color: AppColors.textMuted, fontSize: 14))
                    .animate(delay: 300.ms).fadeIn(),
                const SizedBox(height: 32),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_isBn ? 'আপনার অভিজ্ঞতা কেমন ছিল?' : 'How was your experience?', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          final star = i + 1;
                          return GestureDetector(
                            onTap: () => setState(() => _rating = star),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(
                                star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: star <= _rating ? const Color(0xFFFFC107) : AppColors.glassBorder,
                                size: 40,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Center(child: Text(_ratingLabel(_rating), style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _reviewController,
                        maxLines: 3,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _isBn ? 'রিভিউ লিখুন (ঐচ্ছিক)...' : 'Write a review (optional)...',
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 40),
                            child: Icon(Icons.rate_review_rounded, color: AppColors.textMuted, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GlassButton(label: _isBn ? 'রিভিউ জমা দিন' : 'Submit Review', isLoading: _isSubmitting, onPressed: _submit),
                      const SizedBox(height: 10),
                      GlassButton(
                        label: _isBn ? 'এড়িয়ে যান' : 'Skip',
                        isOutlined: true,
                        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                      ),
                    ],
                  ),
                ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _ratingLabel(int r) {
    if (_isBn) {
      switch (r) {
        case 1: return 'খুব খারাপ';
        case 2: return 'খারাপ';
        case 3: return 'ঠিক আছে';
        case 4: return 'ভালো';
        case 5: return 'চমৎকার!';
        default: return '';
      }
    }
    switch (r) {
      case 1: return 'Very Bad';
      case 2: return 'Bad';
      case 3: return 'Okay';
      case 4: return 'Good';
      case 5: return 'Excellent!';
      default: return '';
    }
  }
}
