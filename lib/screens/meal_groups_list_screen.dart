import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/meal_model.dart';
import '../services/meal_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'create_meal_group_screen.dart';
import 'join_meal_group_screen.dart';
import 'meal_group_detail_screen.dart';

class MealGroupsListScreen extends StatefulWidget {
  const MealGroupsListScreen({super.key});

  @override
  State<MealGroupsListScreen> createState() => _MealGroupsListScreenState();
}

class _MealGroupsListScreenState extends State<MealGroupsListScreen> {
  final _svc = MealService.instance;
  List<MealGroup> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final groups = await _svc.listMyGroups();
      if (mounted) setState(() { _groups = groups; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openGroup(MealGroup group) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MealGroupDetailScreen(group: group)),
    );
    if (changed == true) _load();
  }

  // The create/join API responses don't carry myRole (only listMyGroups does) — refetch
  // and use the annotated copy so the detail screen's manager-only UI is correct from
  // the very first open, instead of momentarily treating a fresh manager as a member.
  MealGroup _withRole(MealGroup fresh) {
    for (final g in _groups) {
      if (g.id == fresh.id) return g;
    }
    return fresh;
  }

  Future<void> _createGroup() async {
    final group = await Navigator.of(context).push<MealGroup>(
      MaterialPageRoute(builder: (_) => const CreateMealGroupScreen()),
    );
    if (group != null && mounted) {
      await _load();
      if (mounted) _openGroup(_withRole(group));
    }
  }

  Future<void> _joinGroup() async {
    final group = await Navigator.of(context).push<MealGroup>(
      MaterialPageRoute(builder: (_) => const JoinMealGroupScreen()),
    );
    if (group != null && mounted) {
      await _load();
      if (mounted) _openGroup(_withRole(group));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.deepBlue,
          backgroundColor: AppColors.bgMid,
          child: CustomScrollView(
            slivers: [
              _buildHeader(context),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: AppColors.deepBlue)),
                )
              else if (_groups.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
              else ...[
                SliverToBoxAdapter(child: _buildActionsRow()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: _groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _buildGroupCard(_groups[i], i),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 190,
      pinned: true,
      backgroundColor: AppColors.deepBlue,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ivory),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(gradient: AppColors.blueGradient),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -10,
                child: Icon(Icons.rice_bowl_rounded, size: 160, color: Colors.white.withOpacity(0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Text('🍛', style: TextStyle(fontSize: 30)),
                        const SizedBox(width: 8),
                        Text(
                          'মিল গ্রুপ',
                          style: const TextStyle(color: AppColors.ivory, fontSize: 26, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
                    const SizedBox(height: 6),
                    Text(
                      'বাসার সবার সাথে খাবার আর বাজারের হিসাব রাখুন',
                      style: TextStyle(color: AppColors.ivory.withOpacity(0.85), fontSize: 13),
                    ).animate(delay: 150.ms).fadeIn(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: GlassButton(
              label: 'নতুন গ্রুপ',
              icon: Icons.add_circle_outline_rounded,
              onPressed: _createGroup,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassButton(
              label: 'কোড দিয়ে যোগ দিন',
              icon: Icons.qr_code_2_rounded,
              isOutlined: true,
              onPressed: _joinGroup,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
  }

  Widget _buildGroupCard(MealGroup group, int index) {
    return GestureDetector(
      onTap: () => _openGroup(group),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.fuchsiaGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: AppColors.fuchsia.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (group.isManager) ...[
                        const Icon(Icons.workspace_premium_rounded, size: 14, color: AppColors.softAmber),
                        const SizedBox(width: 4),
                        const Text('ম্যানেজার', style: TextStyle(color: AppColors.softAmber, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                      ],
                      Text('কোড: ${group.inviteCode}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.deepBlue, size: 16),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.08);
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏠', style: TextStyle(fontSize: 72))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.08, duration: 1200.ms, curve: Curves.easeInOut),
          const SizedBox(height: 20),
          const Text(
            'এখনো কোনো মিল গ্রুপ নেই',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'নতুন গ্রুপ তৈরি করে বাসার সবাইকে যোগ করুন, অথবা কারো দেওয়া কোড দিয়ে যোগ দিন — প্রতিদিনের খাবার আর বাজারের হিসাব থাকবে সবার হাতের কাছে।',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 28),
          GlassButton(label: 'নতুন গ্রুপ তৈরি করুন', icon: Icons.add_circle_outline_rounded, onPressed: _createGroup),
          const SizedBox(height: 12),
          GlassButton(label: 'কোড দিয়ে যোগ দিন', icon: Icons.qr_code_2_rounded, isOutlined: true, onPressed: _joinGroup),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}
