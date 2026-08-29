import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// Result of one status check against whatever backend the caller is confirming payment
/// against — deliberately generic (courses/deposits/lawyer/etc. each have their own confirm
/// endpoint) so this screen doesn't need to know what kind of order it's watching.
enum PaymentCheckStatus { pending, completed, failed }

/// Opens a real gateway checkout page in the external browser, then waits for the payment to
/// land — there's no deep-link package in this app yet, so the customer switches back to
/// Kichaai manually and this screen polls (and re-checks on every app resume) rather than
/// relying on a redirect straight back into the app. Reused across every SSLCommerz flow
/// (course enrollment, advance-booking deposit, lawyer consultation, ...) — callers only
/// supply the gateway URL and a way to ask "is it done yet."
class PaymentWaitingScreen extends StatefulWidget {
  final String gatewayPageUrl;
  final String title;
  final String titleEn;
  final double amount;
  final Future<PaymentCheckStatus> Function() checkStatus;
  final VoidCallback onConfirmed;
  // Optional — omit for a flow with no coupon support yet. Called when the customer applies a
  // code on the agreement-gate step; must re-run the SAME initiate-payment call the caller
  // already made to get gatewayPageUrl, but with couponCode included, and return the fresh
  // {gatewayPageUrl, amount} (gatewayPageUrl null + amount 0 means the coupon covered it fully —
  // this screen skips straight to onConfirmed() without ever opening a gateway).
  final Future<Map<String, dynamic>> Function(String couponCode)? applyCoupon;

  const PaymentWaitingScreen({
    super.key,
    required this.gatewayPageUrl,
    required this.title,
    required this.titleEn,
    required this.amount,
    required this.checkStatus,
    required this.onConfirmed,
    this.applyCoupon,
  });

  @override
  State<PaymentWaitingScreen> createState() => _PaymentWaitingScreenState();
}

