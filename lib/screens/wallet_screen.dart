import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/finance_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_button.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic>? _wallet;
  List<dynamic> _transactions = [];
  List<dynamic> _payouts = [];
  bool _isLoading = true;
  String? _providerId;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _providerId = await ApiClient.getProviderProfileId();
    if (_providerId == null) {
      setState(() => _isLoading = false);
      return;
    }
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final wallet = await FinanceService.instance.getWallet();
      final transactions = await FinanceService.instance.listTransactions(providerId: _providerId);
      final payouts = await FinanceService.instance.listPayouts(providerId: _providerId);
      if (mounted) {
        setState(() {
          _wallet = {'balance': wallet.balance, 'currency': wallet.currency};
          _transactions = transactions;
          _payouts = payouts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _payoutMethods = [
    ('bkash', 'bKash', 'bKash'),
    ('nagad', 'নগদ', 'Nagad'),
    ('bank_transfer', 'ব্যাংক ট্রান্সফার', 'Bank Transfer'),
  ];

  void _showPayoutSheet() {
    final colors = Theme.of(context).colorScheme;
    final amountCtrl = TextEditingController();
    final accountCtrl = TextEditingController();
    String method = 'bkash';
    bool isSaving = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: colors.surface,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(_isBn ? 'উত্তোলনের অনুরোধ' : 'Payout request', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _sheetField(amountCtrl, _isBn ? 'পরিমাণ (৳)' : 'Amount (৳)', Icons.currency_exchange_rounded, TextInputType.number),
                    const SizedBox(height: 12),
                    Text(_isBn ? 'পেআউট পদ্ধতি' : 'Payout method', style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: _payoutMethods.map((m) {
                        final selected = method == m.$1;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setS(() => method = m.$1),
                            child: Container(
                              margin: EdgeInsets.only(right: m.$1 != _payoutMethods.last.$1 ? 8 : 0),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? colors.primary.withOpacity(0.1) : colors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: selected ? colors.primary : colors.outlineVariant),
                              ),
                              child: Text(
                                _isBn ? m.$2 : m.$3,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: selected ? colors.primary : colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _sheetField(
                      accountCtrl,
                      method == 'bank_transfer'
                          ? (_isBn ? 'ব্যাংক নাম, একাউন্ট নম্বর, শাখা' : 'Bank name, account number, branch')
                          : (_isBn ? 'মোবাইল নম্বর' : 'Mobile number'),
                      method == 'bank_transfer' ? Icons.account_balance_outlined : Icons.phone_android_rounded,
                      method == 'bank_transfer' ? null : TextInputType.phone,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
                    ],
                    const SizedBox(height: 24),
                    GlassButton(
                      label: isSaving ? (_isBn ? 'পাঠানো হচ্ছে...' : 'Sending...') : (_isBn ? 'অনুরোধ পাঠান' : 'Send request'),
                      onPressed: isSaving ? null : () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) {
                          setS(() => error = _isBn ? 'সঠিক পরিমাণ দিন' : 'Enter a valid amount');
                          return;
                        }
                        if (accountCtrl.text.trim().isEmpty) {
                          setS(() => error = _isBn ? 'একাউন্টের তথ্য দিন' : 'Enter account details');
                          return;
                        }
                        setS(() { isSaving = true; error = null; });
                        try {
                          await FinanceService.instance.requestPayout(
                            amount: amount,
                            payoutMethod: method,
                            payoutAccountInfo: accountCtrl.text.trim(),
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            _loadAll();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_isBn ? 'পেআউট অনুরোধ পাঠানো হয়েছে' : 'Payout request sent', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating),
                            );
                          }
                        } catch (e) {
                          setS(() {
                            isSaving = false;
                            error = ApiClient.mapError(e).localized(_isBn);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(TextEditingController ctrl, String hint, IconData icon, [TextInputType? type]) {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: TextStyle(color: colors.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.outline),
        prefixIcon: Icon(icon, color: colors.outline, size: 18),
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
        title: Text(_isBn ? 'আমার ওয়ালেট' : 'My Wallet', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.primary,
          unselectedLabelColor: colors.outline,
          indicatorColor: colors.primary,
          tabs: [Tab(text: _isBn ? 'লেনদেন' : 'Transactions'), Tab(text: _isBn ? 'পেআউট' : 'Payouts')],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _providerId == null
              ? Center(child: Text(_isBn ? 'প্রোভাইডার একাউন্ট প্রয়োজন' : 'Provider account required', style: TextStyle(color: colors.outline)))
              : Column(
                  children: [
                    _buildBalanceCard(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTransactionList(),
                          _buildPayoutList(),
                        ],
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _providerId == null ? null : FloatingActionButton.extended(
        onPressed: _showPayoutSheet,
        backgroundColor: colors.primary,
        icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
        label: Text(_isBn ? 'উত্তোলন' : 'Withdraw', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildBalanceCard() {
    final colors = Theme.of(context).colorScheme;
    final balance = (_wallet?['balance'] ?? _wallet?['availableBalance'] ?? 0.0);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppGradients.primary(colors),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isBn ? 'উপলব্ধ ব্যালেন্স' : 'Available balance', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                '৳ ${balance.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.account_balance_wallet_rounded, color: Colors.white38, size: 48),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.2, end: 0);
  }

  Widget _buildTransactionList() {
    final colors = Theme.of(context).colorScheme;
    if (_transactions.isEmpty) {
      return Center(child: Text(_isBn ? 'কোনো লেনদেন নেই' : 'No transactions', style: TextStyle(color: colors.outline)));
    }
    return RefreshIndicator(
      color: colors.primary,
      backgroundColor: colors.surface,
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _transactions.length,
        itemBuilder: (ctx, i) {
          final t = _transactions[i] as TransactionModel;
          final isCredit = t.isCredit;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.description ?? (_isBn ? 'লেনদেন' : 'Transaction'), style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${t.createdAt.year}-${t.createdAt.month.toString().padLeft(2, '0')}-${t.createdAt.day.toString().padLeft(2, '0')}', style: TextStyle(color: colors.outline, fontSize: 11)),
                    ],
                  ),
                ),
                Text(
                  '${isCredit ? '+' : '-'}৳${t.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPayoutList() {
    final colors = Theme.of(context).colorScheme;
    if (_payouts.isEmpty) {
      return Center(child: Text(_isBn ? 'কোনো পেআউট নেই' : 'No payouts', style: TextStyle(color: colors.outline)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _payouts.length,
      itemBuilder: (ctx, i) {
        final p = _payouts[i] as Map<String, dynamic>;
        final status = p['status'] ?? 'pending';
        final statusColor = status == 'completed' ? const Color(0xFF10B981) : status == 'rejected' ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('৳${(double.tryParse('${p['amount'] ?? 0}') ?? 0).toStringAsFixed(0)}', style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      [p['payoutMethod'], p['payoutAccountInfo']].where((v) => v != null && v.toString().isNotEmpty).join(' · '),
                      style: TextStyle(color: colors.outline, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }
}
