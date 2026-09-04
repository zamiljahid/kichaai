import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../core/network/api_client.dart';
import '../models/meal_model.dart';
import '../services/meal_service.dart';
import '../theme/app_gradients.dart';
import '../theme/status_colors.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'meal_monthly_summary_screen.dart';

class MealGroupDetailScreen extends StatefulWidget {
  final MealGroup group;
  const MealGroupDetailScreen({super.key, required this.group});

  @override
  State<MealGroupDetailScreen> createState() => _MealGroupDetailScreenState();
}

class _MealGroupDetailScreenState extends State<MealGroupDetailScreen> {
  final _svc = MealService.instance;
  List<MealGroupMember> _members = [];
  // Today's entry per member, keyed by userId — populated for everyone in the group (not
  // just the caller) so the manager's roster below can show each person's status too.
  Map<String, DailyMealEntry> _todayByUser = {};
  MonthlySummary? _summary;
  bool _isLoading = true;
  String? _userId;

  DateTime get _today => DateTime.now();
  bool get _isManager => widget.group.isManager;
  DailyMealEntry? get _todayEntry => _userId == null ? null : _todayByUser[_userId];
  MemberBalance? get _myBalance {
    final members = _summary?.members;
    if (members == null || _userId == null) return null;
    for (final m in members) {
      if (m.userId == _userId) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _currentMonthKey => '${_today.year}-${_today.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _userId = await ApiClient.getUserId();
    try {
      final results = await Future.wait([
        _svc.listMembers(widget.group.id),
        _svc.listMealEntries(groupId: widget.group.id, month: _currentMonthKey),
        _svc.getMonthlySummary(groupId: widget.group.id, month: _currentMonthKey),
      ]);
      final members = results[0] as List<MealGroupMember>;
      final entries = results[1] as List<DailyMealEntry>;
      final summary = results[2] as MonthlySummary;
      final todayByUser = <String, DailyMealEntry>{};
      for (final e in entries) {
        if (e.date.year == _today.year && e.date.month == _today.month && e.date.day == _today.day) {
          todayByUser[e.userId] = e;
        }
      }
      if (mounted) {
        setState(() {
          _members = members;
          _todayByUser = todayByUser;
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMeal({required String mealType, String? targetUserId}) async {
    final colors = Theme.of(context).colorScheme;
    final uid = targetUserId ?? _userId;
    if (uid == null) return;
    final current = _todayByUser[uid];
    var newBreakfast = current?.ateBreakfast ?? false;
    var newLunch = current?.ateLunch ?? false;
    var newDinner = current?.ateDinner ?? false;
    switch (mealType) {
      case 'breakfast':
        newBreakfast = !newBreakfast;
      case 'lunch':
        newLunch = !newLunch;
      case 'dinner':
        newDinner = !newDinner;
    }

    // Optimistic — the daily toggle is the whole point of this screen, it must feel instant.
    setState(() {
      _todayByUser = {
        ..._todayByUser,
        uid: DailyMealEntry(
          id: current?.id ?? '',
          groupId: widget.group.id,
          userId: uid,
          date: _today,
          ateBreakfast: newBreakfast,
          ateLunch: newLunch,
          ateDinner: newDinner,
        ),
      };
    });
    HapticFeedback.lightImpact();
    try {
      final entry = await _svc.logDailyMeal(
        groupId: widget.group.id,
        date: _today,
        ateBreakfast: newBreakfast,
        ateLunch: newLunch,
        ateDinner: newDinner,
        targetUserId: targetUserId,
      );
      if (mounted) setState(() => _todayByUser = {..._todayByUser, uid: entry});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: colors.error,
        ));
        _load();
      }
    }
  }

  void _shareInvite() {
    final text =
        'আমার সাথে "${widget.group.name}" মিল গ্রুপে যোগ দাও!\n\n'
        'কোড: ${widget.group.inviteCode}\n\n'
        'কিচাই অ্যাপ খুলে "মিল গ্রুপ" → "কোড দিয়ে যোগ দিন" এ গিয়ে কোডটি লিখো।\n'
        'https://kichaai.com/meal/join/${widget.group.inviteCode}';
    Share.share(text, subject: '${widget.group.name} — মিল গ্রুপ ইনভাইট');
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('কোড কপি হয়েছে'),
      backgroundColor: StatusColors.blue,
    ));
  }

  Future<void> _confirmLeave() async {
    final colors = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('গ্রুপ ছেড়ে যাবেন?', style: TextStyle(color: colors.onSurface)),
        content: Text(
          'আপনার আগের মিল ও খরচের হিসাব থেকে যাবে, কিন্তু আপনি আর নতুন হিসাব যোগ করতে পারবেন না।',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ছেড়ে যান', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _svc.leaveGroup(widget.group.id);
        if (mounted) Navigator.of(context).pop(true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: colors.error));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        backgroundColor: colors.surfaceContainerHighest,
        appBar: AppBar(
          title: Text(widget.group.name, overflow: TextOverflow.ellipsis),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'leave') _confirmLeave();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'leave', child: Text('গ্রুপ ছেড়ে যান')),
              ],
            ),
          ],
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.background(colors)),
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: colors.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: colors.primary,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildInviteCard(),
                      const SizedBox(height: 16),
                      _buildQuickStatsCard(),
                      const SizedBox(height: 16),
                      _buildTodayCard(),
                      if (_isManager) ...[
                        const SizedBox(height: 16),
                        _buildRosterCard(),
                      ],
                      const SizedBox(height: 16),
                      _buildSummaryLink(),
                      const SizedBox(height: 16),
                      _buildMembersCard(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildInviteCard() {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      glassColor: colors.primary.withValues(alpha: 0.08),
      borderColor: colors.primary.withValues(alpha: 0.20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ইনভাইট কোড', style: TextStyle(color: colors.outline, fontSize: 12)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _copyCode,
                  child: Row(
                    children: [
                      Text(
                        widget.group.inviteCode,
                        style: TextStyle(color: colors.primary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.copy_rounded, size: 16, color: colors.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GlassButton(label: 'ইনভাইট করুন', icon: Icons.share_rounded, width: 150, onPressed: _shareInvite),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08);
  }

  // Mirrors the Deposit / Balance / Cost-per-meal row bachelors' mess-tracking apps put
  // front-and-center — the whole point of this feature is knowing where you stand without
  // digging into the monthly summary screen.
  Widget _buildQuickStatsCard() {
    final colors = Theme.of(context).colorScheme;
    final my = _myBalance;
    final positive = (my?.balance ?? 0) >= 0;
    final balanceColor = positive ? const Color(0xFF15803D) : colors.error;
    return GlassCard(
      glassColor: colors.primary.withValues(alpha: 0.08),
      borderColor: colors.primary.withValues(alpha: 0.20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _quickStat('আমার জমা', '৳${(my?.deposited ?? 0).toStringAsFixed(0)}', Icons.savings_rounded),
              _quickStatDivider(),
              _quickStat('আমার ব্যালেন্স', '৳${(my?.balance ?? 0).toStringAsFixed(0)}', Icons.account_balance_wallet_rounded, valueColor: balanceColor),
              _quickStatDivider(),
              _quickStat('প্রতি মিল খরচ', '৳${(_summary?.perMealRate ?? 0).toStringAsFixed(1)}', Icons.calculate_rounded),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GlassButton(label: 'জমা দিন', icon: Icons.add_card_rounded, isOutlined: true, onPressed: () => _showAddDepositSheet()),
          ),
        ],
      ),
    ).animate(delay: 60.ms).fadeIn().slideY(begin: 0.08);
  }

  Widget _quickStatDivider() {
    final colors = Theme.of(context).colorScheme;
    return Container(width: 1, height: 36, color: colors.outlineVariant);
  }

  Widget _quickStat(String label, String value, IconData icon, {Color? valueColor}) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: colors.primary, size: 18),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: valueColor ?? colors.onSurface, fontSize: 15, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: colors.outline, fontSize: 10), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _showAddDepositSheet({String? targetUserId, String? targetLabel}) async {
    final colors = Theme.of(context).colorScheme;
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
              color: colors.surface,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(
                    targetLabel != null ? '$targetLabel-এর বাজার ফান্ডে জমা' : 'বাজার ফান্ডে জমা দিন',
                    style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('এটা কোনো কেনাকাটা না — শুধু বাজারের জন্য আগাম টাকা জমা দেওয়া হচ্ছে', style: TextStyle(color: colors.outline, fontSize: 11)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: colors.onSurface),
                    decoration: const InputDecoration(hintText: 'টাকার পরিমাণ', prefixText: '৳ '),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    style: TextStyle(color: colors.onSurface),
                    decoration: const InputDecoration(hintText: 'নোট (ঐচ্ছিক)'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: colors.error, fontSize: 12)),
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
                          targetUserId: targetUserId,
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

  Widget _buildTodayCard() {
    final colors = Theme.of(context).colorScheme;
    final breakfast = _todayEntry?.ateBreakfast ?? false;
    final lunch = _todayEntry?.ateLunch ?? false;
    final dinner = _todayEntry?.ateDinner ?? false;
    final weekday = const ['সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি', 'রবি'][_today.weekday - 1];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('আজকের খাবার', style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$weekday, ${_today.day}/${_today.month}', style: TextStyle(color: colors.outline, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildMealToggle(label: 'সকাল', emoji: '🍳', active: breakfast, onTap: () => _toggleMeal(mealType: 'breakfast'))),
              const SizedBox(width: 10),
              Expanded(child: _buildMealToggle(label: 'লাঞ্চ', emoji: '🍚', active: lunch, onTap: () => _toggleMeal(mealType: 'lunch'))),
              const SizedBox(width: 10),
              Expanded(child: _buildMealToggle(label: 'ডিনার', emoji: '🍛', active: dinner, onTap: () => _toggleMeal(mealType: 'dinner'))),
            ],
          ),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.08);
  }

  Widget _buildMealToggle({required String label, required String emoji, required bool active, required VoidCallback onTap}) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: active ? AppGradients.primary(colors) : null,
          color: active ? null : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Colors.transparent : colors.outlineVariant, width: 1.5),
          boxShadow: active ? [BoxShadow(color: colors.primary.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))] : null,
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: active ? colors.onPrimary : colors.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Icon(
              active ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: active ? colors.onPrimary : colors.outline,
              size: 15,
            ),
          ],
        ),
      ).animate(target: active ? 1 : 0).scaleXY(begin: 1, end: 1.03, curve: Curves.easeOutBack, duration: 200.ms),
    );
  }

  // Manager-only: a compact roster so one person can keep the whole mess's meal register
  // up to date (matches the real paper "মিল খাতা" habit) instead of every member having to
  // separately open the app and self-report. Excludes the caller — their own big toggle
  // tiles above already cover that.
  Widget _buildRosterCard() {
    final colors = Theme.of(context).colorScheme;
    final others = _members.where((m) => m.userId != _userId).toList();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, size: 16, color: StatusColors.amber),
              SizedBox(width: 6),
              Text('অন্য সদস্যদের জন্য এন্ট্রি দিন', style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text('ম্যানেজার হিসেবে আপনি বাসার সবার হয়ে আজকের খাবার টিক দিতে পারবেন। কারো নাম চেপে ধরলে তার বাজার ফান্ডে জমা যোগ করতে পারবেন।', style: TextStyle(color: colors.outline, fontSize: 11)),
          const SizedBox(height: 14),
          if (others.isEmpty)
            Text('গ্রুপে আর কোনো সদস্য নেই', style: TextStyle(color: colors.outline, fontSize: 13))
          else
            ...others.asMap().entries.map((entry) => _buildRosterRow(entry.value, entry.key)),
        ],
      ),
    ).animate(delay: 120.ms).fadeIn().slideY(begin: 0.08);
  }

  Widget _buildRosterRow(MealGroupMember member, int index) {
    final colors = Theme.of(context).colorScheme;
    final entry = _todayByUser[member.userId];
    final breakfast = entry?.ateBreakfast ?? false;
    final lunch = entry?.ateLunch ?? false;
    final dinner = entry?.ateDinner ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          GestureDetector(
            onLongPress: () => _showAddDepositSheet(targetUserId: member.userId, targetLabel: member.displayName),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: colors.primary,
                  child: Text(member.displayName.isNotEmpty ? member.displayName[0].toUpperCase() : '?', style: TextStyle(color: colors.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
          Expanded(child: Text(member.displayName, style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600))),
          _buildRosterChip(emoji: '🍳', active: breakfast, onTap: () => _toggleMeal(mealType: 'breakfast', targetUserId: member.userId)),
          const SizedBox(width: 6),
          _buildRosterChip(emoji: '🍚', active: lunch, onTap: () => _toggleMeal(mealType: 'lunch', targetUserId: member.userId)),
          const SizedBox(width: 6),
          _buildRosterChip(emoji: '🍛', active: dinner, onTap: () => _toggleMeal(mealType: 'dinner', targetUserId: member.userId)),
        ],
      ),
    ).animate(delay: Duration(milliseconds: 50 * index)).fadeIn().slideX(begin: 0.05);
  }

  Widget _buildRosterChip({required String emoji, required bool active, required VoidCallback onTap}) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 34,
        height: 32,
        decoration: BoxDecoration(
          gradient: active ? AppGradients.primary(colors) : null,
          color: active ? null : colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? Colors.transparent : colors.outlineVariant),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 16)),
      ).animate(target: active ? 1 : 0).scaleXY(begin: 1, end: 1.08, curve: Curves.easeOutBack, duration: 180.ms),
    );
  }

  Widget _buildSummaryLink() {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MealMonthlySummaryScreen(group: widget.group)),
      ),
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: AppGradients.accent(colors), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.receipt_long_rounded, color: colors.onPrimary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('মাসিক হিসাব ও বাজার খরচ', style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('কে কত মিল খেলো, কে কত টাকা পাবে/দেবে', style: TextStyle(color: colors.outline, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: colors.primary, size: 16),
          ],
        ),
      ),
    ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.08);
  }

  Widget _buildMembersCard() {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('সদস্য (${_members.length})', style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ..._members.asMap().entries.map((entry) {
            final m = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.primary,
                    child: Text(
                      m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
                      style: TextStyle(color: colors.onPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(m.displayName, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600))),
                  if (m.isManager)
                    const Icon(Icons.workspace_premium_rounded, size: 16, color: StatusColors.amber),
                ],
              ),
            ).animate(delay: Duration(milliseconds: 50 * entry.key)).fadeIn().slideX(begin: 0.05);
          }),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.08);
  }
}