class _PaymentWaitingScreenState extends State<PaymentWaitingScreen> with WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _isChecking = false;
  bool _failed = false;
  bool _isBn = true;
  bool _openedOnce = false;

  // Mandatory compliance gate (SSLCommerz payment-gateway review requirement): the customer
  // must explicitly tick a BLANK checkbox agreeing to Terms/Privacy/Refund policy — each
  // hyperlinked to the real page — before the gateway opens. This is the single choke-point
  // every SSLCommerz-backed payment in the app already passes through (dispatch deposits,
  // cook/laundry/commute bookings, matchmaking award/meet-fee, mess listing fee, courses,
  // subscriptions), so gating it here covers all of them without touching each call site.
  bool _agreed = false;
  bool _gatePassed = false;

  // Mutable — a coupon can replace these before the gateway ever opens (see applyCoupon).
  late String _gatewayPageUrl = widget.gatewayPageUrl;
  late double _amount = widget.amount;
  final _couponCtrl = TextEditingController();
  bool _applyingCoupon = false;
  String? _couponError;
  double? _couponDiscount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Gateway no longer auto-opens — see _confirmAndProceed, called only after the agreement
    // checkbox is ticked.
  }

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty || widget.applyCoupon == null) return;
    setState(() { _applyingCoupon = true; _couponError = null; });
    try {
      final result = await widget.applyCoupon!(code);
      if (!mounted) return;
      final newAmount = (result['amount'] as num?)?.toDouble() ?? _amount;
      setState(() {
        _couponDiscount = _amount - newAmount;
        _amount = newAmount;
        _gatewayPageUrl = result['gatewayPageUrl'] as String? ?? _gatewayPageUrl;
      });
    } catch (e) {
      if (mounted) setState(() => _couponError = _isBn ? 'কুপন কোড সঠিক নয়' : 'Invalid coupon code');
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  void _confirmAndProceed() {
    if (!_agreed) return;
    setState(() => _gatePassed = true);
    // A coupon that covered the full amount already marked the GatewayTransaction completed
    // server-side (see payment-gateway-service's initiateTransaction) — but the CALLER's own
    // checkStatus (confirmDepositPayment, confirmCourseEnrollment, etc.) is what actually flips
    // the order's own paid flag and does its side effects (e.g. generating the lawyer Meet
    // link) — that only runs once checkStatus is actually called. Skipping straight to
    // onConfirmed() here would leave the transaction "completed" in payment-gateway-service
    // while the order itself never learns about it. Still go through _check(), just without
    // ever opening a gateway page.
    if (_amount <= 0) {
      _check();
      // Safety net in case the first check races the backend committing the completed
      // transaction — same retry cadence as the real-payment path, just no gateway to open.
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _openGateway());
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> _openLegalPage(String path) async {
    try {
      await launchUrl(Uri.parse('https://kichaai.com$path'), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _couponCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Customer most likely just came back from paying in the browser — check right away
    // instead of waiting for the next timer tick.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _openGateway() async {
    _openedOnce = true;
    try {
      await launchUrl(Uri.parse(_gatewayPageUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Non-fatal — the "reopen payment page" button below covers this.
    }
  }

  Future<void> _check() async {
    if (_isChecking || !mounted) return;
    setState(() => _isChecking = true);
    try {
      final status = await widget.checkStatus();
      if (!mounted) return;
      if (status == PaymentCheckStatus.completed) {
        widget.onConfirmed();
        return;
      }
      setState(() {
        _isChecking = false;
        _failed = status == PaymentCheckStatus.failed;
      });
    } catch (_) {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Widget _buildAgreementGate() {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isBn ? widget.title : widget.titleEn,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (_couponDiscount != null && _couponDiscount! > 0) ...[
                  Text(
                    '৳ ${widget.amount.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 15, fontWeight: FontWeight.w600, decoration: TextDecoration.lineThrough),
                  ),
                  const SizedBox(height: 2),
                ],
                Text('৳ ${_amount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 26, fontWeight: FontWeight.w800)),
                if (widget.applyCoupon != null) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _couponCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _isBn ? 'কুপন কোড থাকলে দিন' : 'Have a coupon code?',
                          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          filled: true,
                          fillColor: AppColors.glassWhite,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.glassBorder)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _applyingCoupon
                        ? const SizedBox(width: 44, height: 44, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                        : TextButton(onPressed: _applyCoupon, child: Text(_isBn ? 'প্রয়োগ করুন' : 'Apply', style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700))),
                  ]),
                  if (_couponError != null) ...[
                    const SizedBox(height: 4),
                    Text(_couponError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ],
                  if (_couponDiscount != null && _couponDiscount! > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      _isBn ? '৳${_couponDiscount!.toStringAsFixed(0)} ছাড় প্রয়োগ হয়েছে ✓' : '৳${_couponDiscount!.toStringAsFixed(0)} discount applied ✓',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                GlassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreed,
                        activeColor: AppColors.deepBlue,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(
                            children: [
                              Text(
                                _isBn ? 'আমি পড়েছি এবং সম্মত ' : 'I have read and agree to the ',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
                              ),
                              GestureDetector(
                                onTap: () => _openLegalPage('/terms'),
                                child: Text(
                                  _isBn ? 'ব্যবহারের শর্তাবলী' : 'Terms & Conditions',
                                  style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                ),
                              ),
                              Text(_isBn ? ', ' : ', ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              GestureDetector(
                                onTap: () => _openLegalPage('/privacy'),
                                child: Text(
                                  _isBn ? 'প্রাইভেসি পলিসি' : 'Privacy Policy',
                                  style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                ),
                              ),
                              Text(_isBn ? ' এবং ' : ' and ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              GestureDetector(
                                onTap: () => _openLegalPage('/refund'),
                                child: Text(
                                  _isBn ? 'রিফান্ড ও রিটার্ন নীতি' : 'Return & Refund Policy',
                                  style: const TextStyle(color: AppColors.deepBlue, fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                ),
                              ),
                              Text(_isBn ? ' মেনে নিয়েছি।' : '.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GlassButton(
                  label: _amount <= 0
                      ? (_isBn ? 'সম্পন্ন করুন (বিনামূল্যে)' : 'Complete (Free)')
                      : (_isBn ? 'পেমেন্ট এগিয়ে নিন' : 'Proceed to Payment'),
                  onPressed: _agreed ? _confirmAndProceed : null,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(_isBn ? 'বাতিল করুন' : 'Cancel', style: const TextStyle(color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    if (!_gatePassed) return _buildAgreementGate();
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    gradient: _failed
                        ? const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)])
                        : AppColors.blueGradient,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: (_failed ? const Color(0xFFEF4444) : AppColors.deepBlue).withOpacity(0.35), blurRadius: 24)],
                  ),
                  child: Icon(
                    _failed ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
                    color: AppColors.ivory,
                    size: 44,
                  ),
                ).animate(onPlay: (c) => _failed ? null : c.repeat(reverse: true)).scale(
                      begin: const Offset(1, 1), end: const Offset(1.06, 1.06),
                      duration: 900.ms, curve: Curves.easeInOut,
                    ),
                const SizedBox(height: 24),
                Text(
                  _failed
                      ? (_isBn ? 'পেমেন্ট ব্যর্থ হয়েছে' : 'Payment Failed')
                      : (_isBn ? 'পেমেন্টের অপেক্ষায়...' : 'Waiting for Payment...'),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _isBn ? widget.title : widget.titleEn,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('৳ ${_amount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.deepBlue, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                GlassCard(
                  child: Text(
                    _failed
                        ? (_isBn
                            ? 'পেমেন্টটি সম্পন্ন হয়নি। আবার চেষ্টা করুন অথবা পরে ফিরে আসুন।'
                            : 'The payment did not go through. Try again or come back later.')
                        : (_isBn
                            ? 'ব্রাউজারে পেমেন্ট পেজ খোলা হয়েছে। bKash/Nagad/কার্ড দিয়ে পেমেন্ট সম্পন্ন করে এই স্ক্রিনে ফিরে আসুন — আমরা স্বয়ংক্রিয়ভাবে যাচাই করব।'
                            : 'The payment page opened in your browser. Complete payment with bKash/Nagad/Card, then come back here — we\'ll verify it automatically.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
                if (_failed) ...[
                  GlassButton(
                    label: _isBn ? 'আবার চেষ্টা করুন' : 'Try Again',
                    onPressed: () {
                      setState(() => _failed = false);
                      _openGateway();
                    },
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  GlassButton(
                    label: _isChecking
                        ? (_isBn ? 'যাচাই করা হচ্ছে...' : 'Checking...')
                        : (_isBn ? 'পেমেন্ট করেছি — এখন যাচাই করুন' : 'I\'ve Paid — Check Now'),
                    isLoading: _isChecking,
                    onPressed: _isChecking ? null : _check,
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _openGateway,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.deepBlue),
                    label: Text(
                      _openedOnce
                          ? (_isBn ? 'পেমেন্ট পেজ আবার খুলুন' : 'Reopen Payment Page')
                          : (_isBn ? 'পেমেন্ট পেজ খুলুন' : 'Open Payment Page'),
                      style: const TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(_isBn ? 'বাতিল করুন' : 'Cancel', style: const TextStyle(color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
