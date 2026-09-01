import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../widgets/glass_button.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'payment_waiting_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _client = ApiClient.instance.dio;
  Map<String, dynamic>? _subscription;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isBn = true;

  // Prices must match auth.service.ts's subscribePlan() planDetails exactly — this UI
  // shows what the customer will actually be charged, not just an approximation.
  final _plans = [
    {'plan': 'FREE', 'price': 0,
      'featuresBn': ['৫টি জব/মাস', 'বেসিক সাপোর্ট', 'স্ট্যান্ডার্ড লিস্টিং'],
      'featuresEn': ['5 jobs/month', 'Basic support', 'Standard listing']},
    {'plan': 'STANDARD', 'price': 399,
      'featuresBn': ['৩০টি জব/মাস', 'প্রায়োরিটি সাপোর্ট', 'উপরে তালিকাভুক্তি', 'ব্যাজ দেখানো'],
      'featuresEn': ['30 jobs/month', 'Priority support', 'Top listing', 'Verified badge']},
    {'plan': 'PRO', 'price': 799,
      'featuresBn': ['আনলিমিটেড জব', '২৪/৭ সাপোর্ট', 'সর্বোচ্চ অগ্রাধিকার', 'গোল্ড ব্যাজ', 'বিশ্লেষণ ড্যাশবোর্ড'],
      'featuresEn': ['Unlimited jobs', '24/7 support', 'Highest priority', 'Gold badge', 'Analytics dashboard']},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.get('/auth/subscriptions/me');
      if (mounted) setState(() { _subscription = res.data as Map<String, dynamic>?; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _subscribe(String plan) async {
    final colors = Theme.of(context).colorScheme;
    // FREE has nothing to charge, so skip the paid-order agreement gate — only
    // STANDARD/PRO actually place a paid order that needs it.
    bool agreed = plan == 'FREE';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text('$plan ${_isBn ? 'সাবস্ক্রিপশন' : 'subscription'}', style: TextStyle(color: colors.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isBn ? '$plan প্ল্যানে সাবস্ক্রাইব করতে চান?' : 'Subscribe to the $plan plan?', style: TextStyle(color: colors.outline)),
              if (plan != 'FREE')
                PolicyAgreementCheckbox(
                  value: agreed,
                  onChanged: (v) => setDialogState(() => agreed = v),
                  isBn: _isBn,
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: TextStyle(color: colors.outline))),
            TextButton(onPressed: agreed ? () => Navigator.pop(ctx, true) : null, child: Text(_isBn ? 'নিশ্চিত করুন' : 'Confirm', style: TextStyle(color: agreed ? colors.primary : colors.outline))),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await _client.post('/auth/subscriptions', data: {'plan': plan});

      if (plan == 'FREE') {
        // FREE is always instant, self-service — nothing to pay, nothing to verify.
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isBn ? '$plan সাবস্ক্রিপশন সক্রিয় হয়েছে' : '$plan subscription activated', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }

      // STANDARD/PRO land as PENDING_PAYMENT above — this is the real SSLCommerz path that
      // actually activates it, instead of the manual bKash/bank + admin-activation fallback.
      final initRes = await _client.post('/auth/subscriptions/pay/initiate');
      final gatewayPageUrl = (initRes.data as Map)['transaction']?['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isBn ? 'পেমেন্ট শুরু করা যায়নি — আবার চেষ্টা করুন' : 'Could not start the payment — please try again', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      final priceEntry = _plans.firstWhere((p) => p['plan'] == plan);
      final amount = (priceEntry['price'] as int).toDouble();
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? '$plan সাবস্ক্রিপশন' : '$plan Subscription',
          titleEn: '$plan Subscription',
          amount: amount,
          checkStatus: () async {
            try {
              await _client.post('/auth/subscriptions/pay/confirm');
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
          applyCoupon: (code) async {
            final r = await _client.post('/auth/subscriptions/pay/initiate',
                data: {'couponCode': code});
            final t = (r.data as Map)['transaction'] as Map?;
            return {
              'gatewayPageUrl': t?['gatewayPageUrl'],
              'amount': double.tryParse('${t?['amount']}') ?? amount,
            };
          },
        ),
      ));
      await _load();
    } catch (e) {
      final ex = ApiClient.mapError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ex.messageBn, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancel() async {
    final colors = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(_isBn ? 'সাবস্ক্রিপশন বাতিল করুন?' : 'Cancel subscription?', style: TextStyle(color: colors.onSurface)),
        content: Text(_isBn ? 'আপনার সাবস্ক্রিপশন বাতিল করতে চান?' : 'Cancel your subscription?', style: TextStyle(color: colors.outline)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'না' : 'No', style: TextStyle(color: colors.outline))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'বাতিল করুন' : 'Cancel', style: const TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _client.post('/auth/subscriptions/cancel');
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    final currentPlan = _subscription?['plan'] as String? ?? 'FREE';

    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'সাবস্ক্রিপশন' : 'Subscription', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                _buildCurrentCard(currentPlan),
                const SizedBox(height: 24),
                Text(_isBn ? 'প্ল্যান তুলনা' : 'Compare plans', style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
                const SizedBox(height: 12),
                ..._plans.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  final plan = p['plan'] as String;
                  final price = p['price'] as int;
                  final features = (p[_isBn ? 'featuresBn' : 'featuresEn'] as List).cast<String>();
                  final isCurrent = plan == currentPlan;
                  return _buildPlanCard(plan, price, features, isCurrent, i);
                }),
                if (currentPlan != 'FREE') ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _cancel,
                    child: Text(_isBn ? 'সাবস্ক্রিপশন বাতিল করুন' : 'Cancel subscription', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildCurrentCard(String plan) {
    final colors = Theme.of(context).colorScheme;
    final planColors = {'FREE': const Color(0xFF6B7280), 'STANDARD': colors.primary, 'PRO': const Color(0xFFF59E0B)};
    final color = planColors[plan] ?? colors.outline;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isBn ? 'বর্তমান প্ল্যান' : 'Current plan', style: TextStyle(color: colors.outline, fontSize: 12)),
          const SizedBox(height: 4),
          Text(plan, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          if (_subscription?['expiresAt'] != null)
            Text('${_isBn ? 'মেয়াদ' : 'Expires'}: ${_subscription!['expiresAt'].toString().substring(0, 10)}', style: TextStyle(color: colors.outline, fontSize: 11)),
        ]),
        const Spacer(),
        Icon(Icons.star_rounded, color: color, size: 48),
      ]),
    ).animate().fadeIn();
  }

  Widget _buildPlanCard(String plan, int price, List<String> features, bool isCurrent, int index) {
    final colors = Theme.of(context).colorScheme;
    final planColors = {'FREE': const Color(0xFF6B7280), 'STANDARD': colors.primary, 'PRO': const Color(0xFFF59E0B)};
    final color = planColors[plan] ?? colors.outline;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCurrent ? color : colors.outlineVariant, width: isCurrent ? 2 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(plan, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (isCurrent) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(_isBn ? 'বর্তমান' : 'Current', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600))),
              const Spacer(),
              Text(price == 0 ? (_isBn ? 'বিনামূল্যে' : 'Free') : '৳$price/${_isBn ? 'মাস' : 'mo'}', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: color, size: 16),
                const SizedBox(width: 8),
                Text(f, style: TextStyle(color: colors.onSurface, fontSize: 13)),
              ]),
            )),
            if (!isCurrent) ...[
              const SizedBox(height: 12),
              GlassButton(
                label: _isSaving ? (_isBn ? 'প্রসেস হচ্ছে...' : 'Processing...') : (_isBn ? '$plan নির্বাচন করুন' : 'Choose $plan'),
                onPressed: _isSaving ? null : () => _subscribe(plan),
              ),
            ],
          ]),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 80)).slideY(begin: 0.1, end: 0);
  }
}
