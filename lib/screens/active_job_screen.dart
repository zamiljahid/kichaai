import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../models/dispatch_model.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../services/messaging_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'chat_screen.dart';

class ActiveJobScreen extends StatefulWidget {
  final JobModel job;
  final VoidCallback? onJobCompleted;

  const ActiveJobScreen({super.key, required this.job, this.onJobCompleted});

  @override
  State<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends State<ActiveJobScreen> {
  late JobModel _job;
  bool _isLoading = false;
  bool _isOpeningChat = false;
  final _otpController = TextEditingController();
  Timer? _trackTimer;

  // Statuses during which the customer's live map expects our pings.
  static const _trackableStatuses = {'accepted', 'arriving', 'in_progress'};

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    _syncLocationTracking();
  }

  @override
  void dispose() {
    _trackTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  /// Start/stop the location ping loop based on the job's current status.
  /// This is the data source for the customer's tracking map — without it the
  /// map screen renders but never moves.
  void _syncLocationTracking() {
    final shouldTrack = _trackableStatuses.contains(_job.status);
    if (shouldTrack && _trackTimer == null) {
      _postLocation();
      _trackTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _postLocation();
        _silentRefreshUntilConfirmed();
      });
    } else if (!shouldTrack && _trackTimer != null) {
      _trackTimer!.cancel();
      _trackTimer = null;
    }
  }

  Future<void> _postLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await DispatchService.instance.trackLocation(_job.id, pos.latitude, pos.longitude);
    } catch (_) {
      // No permission / GPS off — skip this ping, try again next tick.
    }
  }

  // Piggybacks on the same 20s tracking tick — no separate timer needed. Only fires while the
  // customer hasn't confirmed yet, so the customer's phone number appears here on its own the
  // moment they do, without the provider having to leave and come back to this screen.
  Future<void> _silentRefreshUntilConfirmed() async {
    if (_job.providerConfirmed) return;
    try {
      final updated = await DispatchService.instance.getJob(_job.id);
      if (mounted) setState(() => _job = updated);
    } catch (_) {}
  }

  Future<void> _openJobChat() async {
    setState(() => _isOpeningChat = true);
    try {
      final user = await AuthService.instance.getCurrentUser();
      final threads = await MessagingService.instance.listThreads(user.id);
      ThreadModel? thread;
      for (final t in threads) {
        if (t.dispatchJobId == _job.id) { thread = t; break; }
      }
      if (!mounted) return;
      if (thread == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('চ্যাট এখনো তৈরি হয়নি — একটু পরে আবার চেষ্টা করুন', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      final otherName = thread.otherParticipantName(user.id);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(threadId: thread!.id, currentUserId: user.id, participantName: otherName),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('চ্যাট খোলা যায়নি', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _isLoading = true);
    try {
      final updated = await DispatchService.instance.updateJobStatus(_job.id, status);
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (e) {
      _showError('স্ট্যাটাস আপডেট করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestAndConfirmStart() async {
    setState(() => _isLoading = true);
    try {
      final devOtp = await DispatchService.instance.requestStart(_job.id);
      setState(() => _isLoading = false);
      final otp = await _showOtpDialog('কাজ শুরুর OTP', devOtp: devOtp);
      if (otp == null || otp.isEmpty) return;
      setState(() => _isLoading = true);
      await DispatchService.instance.confirmStart(_job.id, otp);
      final updated = await DispatchService.instance.getJob(_job.id);
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (e) {
      _showError('OTP যাচাই ব্যর্থ হয়েছে');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestAndConfirmCompletion() async {
    setState(() => _isLoading = true);
    try {
      final devOtp = await DispatchService.instance.requestCompletion(_job.id);
      setState(() => _isLoading = false);
      final otp = await _showOtpDialog('কাজ সম্পন্নের OTP', devOtp: devOtp);
      if (otp == null || otp.isEmpty) return;
      setState(() => _isLoading = true);
      await DispatchService.instance.confirmCompletion(_job.id, otp);
      final updated = await DispatchService.instance.getJob(_job.id);
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (e) {
      _showError('OTP যাচাই ব্যর্থ হয়েছে');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshJob() async {
    setState(() => _isLoading = true);
    try {
      final updated = await DispatchService.instance.getJob(_job.id);
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (_) {
      // keep showing the last known state
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitQuote() async {
    final amountCtrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('কাজ দেখে কোট দিন', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('আপনার প্রস্তাবিত মূল্য (৳)। গ্রাহক অনুমোদন করলেই কাজ শুরু হবে।',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                prefixText: '৳ ',
                prefixStyle: const TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.w700),
                hintText: '2500',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.glassBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.deepBlue)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('বাতিল', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              final v = double.tryParse(amountCtrl.text.trim());
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('কোট পাঠান', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (amount == null) return;
    setState(() => _isLoading = true);
    try {
      final updated = await DispatchService.instance.submitQuote(_job.id, quotedAmount: amount);
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (e) {
      _showError('কোট পাঠাতে সমস্যা হয়েছে');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _showOtpDialog(String title, {String? devOtp}) async {
    _otpController.text = devOtp ?? '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (devOtp != null) ...[
              Text('টেস্ট মোড — OTP নিজে থেকেই ভরা হয়েছে: $devOtp',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, letterSpacing: 4),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '••••••',
                hintStyle: TextStyle(color: AppColors.textMuted),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.deepBlue),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('বাতিল', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _otpController.text.trim()),
            child: const Text('নিশ্চিত', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildStatusCard(),
                      const SizedBox(height: 14),
                      _buildCustomerCard(),
                      const SizedBox(height: 14),
                      _buildJobCard(),
                      if (_trackableStatuses.contains(_job.status) && _job.serviceKind != 'lawyer') ...[
                        const SizedBox(height: 14),
                        _buildPhotoProofCard(),
                      ],
                      const SizedBox(height: 28),
                      _buildActionButton(),
                      if (_canProviderCancel) ...[
                        const SizedBox(height: 18),
                        _buildCancelLink(),
                      ],
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                border: Border.all(color: AppColors.glassBorder, width: 1.5),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          const Text('সক্রিয় কাজ', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final Color statusColor;
    switch (_job.status) {
      case 'in_progress':
        statusColor = AppColors.deepBlue;
      case 'arriving':
        statusColor = const Color(0xFFF59E0B);
      case 'completed':
        statusColor = const Color(0xFF10B981);
      default:
        statusColor = AppColors.textMuted;
    }
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            'অবস্থা: ${_job.statusBn()}',
            style: TextStyle(color: statusColor, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Photo proof (কাজের ছবি) ─────────────────────────────────────
  // The backend has ALWAYS set commission to 15% with a photo and 20% without —
  // but the app never had an upload UI, so every technician silently paid 20%.
  // Also: request-completion refuses outright if no photo exists.

  bool _uploadingStartPhoto = false;
  bool _uploadingEndPhoto = false;
  final _photoPicker = ImagePicker();

  Future<void> _takeJobPhoto(String photoType) async {
    XFile? image;
    try {
      image = await _photoPicker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1280);
    } catch (_) {
      // Camera unavailable (e.g. desktop browser) — fall back to gallery.
      image = await _photoPicker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1280);
    }
    if (image == null) return;

    setState(() {
      if (photoType == 'start') { _uploadingStartPhoto = true; } else { _uploadingEndPhoto = true; }
    });
    try {
      // XFile.readAsBytes works on every platform (File(path) doesn't exist on web).
      final bytes = await image.readAsBytes();
      final b64 = base64Encode(bytes);
      final fileUrl = await OnboardingService.instance.uploadFile(
        fileBase64: b64,
        fileName: 'job_${_job.id}_$photoType.jpg',
        mimeType: 'image/jpeg',
      );
      await DispatchService.instance.uploadJobPhoto(_job.id, photoType: photoType, photoUrl: fileUrl);
      final updated = await DispatchService.instance.getJob(_job.id);
      if (mounted) setState(() => _job = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ছবি আপলোড হয়েছে — কমিশন এখন ১৫%', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF10B981), behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ছবি আপলোড ব্যর্থ হয়েছে — আবার চেষ্টা করুন', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) {
        setState(() { _uploadingStartPhoto = false; _uploadingEndPhoto = false; });
      }
    }
  }

  Widget _buildPhotoProofCard() {
    final hasAny = _job.startPhotoUrl != null || _job.endPhotoUrl != null;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera_rounded, color: AppColors.deepBlue, size: 20),
              const SizedBox(width: 8),
              const Text('কাজের ছবি', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (hasAny ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasAny ? 'কমিশন ১৫%' : 'ছবি ছাড়া কমিশন ২০%',
                  style: TextStyle(
                    color: hasAny ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontSize: 10.5, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('কাজ শুরু ও শেষের ছবি তুলুন — ছবি থাকলে কমিশন ২০% এর বদলে ১৫%।',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _photoSlot('শুরুর ছবি', 'start', _job.startPhotoUrl, _uploadingStartPhoto)),
              const SizedBox(width: 12),
              Expanded(child: _photoSlot('শেষের ছবি', 'end', _job.endPhotoUrl, _uploadingEndPhoto)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoSlot(String label, String photoType, String? url, bool uploading) {
    return GestureDetector(
      onTap: uploading ? null : () => _takeJobPhoto(photoType),
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: url != null ? const Color(0xFF10B981) : AppColors.glassBorder,
            width: url != null ? 1.6 : 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: url != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image_outlined, color: AppColors.textMuted))),
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (uploading)
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                  else
                    const Icon(Icons.add_a_photo_rounded, color: AppColors.deepBlue, size: 26),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('গ্রাহকের তথ্য', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.person_rounded, color: AppColors.deepBlue, size: 18),
            const SizedBox(width: 8),
            Text(
              _job.customerNameSnapshot ?? 'অজানা',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ]),
          if (_job.customerPhoneSnapshot != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.phone_rounded, color: AppColors.deepBlue, size: 18),
              const SizedBox(width: 8),
              Text(_job.customerPhoneSnapshot!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            ]),
          ] else if (_job.serviceKind != 'lawyer') ...[
            const SizedBox(height: 8),
            Text(
              (_job.startConfirmed || _job.providerConfirmed)
                  ? 'গ্রাহক কোনো ফোন নম্বর দেননি — চ্যাটে যোগাযোগ করুন'
                  : 'গ্রাহক নিশ্চিত না করা পর্যন্ত নম্বর দেখা যাবে না — ততক্ষণ চ্যাটে কথা বলুন',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
          if (_job.serviceKind != 'lawyer') ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _isOpeningChat ? null : _openJobChat,
              child: Row(children: [
                _isOpeningChat
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue))
                    : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.deepBlue, size: 16),
                const SizedBox(width: 8),
                const Text('গ্রাহকের সাথে চ্যাট করুন', style: TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          if (_job.pickupAddressSnapshot != null) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.location_on_rounded, color: AppColors.deepBlue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _job.pickupAddressSnapshot!,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildJobCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('কাজের বিবরণ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Text(_job.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          if (_job.description != null && _job.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_job.description!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          if (_job.estimatedAmount != null) ...[
            const SizedBox(height: 8),
            Text(
              'আনুমানিক মূল্য: ৳ ${_job.estimatedAmount!.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.deepBlue, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitOpinion() async {
    final summaryCtrl = TextEditingController();
    final adviceCtrl = TextEditingController();
    final stepsCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('আইনি মতামত জমা দিন', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _opinionField(summaryCtrl, 'সারসংক্ষেপ (আবশ্যক)', maxLines: 3),
              const SizedBox(height: 12),
              _opinionField(adviceCtrl, 'পরামর্শ (ঐচ্ছিক)', maxLines: 2),
              const SizedBox(height: 12),
              _opinionField(stepsCtrl, 'পরবর্তী পদক্ষেপ (ঐচ্ছিক)', maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('বাতিল', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              if (summaryCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('জমা দিন', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (submitted != true) return;
    setState(() => _isLoading = true);
    try {
      final updated = await DispatchService.instance.submitOpinion(
        _job.id,
        opinionSummary: summaryCtrl.text.trim(),
        opinionAdvice: adviceCtrl.text.trim().isNotEmpty ? adviceCtrl.text.trim() : null,
        opinionNextSteps: stepsCtrl.text.trim().isNotEmpty ? stepsCtrl.text.trim() : null,
      );
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (e) {
      _showError('মতামত জমা দিতে সমস্যা হয়েছে');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _opinionField(TextEditingController c, String hint, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.glassBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.deepBlue)),
      ),
    );
  }

  // Provider can cancel once they've accepted, until the job is done.
  bool get _canProviderCancel =>
      _job.status == 'accepted' ||
      _job.status == 'arriving' ||
      _job.status == 'in_progress';

  // A muted "cancel job" link + a one-line hint of what cancelling costs right now.
  Widget _buildCancelLink() {
    final kind = _job.cancelPenaltyKind;
    late final String hint;
    late final Color hintColor;
    switch (kind) {
      case 'free':
        hint = '১৫ মিনিটের মধ্যে বাতিল ফ্রি (${_job.cancelGraceMinutesLeft} মিনিট বাকি)';
        hintColor = AppColors.textMuted;
        break;
      case 'fee':
        hint = 'গ্রাহক কাজ শুরু নিশ্চিত করেছেন — বাতিল করলে রেড কার্ড + কমিশন দেনা';
        hintColor = const Color(0xFFEF4444);
        break;
      default: // card
        hint = 'সময় শেষ — বাতিল করলে ১টি রেড কার্ড';
        hintColor = const Color(0xFFF59E0B);
    }
    return Column(
      children: [
        TextButton.icon(
          onPressed: _cancelJob,
          icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 18),
          label: const Text('কাজটি বাতিল করুন',
              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
        ),
        Text(hint, textAlign: TextAlign.center,
            style: TextStyle(color: hintColor, fontSize: 12)),
      ],
    );
  }

  Future<void> _cancelJob() async {
    final kind = _job.cancelPenaltyKind;
    late final String body;
    switch (kind) {
      case 'free':
        body = 'এখন বাতিল করলে কোনো জরিমানা নেই। নিশ্চিত?';
        break;
      case 'fee':
        body = 'গ্রাহক কাজ শুরু নিশ্চিত করেছেন। বাতিল করলে ১টি রেড কার্ড পাবেন এবং '
            'কমিশন দেনা হিসেবে বসবে — দেনা না মেটানো পর্যন্ত নতুন কাজ পাবেন না। নিশ্চিত?';
        break;
      default: // card
        body = 'ফ্রি সময় (১৫ মিনিট) শেষ। বাতিল করলে ১টি রেড কার্ড পাবেন। '
            '৩টি কার্ড হলে ৭ দিনের জন্য কাজ বন্ধ থাকবে। নিশ্চিত?';
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('কাজ বাতিল', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('না', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('হ্যাঁ, বাতিল করুন', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      final result = await DispatchService.instance.cancelJob(_job.id);
      if (!mounted) return;
      await _showCancelResult(result);
      widget.onJobCompleted?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('বাতিল করতে সমস্যা হয়েছে');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCancelResult(CancelResult r) {
    String msg;
    if (!r.hadPenalty) {
      msg = 'কাজ বাতিল হয়েছে। কোনো জরিমানা হয়নি।';
    } else {
      final parts = <String>['১টি রেড কার্ড যোগ হয়েছে'];
      if (r.feeCharged && r.feeAmount != null) {
        parts.add('৳${r.feeAmount!.toStringAsFixed(0)} কমিশন দেনা বসেছে (দেনা না মেটালে নতুন কাজ বন্ধ)');
      }
      if (r.suspended) {
        final until = r.bannedUntil != null ? _fmtDate(r.bannedUntil!) : '৭ দিন';
        parts.add('৩টি কার্ড হয়ে যাওয়ায় $until পর্যন্ত কাজ বন্ধ');
      }
      msg = '${parts.join('।\n')}।';
    }
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(r.hadPenalty ? 'বাতিল হয়েছে (জরিমানা প্রযোজ্য)' : 'বাতিল হয়েছে',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ঠিক আছে', style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildActionButton() {
    if (_isLoading) {
      return const CircularProgressIndicator(color: AppColors.deepBlue);
    }
    // Lawyer consultation — provider completes it by submitting a written opinion.
    if (_job.serviceKind == 'lawyer' && _job.isActive &&
        _job.status != 'searching' && _job.status != 'assigned') {
      return GlassButton(
        label: 'আইনি মতামত জমা দিন',
        icon: Icons.gavel_rounded,
        color: const Color(0xFF6A1B9A),
        onPressed: _submitOpinion,
      );
    }
    // CUSTOM-pricing jobs must be quoted (and approved) before work can start.
    if (_job.isActive && _job.status != 'searching' && _job.status != 'assigned') {
      if (_job.awaitingProviderQuote) {
        return GlassButton(
          label: 'কাজ দেখে কোট দিন',
          icon: Icons.request_quote_rounded,
          color: const Color(0xFFF59E0B),
          onPressed: _submitQuote,
        );
      }
      if (_job.awaitingQuoteApproval) {
        return Column(
          children: [
            const Icon(Icons.hourglass_top_rounded, color: Color(0xFFF59E0B), size: 44),
            const SizedBox(height: 10),
            Text(
              'গ্রাহকের অনুমোদনের অপেক্ষায় — ৳ ${_job.quotedAmount!.toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            GlassButton(label: 'রিফ্রেশ', isOutlined: true, onPressed: _refreshJob),
          ],
        );
      }
    }
    switch (_job.status) {
      case 'accepted':
        return GlassButton(
          label: 'আসছি বলুন',
          icon: Icons.directions_run_rounded,
          onPressed: () => _updateStatus('arriving'),
        );
      case 'arriving':
        return GlassButton(
          label: 'কাজ শুরু করুন (OTP)',
          icon: Icons.play_circle_rounded,
          onPressed: _requestAndConfirmStart,
        );
      case 'in_progress':
        return GlassButton(
          label: 'কাজ সম্পন্ন (OTP)',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF10B981),
          onPressed: _requestAndConfirmCompletion,
        );
      case 'completed':
        return Column(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 56),
            const SizedBox(height: 12),
            const Text(
              'কাজ সম্পন্ন হয়েছে!',
              style: TextStyle(color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            GlassButton(
              label: 'ফিরে যান',
              isOutlined: true,
              onPressed: () {
                widget.onJobCompleted?.call();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
