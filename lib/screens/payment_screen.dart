import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_gradients.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _client = ApiClient.instance.dio;
  List<dynamic> _payments = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;
  String? _userId;
  bool _isBn = true;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await _load(reset: true);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 && _hasMore && !_isLoading) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      _hasMore = true;
    }
    setState(() => _isLoading = true);
    try {
      final res = await _client.get('/payment/transactions', queryParameters: {
        'customerId': _userId,
        'limit': _limit,
        'offset': _offset,
      });
      final data = res.data;
      final items = (data is List ? data : (data['items'] ?? data['data'] ?? [])) as List;
      if (mounted) {
        setState(() {
          if (reset) _payments = items; else _payments.addAll(items);
          _offset += items.length;
          _hasMore = items.length >= _limit;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
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
        title: Text(_isBn ? 'পেমেন্ট ইতিহাস' : 'Payment History', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading && _payments.isEmpty
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _payments.isEmpty
              ? Center(child: Text(_isBn ? 'কোনো পেমেন্ট নেই' : 'No payments', style: TextStyle(color: colors.outline)))
              : Column(
                  children: [
                    _buildSummaryCard(),
                    Expanded(
                      child: RefreshIndicator(
                        color: colors.primary,
                        backgroundColor: colors.surface,
                        onRefresh: () => _load(reset: true),
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _payments.length + (_hasMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _payments.length) {
                              return Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(color: colors.primary, strokeWidth: 2)),
                              );
                            }
                            return _buildPaymentTile(_payments[i] as Map<String, dynamic>, i);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSummaryCard() {
    final colors = Theme.of(context).colorScheme;
    final total = _payments.fold<double>(0, (sum, p) => sum + ((p['amount'] ?? 0) as num).toDouble());
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppGradients.primary(colors),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isBn ? 'মোট পেমেন্ট' : 'Total paid', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text('৳ ${total.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          Text(_isBn ? '${_payments.length}টি লেনদেন' : '${_payments.length} transactions', style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
        const Spacer(),
        const Icon(Icons.receipt_long_rounded, color: Colors.white24, size: 48),
      ]),
    ).animate().fadeIn().slideY(begin: -0.1, end: 0);
  }

  Widget _buildPaymentTile(Map<String, dynamic> p, int index) {
    final colors = Theme.of(context).colorScheme;
    final status = p['status'] as String? ?? 'completed';
    final statusColor = switch (status) {
      'completed' || 'success' => const Color(0xFF10B981),
      'failed' || 'cancelled' => const Color(0xFFEF4444),
      _ => const Color(0xFFF59E0B),
    };
    final statusLabel = _isBn
        ? switch (status) {
            'completed' || 'success' => 'সম্পন্ন',
            'failed' => 'ব্যর্থ',
            'cancelled' => 'বাতিল',
            _ => 'প্রক্রিয়াধীন',
          }
        : switch (status) {
            'completed' || 'success' => 'Completed',
            'failed' => 'Failed',
            'cancelled' => 'Cancelled',
            _ => 'Processing',
          };
    final method = p['method'] ?? p['paymentMethod'] ?? (_isBn ? 'অনলাইন' : 'Online');
    final amount = (p['amount'] ?? 0) as num;
    final refundable = (status == 'completed' || status == 'success') && amount > 0;

    return GestureDetector(
      onTap: refundable ? () => _showRefundSheet(p) : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            status == 'completed' || status == 'success' ? Icons.check_rounded : Icons.close_rounded,
            color: statusColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['description'] ?? (_isBn ? 'পেমেন্ট' : 'Payment'), style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              Text(method, style: TextStyle(color: colors.outline, fontSize: 11)),
              Text(' · ', style: TextStyle(color: colors.outline, fontSize: 11)),
              Text(p['createdAt']?.toString().substring(0, 10) ?? '', style: TextStyle(color: colors.outline, fontSize: 11)),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '৳${amount.toStringAsFixed(0)}',
            style: TextStyle(color: statusColor, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    ).animate(delay: Duration(milliseconds: index * 40)).fadeIn().slideX(begin: 0.03, end: 0),
    );
  }

  void _showRefundSheet(Map<String, dynamic> p) {
    final colors = Theme.of(context).colorScheme;
    final txnId = p['id']?.toString() ?? '';
    if (txnId.isEmpty) return;
    final maxAmount = ((p['amount'] ?? 0) as num).toDouble();
    final amountCtrl = TextEditingController(text: maxAmount.toStringAsFixed(0));
    final reasonCtrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              Text(_isBn ? 'রিফান্ডের আবেদন' : 'Request refund', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_isBn ? 'অ্যাডমিন যাচাই করে অনুমোদন করলে টাকা ফেরত দেওয়া হবে।' : 'Refunded once an admin reviews and approves.', style: TextStyle(color: colors.outline, fontSize: 12)),
              const SizedBox(height: 18),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700),
                decoration: _dec(_isBn ? 'পরিমাণ (৳)' : 'Amount (৳)', prefix: '৳ '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                style: TextStyle(color: colors.onSurface, fontSize: 14),
                decoration: _dec(_isBn ? 'কারণ (ঐচ্ছিক)' : 'Reason (optional)'),
              ),
              const SizedBox(height: 20),
              GlassRefundButton(
                label: _isBn ? 'আবেদন জমা দিন' : 'Submit request',
                saving: saving,
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text.trim());
                  if (amt == null || amt <= 0 || amt > maxAmount) {
                    _snack(_isBn ? 'সঠিক পরিমাণ দিন (সর্বোচ্চ ৳${maxAmount.toStringAsFixed(0)})' : 'Enter a valid amount (max ৳${maxAmount.toStringAsFixed(0)})', error: true);
                    return;
                  }
                  setS(() => saving = true);
                  try {
                    await _client.post('/payment/refunds', data: {
                      'transactionId': txnId,
                      'amount': amt,
                      if (reasonCtrl.text.trim().isNotEmpty) 'reason': reasonCtrl.text.trim(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack(_isBn ? 'রিফান্ডের আবেদন জমা হয়েছে' : 'Refund request submitted');
                    _load(reset: true);
                  } catch (e) {
                    setS(() => saving = false);
                    _snack(ApiClient.mapError(e).messageBn, error: true);
                  }
                },
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, {String? prefix}) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
        hintText: hint,
        prefixText: prefix,
        prefixStyle: TextStyle(color: colors.primary, fontSize: 16, fontWeight: FontWeight.w700),
        hintStyle: TextStyle(color: colors.outline, fontSize: 13),
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.primary)),
      );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// Small inline button with its own loading state for the refund sheet.
class GlassRefundButton extends StatelessWidget {
  final bool saving;
  final String label;
  final VoidCallback onPressed;
  const GlassRefundButton({super.key, required this.saving, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: saving ? null : onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(14)),
        child: saving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
