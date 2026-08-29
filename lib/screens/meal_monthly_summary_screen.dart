import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/meal_model.dart';
import '../services/meal_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

const _kBnMonths = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
];

class MealMonthlySummaryScreen extends StatefulWidget {
  final MealGroup group;
  const MealMonthlySummaryScreen({super.key, required this.group});

  @override
  State<MealMonthlySummaryScreen> createState() => _MealMonthlySummaryScreenState();
}

class _MealMonthlySummaryScreenState extends State<MealMonthlySummaryScreen> {
  final _svc = MealService.instance;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  MonthlySummary? _summary;
  List<GroceryExpense> _expenses = [];
  List<MealDeposit> _deposits = [];
  bool _isLoading = true;

  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _svc.getMonthlySummary(groupId: widget.group.id, month: _monthKey),
        _svc.listGroceryExpenses(groupId: widget.group.id, month: _monthKey),
        _svc.listDeposits(groupId: widget.group.id, month: _monthKey),
      ]);
      if (mounted) {
        setState(() {
          _summary = results[0] as MonthlySummary;
          _expenses = results[1] as List<GroceryExpense>;
          _deposits = results[2] as List<MealDeposit>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _showAddExpenseSheet() async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isSubmitting = false;
    String? error;

    await showModalBottomSheet(
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
                color: AppColors.bgMid,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    const Text('বাজার খরচ যোগ করুন', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: 'টাকার পরিমাণ', prefixText: '৳ '),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: 'কী কিনেছেন? (যেমন: চাল, ডাল, সবজি)'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: AppColors.softRed, fontSize: 12)),
                    ],
                    const SizedBox(height: 20),
                    GlassButton(
                      label: 'যোগ করুন',
                      icon: Icons.add_shopping_cart_rounded,
                      isLoading: isSubmitting,
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text.trim());
                        if (amount == null || amount <= 0) {
                          setS(() => error = 'সঠিক পরিমাণ দিন');
                          return;
                        }
                        setS(() { isSubmitting = true; error = null; });
                        try {
                          await _svc.addGroceryExpense(
                            groupId: widget.group.id,
                            amount: amount,
                            description: descCtrl.text.trim(),
                            date: DateTime.now(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setS(() { isSubmitting = false; error = e.toString(); });
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
    _load();
  }

  Future<void> _showAddDepositSheet() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool isSubmitting = false;
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              color: AppColors.bgMid,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  const Text('বাজার ফান্ডে জমা দিন', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('এটা কোনো কেনাকাটা না — শুধু বাজারের জন্য আগাম টাকা জমা দেওয়া হচ্ছে', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(hintText: 'টাকার পরিমাণ', prefixText: '৳ '),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(hintText: 'নোট (ঐচ্ছিক)'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: AppColors.softRed, fontSize: 12)),
                  ],
                  const SizedBox(height: 20),
                  GlassButton(
                    label: 'জমা দিন',
                    icon: Icons.add_card_rounded,
                    isLoading: isSubmitting,
                    onPressed: () async {
                      final amount = double.tryParse(amountCtrl.text.trim());
                      if (amount == null || amount <= 0) {
                        setS(() => error = 'সঠিক পরিমাণ দিন');
                        return;
                      }
                      setS(() { isSubmitting = true; error = null; });
                      try {
                        await _svc.addDeposit(
                          groupId: widget.group.id,
                          amount: amount,
                          note: noteCtrl.text.trim(),
                          date: DateTime.now(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setS(() { isSubmitting = false; error = e.toString(); });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('মাসিক হিসাব')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'addDeposit',
            onPressed: _showAddDepositSheet,
            backgroundColor: AppColors.softAmber,
            icon: const Icon(Icons.add_card_rounded, color: AppColors.ivory),
            label: const Text('জমা দিন', style: TextStyle(color: AppColors.ivory)),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addExpense',
            onPressed: _showAddExpenseSheet,
            backgroundColor: AppColors.deepBlue,
            icon: const Icon(Icons.add_shopping_cart_rounded, color: AppColors.ivory),
            label: const Text('খরচ যোগ করুন', style: TextStyle(color: AppColors.ivory)),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.deepBlue,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    _buildMonthSelector(),
                    const SizedBox(height: 16),
                    _buildOverviewCard(),
                    const SizedBox(height: 16),
                    _buildBalancesCard(),
                    const SizedBox(height: 16),
                    _buildExpensesCard(),
                    const SizedBox(height: 16),
                    _buildDepositsCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left_rounded, color: AppColors.deepBlue), onPressed: () => _changeMonth(-1)),
        Text(
          '${_kBnMonths[_month.month - 1]} ${_month.year}',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        IconButton(icon: const Icon(Icons.chevron_right_rounded, color: AppColors.deepBlue), onPressed: () => _changeMonth(1)),
      ],
    );
  }

  Widget _buildOverviewCard() {
    final s = _summary;
    return GlassCard(
      glassColor: AppColors.glassBlue,
      borderColor: AppColors.glassBorderBlue,
      child: Column(
        children: [
          Row(
            children: [
              _overviewStat('মোট মিল', '${s?.totalMeals ?? 0}', Icons.restaurant_rounded),
              _divider(),
              _overviewStat('মোট বাজার খরচ', '৳${(s?.totalSpend ?? 0).toStringAsFixed(0)}', Icons.shopping_basket_rounded),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _overviewStat('মোট জমা', '৳${(s?.totalDeposits ?? 0).toStringAsFixed(0)}', Icons.savings_rounded),
              _divider(),
              _overviewStat('প্রতি মিল খরচ', '৳${(s?.perMealRate ?? 0).toStringAsFixed(1)}', Icons.calculate_rounded),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08);
  }

  Widget _divider() => Container(width: 1, height: 40, color: AppColors.glassBorder);

  Widget _overviewStat(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.deepBlue, size: 20),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildBalancesCard() {
    final members = _summary?.members ?? [];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('সদস্যদের হিসাব', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('সবুজ মানে টাকা ফেরত পাবে, লাল মানে গ্রুপকে টাকা দিতে হবে', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 14),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('এই মাসে এখনো কোনো হিসাব নেই', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            ...members.asMap().entries.map((entry) => _buildBalanceRow(entry.value, entry.key)),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.08);
  }

  Widget _buildBalanceRow(MemberBalance m, int index) {
    final positive = m.balance >= 0;
    final color = positive ? const Color(0xFF15803D) : AppColors.softRed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: AppColors.deepBlue, child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.ivory, fontSize: 13, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  m.deposited > 0
                      ? '${m.mealCount} মিল · মোট ৳${m.paid.toStringAsFixed(0)} (জমা ৳${m.deposited.toStringAsFixed(0)})'
                      : '${m.mealCount} মিল · মোট ৳${m.paid.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(
              '${positive ? '+' : ''}৳${m.balance.toStringAsFixed(0)}',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: 60 * index)).fadeIn().slideX(begin: 0.05);
  }

  Widget _buildExpensesCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('বাজার খরচের তালিকা', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_expenses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('এই মাসে এখনো কোনো বাজার খরচ যোগ হয়নি', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            ..._expenses.map((ex) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_basket_rounded, color: AppColors.softAmber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ex.description?.isNotEmpty == true ? ex.description! : 'বাজার খরচ', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('${ex.date.day}/${ex.date.month}/${ex.date.year}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text('৳${ex.amount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                )),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.08);
  }

  String _nameForUser(String userId) {
    for (final m in _summary?.members ?? const <MemberBalance>[]) {
      if (m.userId == userId) return m.name;
    }
    return 'সদস্য';
  }

  Widget _buildDepositsCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('বাজার ফান্ডে জমার তালিকা', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_deposits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('এই মাসে এখনো কোনো জমা যোগ হয়নি', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            ..._deposits.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.savings_rounded, color: AppColors.softAmber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_nameForUser(d.userId), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(
                              '${d.date.day}/${d.date.month}/${d.date.year}${d.note?.isNotEmpty == true ? ' · ${d.note}' : ''}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text('৳${d.amount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                )),
        ],
      ),
    ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.08);
  }
}
