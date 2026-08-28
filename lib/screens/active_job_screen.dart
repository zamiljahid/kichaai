import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../core/utils/meet_link.dart';
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
  bool _isBn = true;

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'চ্যাট এখনো তৈরি হয়নি — একটু পরে আবার চেষ্টা করুন' : 'Chat not created yet — try again shortly', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFF59E0B),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'চ্যাট খোলা যায়নি' : 'Could not open chat', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
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
      _showError(_isBn ? 'স্ট্যাটাস আপডেট করতে সমস্যা হয়েছে' : 'Could not update status');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestAndConfirmStart() async {
    setState(() => _isLoading = true);
    try {
      final devOtp = await DispatchService.instance.requestStart(_job.id);
      setState(() => _isLoading = false);
      final otp = await _showOtpDialog(_isBn ? 'কাজ শুরুর OTP' : 'Job start OTP', devOtp: devOtp);
      if (otp == null || otp.isEmpty) return;
      setState(() => _isLoading = true);
      await DispatchService.instance.confirmStart(_job.id, otp);
      final updated = await DispatchService.instance.getJob(_job.id);
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (e) {
      // Show the real backend reason (e.g. "already started", wrong job status) instead of a
      // generic OTP message — a masked reason here is exactly what hid the identity-check bug.
      _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestAndConfirmCompletion() async {
    setState(() => _isLoading = true);
    try {
      final devOtp = await DispatchService.instance.requestCompletion(_job.id);
      setState(() => _isLoading = false);
      final otp = await _showOtpDialog(_isBn ? 'কাজ সম্পন্নের OTP' : 'Job completion OTP', devOtp: devOtp);
      if (otp == null || otp.isEmpty) return;
      setState(() => _isLoading = true);
      await DispatchService.instance.confirmCompletion(_job.id, otp);
      final updated = await DispatchService.instance.getJob(_job.id);
      if (mounted) {
        setState(() => _job = updated);
        _syncLocationTracking();
      }
    } catch (e) {
      _showError(ApiClient.mapError(e).localized(_isBn));
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
        title: Text(_isBn ? 'কাজ দেখে কোট দিন' : 'Quote after seeing the job', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isBn ? 'আপনার প্রস্তাবিত মূল্য (৳)। গ্রাহক অনুমোদন করলেই কাজ শুরু হবে।' : 'Your proposed price (৳). Work begins once the customer approves.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              final v = double.tryParse(amountCtrl.text.trim());
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: Text(_isBn ? 'কোট পাঠান' : 'Send quote', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
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
      _showError(_isBn ? 'কোট পাঠাতে সমস্যা হয়েছে' : 'Could not send the quote');
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
              Text(_isBn ? 'টেস্ট মোড — OTP নিজে থেকেই ভরা হয়েছে: $devOtp' : 'Test mode — OTP auto-filled: $devOtp',
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
            child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _otpController.text.trim()),
            child: Text(_isBn ? 'নিশ্চিত' : 'Confirm', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
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
    _isBn = context.watch<LanguageNotifier>().isBengali;
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
                      // Rides are photo-exempt server-side (PHOTO_EXEMPT_KINDS): the start/
                      // completion OTPs and the GPS trail are the proof, so the driver already
                      // gets the 15% rate and request-completion no longer demands a picture.
                      // Showing this card would tell them to photograph nothing for a discount
                      // they already have.
                      if (_trackableStatuses.contains(_job.status) &&
                          _job.serviceKind != 'lawyer' &&
                          !_job.isRide) ...[
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
          Text(_isBn ? 'সক্রিয় কাজ' : 'Active job', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
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
            _isBn ? 'অবস্থা: ${_job.statusLabel(true)}' : 'Status: ${_job.statusLabel(false)}',
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'ছবি আপলোড হয়েছে — কমিশন এখন ১৫%' : 'Photo uploaded — commission is now 15%', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'ছবি আপলোড ব্যর্থ হয়েছে — আবার চেষ্টা করুন' : 'Photo upload failed — try again', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
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
              Text(_isBn ? 'কাজের ছবি' : 'Job photos', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (hasAny ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasAny
                      ? (_isBn ? 'কমিশন ১৫%' : '15% commission')
                      : (_isBn ? 'ছবি ছাড়া কমিশন ২০%' : '20% commission without photo'),
                  style: TextStyle(
                    color: hasAny ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontSize: 10.5, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_isBn ? 'কাজ শুরু ও শেষের ছবি তুলুন — ছবি থাকলে কমিশন ২০% এর বদলে ১৫%।' : 'Take start and end photos — commission drops from 20% to 15% with a photo.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _photoSlot(_isBn ? 'শুরুর ছবি' : 'Start photo', 'start', _job.startPhotoUrl, _uploadingStartPhoto)),
              const SizedBox(width: 12),
              Expanded(child: _photoSlot(_isBn ? 'শেষের ছবি' : 'End photo', 'end', _job.endPhotoUrl, _uploadingEndPhoto)),
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
          Text(_isBn ? 'গ্রাহকের তথ্য' : 'Customer info', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.person_rounded, color: AppColors.deepBlue, size: 18),
            const SizedBox(width: 8),
            Text(
              _job.customerNameSnapshot ?? (_isBn ? 'অজানা' : 'Unknown'),
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
                  ? (_isBn ? 'গ্রাহক কোনো ফোন নম্বর দেননি — চ্যাটে যোগাযোগ করুন' : 'The customer did not provide a phone number — contact them via chat')
                  : (_isBn ? 'গ্রাহক নিশ্চিত না করা পর্যন্ত নম্বর দেখা যাবে না — ততক্ষণ চ্যাটে কথা বলুন' : 'The number stays hidden until the customer confirms — chat until then'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
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
                Text(_isBn ? 'গ্রাহকের সাথে চ্যাট করুন' : 'Chat with customer', style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          // Lawyer consultations are Google Meet only — pickupLatitude/Longitude are a
          // hardcoded Dhaka-center placeholder (never the customer's real coordinates,
          // see lawyer_consultation_screen.dart's createJob call), so showing them as a
          // map/"গ্রাহকের অবস্থান" here would mislead the lawyer into thinking that's
          // where the client actually is.
          if (_job.serviceKind == 'lawyer') ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.videocam_rounded, color: Color(0xFF6A1B9A), size: 18),
              const SizedBox(width: 8),
              Text(_isBn ? 'রিমোট কনসালটেশন (Google Meet) — কোনো ফিজিক্যাল লোকেশন নেই' : 'Remote consultation (Google Meet) — no physical location', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            // No Meet link exists until the customer pays the consultation fee (see
            // dispatch.service.ts's confirmDepositPayment) — without this, accepting a job
            // that then shows nothing here reads as broken rather than "waiting on payment".
            if (_job.depositRequired) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD98A0B).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD98A0B).withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.hourglass_top_rounded, color: Color(0xFFB27107), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isBn ? 'গ্রাহকের পেমেন্টের অপেক্ষায় — পরিশোধ হলে Meet লিংক এখানে দেখা যাবে' : 'Waiting for customer payment — the Meet link will appear here once paid',
                      style: const TextStyle(color: Color(0xFF8A5A06), fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
            // Previously the Meet link was only ever shown once, in-memory, on
            // lawyer_consultation_screen.dart's initial "joined" step — closing
            // the app or navigating away lost it for good, for BOTH the customer
            // and the lawyer. This screen (their shared "active job" view) is
            // reachable any time from either side, so surfacing it here fixes that.
            if (_job.meetLink != null && _job.meetLink!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6A1B9A).withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isBn ? 'মিটিং লিংক' : 'Meeting link', style: const TextStyle(color: Color(0xFF6A1B9A), fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SelectableText(_job.meetLink!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => openMeetLink(context, _job.meetLink!),
                        icon: const Icon(Icons.videocam_rounded, size: 17),
                        label: Text(_isBn ? 'মিটিং এ যোগ দিন' : 'Join meeting'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A1B9A), foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _job.meetLink!));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(_isBn ? 'লিংক কপি হয়েছে' : 'Link copied', style: const TextStyle(color: Colors.white)),
                          backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating,
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF6A1B9A).withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.copy_rounded, color: Color(0xFF6A1B9A), size: 18),
                      ),
                    ),
                  ]),
                ]),
              ),
            ],
          ] else ...[
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
            // Customer's pickup point is fixed (unlike the customer's live map of the moving
            // provider, see job_tracking_screen.dart) — a static marker is enough, no polling.
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 180,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(_job.pickupLatitude, _job.pickupLongitude),
                    zoom: 15,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('customer_pickup'),
                      position: LatLng(_job.pickupLatitude, _job.pickupLongitude),
                      infoWindow: InfoWindow(title: _isBn ? 'গ্রাহকের অবস্থান' : 'Customer\'s location'),
                    ),
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  liteModeEnabled: false,
                ),
              ),
            ),
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
          Text(_isBn ? 'কাজের বিবরণ' : 'Job details', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Text(_job.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          if (_job.description != null && _job.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_job.description!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          if (_job.serviceKind == 'caregiver' && _hasCaregiverInfo(_job)) ...[
            const SizedBox(height: 10),
            _buildCaregiverInfoBlock(),
          ],
          if (_job.isRide) ...[
            const SizedBox(height: 12),
            _buildRideRouteBlock(),
          ],
          if (_job.estimatedAmount != null) ...[
            const SizedBox(height: 8),
            Text(
              _isBn ? 'আনুমানিক মূল্য: ৳ ${_job.estimatedAmount!.toStringAsFixed(0)}' : 'Estimated price: ৳ ${_job.estimatedAmount!.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.deepBlue, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  // ── Ride: route + navigation ─────────────────────────────────────
  // A driver was previously shown the pickup and nothing else — no destination anywhere on this
  // screen, and no way to navigate to either end.
  Widget _buildRideRouteBlock() {
    // vehicleType lives on RideDetails (the backend also mirrors it into job.specialization,
    // which is what the broadcast filters on, but that field is not on this model).
    final vehicle = _job.rideDetail?.vehicleType;
    final passengers = _job.rideDetail?.passengerCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _routeRow(
          Icons.trip_origin_rounded,
          const Color(0xFF22C55E),
          _isBn ? 'যাত্রা শুরু' : 'Pickup',
          _job.pickupAddressSnapshot ?? (_isBn ? 'ম্যাপে দেখানো আছে' : 'Pinned on the map'),
          _job.pickupLatitude,
          _job.pickupLongitude,
        ),
        const SizedBox(height: 8),
        _routeRow(
          Icons.flag_rounded,
          AppColors.deepBlue,
          _isBn ? 'গন্তব্য' : 'Destination',
          _job.dropoffAddressSnapshot ?? (_isBn ? 'ম্যাপে দেখানো আছে' : 'Pinned on the map'),
          _job.dropoffLatitude,
          _job.dropoffLongitude,
        ),
        if (_job.distanceKm != null || (vehicle != null && vehicle.isNotEmpty)) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (vehicle != null && vehicle.isNotEmpty) ...[
                Icon(
                  switch (vehicle) {
                    'motorcycle' || 'motorcycle_plus' => Icons.two_wheeler_rounded,
                    'cng' || 'cng_plus' => Icons.electric_rickshaw_rounded,
                    _ => Icons.directions_car_filled_rounded,
                  },
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  _isBn
                      ? (kRideVehicleLabelsBn[vehicle] ?? vehicle)
                      : (kRideVehicleLabelsEn[vehicle] ?? vehicle),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              if (_job.distanceKm != null) ...[
                const SizedBox(width: 10),
                Text(
                  _isBn
                      ? 'প্রায় ${_job.distanceKm!.toStringAsFixed(1)} কিমি'
                      : 'About ${_job.distanceKm!.toStringAsFixed(1)} km',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
              if (passengers != null && passengers > 1) ...[
                const SizedBox(width: 10),
                const Icon(Icons.people_alt_rounded, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  _isBn ? '$passengers জন' : '$passengers passengers',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _routeRow(
    IconData icon,
    Color color,
    String label,
    String address,
    double? lat,
    double? lon,
  ) {
    final canNavigate = lat != null && lon != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              Text(
                address,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (canNavigate)
          GestureDetector(
            onTap: () => _navigateTo(lat, lon),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.glassBlue,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.glassBorderBlue),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation_rounded, size: 14, color: AppColors.deepBlue),
                  const SizedBox(width: 5),
                  Text(
                    _isBn ? 'চলুন' : 'Go',
                    style: const TextStyle(
                        color: AppColors.deepBlue, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Hand the coordinates to whatever navigation app the driver already uses. google.navigation
  /// is the Android intent that starts turn-by-turn straight away; the https URL is the
  /// cross-platform fallback (and what iOS/web get).
  Future<void> _navigateTo(double lat, double lon) async {
    final candidates = [
      Uri.parse('google.navigation:q=$lat,$lon&mode=d'),
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving'),
    ];
    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // Try the next form rather than failing the whole action.
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        _isBn ? 'ম্যাপ অ্যাপ খোলা যায়নি' : 'Could not open a maps app',
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: AppColors.softRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  bool _hasCaregiverInfo(JobModel job) =>
      (job.caregiverDetail?.patientCondition?.isNotEmpty ?? false) ||
      job.caregiverDetail?.patientAge != null ||
      (job.providerGenderPreference != null && job.providerGenderPreference != 'any');

  // Caregiver-only info block — patient condition/age + the customer's self-declared
  // gender preference (informational only, never filters who gets the broadcast).
  Widget _buildCaregiverInfoBlock() {
    final detail = _job.caregiverDetail;
    final rows = <Widget>[];
    void addRow(IconData icon, String text) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.deepBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
        ],
      ));
    }

    if (detail?.patientCondition != null && detail!.patientCondition!.isNotEmpty) {
      addRow(Icons.medical_information_rounded, detail.patientCondition!);
    }
    if (detail?.patientAge != null) {
      addRow(Icons.cake_rounded, _isBn ? 'বয়স: ${detail!.patientAge}' : 'Age: ${detail!.patientAge}');
    }
    if (_job.providerGenderPreference != null && _job.providerGenderPreference != 'any') {
      addRow(Icons.wc_rounded, _isBn ? 'পছন্দ: ${_job.providerGenderPreference}' : 'Preference: ${_job.providerGenderPreference}');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.deepBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
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
        title: Text(_isBn ? 'আইনি মতামত জমা দিন' : 'Submit legal opinion', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _opinionField(summaryCtrl, _isBn ? 'সারসংক্ষেপ (আবশ্যক)' : 'Summary (required)', maxLines: 3),
              const SizedBox(height: 12),
              _opinionField(adviceCtrl, _isBn ? 'পরামর্শ (ঐচ্ছিক)' : 'Advice (optional)', maxLines: 2),
              const SizedBox(height: 12),
              _opinionField(stepsCtrl, _isBn ? 'পরবর্তী পদক্ষেপ (ঐচ্ছিক)' : 'Next steps (optional)', maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              if (summaryCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: Text(_isBn ? 'জমা দিন' : 'Submit', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700)),
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
      _showError(_isBn ? 'মতামত জমা দিতে সমস্যা হয়েছে' : 'Could not submit the opinion');
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
        hint = _isBn
            ? '১৫ মিনিটের মধ্যে বাতিল ফ্রি (${_job.cancelGraceMinutesLeft} মিনিট বাকি)'
            : 'Free cancellation within 15 minutes (${_job.cancelGraceMinutesLeft} min left)';
        hintColor = AppColors.textMuted;
        break;
      case 'fee':
        hint = _isBn
            ? 'গ্রাহক কাজ শুরু নিশ্চিত করেছেন — বাতিল করলে রেড কার্ড + কমিশন দেনা'
            : 'Customer has confirmed the job start — cancelling means a red card + commission due';
        hintColor = const Color(0xFFEF4444);
        break;
      default: // card
        hint = _isBn ? 'সময় শেষ — বাতিল করলে ১টি রেড কার্ড' : 'Time is up — cancelling means 1 red card';
        hintColor = const Color(0xFFF59E0B);
    }
    return Column(
      children: [
        TextButton.icon(
          onPressed: _cancelJob,
          icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 18),
          label: Text(_isBn ? 'কাজটি বাতিল করুন' : 'Cancel this job',
              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
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
        body = _isBn ? 'এখন বাতিল করলে কোনো জরিমানা নেই। নিশ্চিত?' : 'Cancelling now carries no penalty. Confirm?';
        break;
      case 'fee':
        body = _isBn
            ? 'গ্রাহক কাজ শুরু নিশ্চিত করেছেন। বাতিল করলে ১টি রেড কার্ড পাবেন এবং '
                'কমিশন দেনা হিসেবে বসবে — দেনা না মেটানো পর্যন্ত নতুন কাজ পাবেন না। নিশ্চিত?'
            : 'The customer has confirmed the job start. Cancelling gives you 1 red card and '
                'a commission due — you won\'t get new jobs until it\'s settled. Confirm?';
        break;
      default: // card
        body = _isBn
            ? 'ফ্রি সময় (১৫ মিনিট) শেষ। বাতিল করলে ১টি রেড কার্ড পাবেন। '
                '৩টি কার্ড হলে ৭ দিনের জন্য কাজ বন্ধ থাকবে। নিশ্চিত?'
            : 'The free window (15 minutes) is over. Cancelling gives you 1 red card. '
                '3 cards means a 7-day suspension. Confirm?';
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isBn ? 'কাজ বাতিল' : 'Cancel job', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'না' : 'No', style: const TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'হ্যাঁ, বাতিল করুন' : 'Yes, cancel', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700))),
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
      _showError(_isBn ? 'বাতিল করতে সমস্যা হয়েছে' : 'Could not cancel the job');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCancelResult(CancelResult r) {
    String msg;
    if (!r.hadPenalty) {
      msg = _isBn ? 'কাজ বাতিল হয়েছে। কোনো জরিমানা হয়নি।' : 'Job cancelled. No penalty applied.';
    } else if (_isBn) {
      final parts = <String>['১টি রেড কার্ড যোগ হয়েছে'];
      if (r.feeCharged && r.feeAmount != null) {
        parts.add('৳${r.feeAmount!.toStringAsFixed(0)} কমিশন দেনা বসেছে (দেনা না মেটালে নতুন কাজ বন্ধ)');
      }
      if (r.suspended) {
        final until = r.bannedUntil != null ? _fmtDate(r.bannedUntil!) : '৭ দিন';
        parts.add('৩টি কার্ড হয়ে যাওয়ায় $until পর্যন্ত কাজ বন্ধ');
      }
      msg = '${parts.join('।\n')}।';
    } else {
      final parts = <String>['1 red card added'];
      if (r.feeCharged && r.feeAmount != null) {
        parts.add('৳${r.feeAmount!.toStringAsFixed(0)} commission due added (no new jobs until settled)');
      }
      if (r.suspended) {
        final until = r.bannedUntil != null ? _fmtDate(r.bannedUntil!) : '7 days';
        parts.add('3 cards reached — suspended until $until');
      }
      msg = '${parts.join('.\n')}.';
    }
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
            r.hadPenalty
                ? (_isBn ? 'বাতিল হয়েছে (জরিমানা প্রযোজ্য)' : 'Cancelled (penalty applied)')
                : (_isBn ? 'বাতিল হয়েছে' : 'Cancelled'),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_isBn ? 'ঠিক আছে' : 'OK', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700))),
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
        label: _isBn ? 'আইনি মতামত জমা দিন' : 'Submit legal opinion',
        icon: Icons.gavel_rounded,
        color: const Color(0xFF6A1B9A),
        onPressed: _submitOpinion,
      );
    }
    // CUSTOM-pricing jobs must be quoted (and approved) before work can start.
    if (_job.isActive && _job.status != 'searching' && _job.status != 'assigned') {
      if (_job.awaitingProviderQuote) {
        return GlassButton(
          label: _isBn ? 'কাজ দেখে কোট দিন' : 'Quote after seeing the job',
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
              _isBn
                  ? 'গ্রাহকের অনুমোদনের অপেক্ষায় — ৳ ${_job.quotedAmount!.toStringAsFixed(0)}'
                  : 'Awaiting customer approval — ৳ ${_job.quotedAmount!.toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            GlassButton(label: _isBn ? 'রিফ্রেশ' : 'Refresh', isOutlined: true, onPressed: _refreshJob),
          ],
        );
      }
    }
    switch (_job.status) {
      case 'confirmed':
        // Advance-booking (photographer/cinematographer/makeup_artist) — the customer already
        // locked this provider in for a future date; there's no separate "accept the offer"
        // step for these, so the day-of flow starts here instead of at 'accepted'. Previously
        // there was no case for this status at all — the job could never progress past
        // 'confirmed' and the provider was never paid for it.
        return GlassButton(
          label: _isBn ? 'আসছি বলুন' : 'I\'m on my way',
          icon: Icons.directions_run_rounded,
          onPressed: () => _updateStatus('arriving'),
        );
      case 'accepted':
        return GlassButton(
          label: _isBn ? 'আসছি বলুন' : 'I\'m on my way',
          icon: Icons.directions_run_rounded,
          onPressed: () => _updateStatus('arriving'),
        );
      case 'arriving':
        return GlassButton(
          label: _isBn ? 'কাজ শুরু করুন (OTP)' : 'Start job (OTP)',
          icon: Icons.play_circle_rounded,
          onPressed: _requestAndConfirmStart,
        );
      case 'in_progress':
        return GlassButton(
          label: _isBn ? 'কাজ সম্পন্ন (OTP)' : 'Complete job (OTP)',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF10B981),
          onPressed: _requestAndConfirmCompletion,
        );
      case 'completed':
        return Column(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 56),
            const SizedBox(height: 12),
            Text(
              _isBn ? 'কাজ সম্পন্ন হয়েছে!' : 'Job complete!',
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            GlassButton(
              label: _isBn ? 'ফিরে যান' : 'Go back',
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
