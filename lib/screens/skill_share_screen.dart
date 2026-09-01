import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/skill_share_service.dart';
import '../widgets/glass_button.dart';
import 'exchange_detail_screen.dart';
import 'payment_waiting_screen.dart';

const _kCategories = ['technology', 'language', 'art', 'music', 'sports', 'cooking', 'business'];
const _kLevels = ['beginner', 'intermediate', 'advanced', 'expert'];

class SkillShareScreen extends StatefulWidget {
  const SkillShareScreen({super.key});

  @override
  State<SkillShareScreen> createState() => _SkillShareScreenState();
}

class _SkillShareScreenState extends State<SkillShareScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _svc = SkillShareService.instance;
  String? _userId;

  List<Map<String, dynamic>> _mySkills = [];
  List<Map<String, dynamic>> _openExchanges = [];
  List<Map<String, dynamic>> _myExchanges = [];
  bool _isLoading = true;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await Future.wait([_loadMySkills(), _loadOpenExchanges(), _loadMyExchanges()]);
  }

  Future<void> _loadMySkills() async {
    if (_userId == null) return;
    try {
      final list = await _svc.listUserSkills(_userId!);
      if (mounted) setState(() { _mySkills = list; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOpenExchanges() async {
    try {
      final list = await _svc.listOpenExchanges();
      // Someone shouldn't see (and respond to) their own open post in the discovery feed.
      if (mounted) setState(() => _openExchanges = list.where((e) => e['requesterId'] != _userId).toList());
    } catch (_) {}
  }

  Future<void> _loadMyExchanges() async {
    try {
      final list = await _svc.listMyExchanges();
      if (mounted) setState(() => _myExchanges = list);
    } catch (_) {}
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF10B981), behavior: SnackBarBehavior.floating,
    ));
  }

  void _showAddSkillSheet() {
    final colors = Theme.of(context).colorScheme;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'technology';
    String level = 'beginner';

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
                    Text(_isBn ? 'নতুন দক্ষতা যোগ করুন' : 'Add a New Skill', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _sheetField(nameCtrl, _isBn ? 'দক্ষতার নাম' : 'Skill name', Icons.star_outline_rounded),
                    const SizedBox(height: 12),
                    _sheetField(descCtrl, _isBn ? 'বিবরণ' : 'Description', Icons.description_outlined, maxLines: 3),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      dropdownColor: colors.surface,
                      style: TextStyle(color: colors.onSurface),
                      decoration: _inputDeco(_isBn ? 'বিভাগ' : 'Category'),
                      items: _kCategories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setS(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: level,
                      dropdownColor: colors.surface,
                      style: TextStyle(color: colors.onSurface),
                      decoration: _inputDeco(_isBn ? 'স্তর' : 'Level'),
                      items: _kLevels.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setS(() => level = v ?? level),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: _isBn ? 'যোগ করুন' : 'Add',
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        try {
                          await _svc.addSkill(
                            skillName: nameCtrl.text.trim(),
                            description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                            category: category,
                            level: level,
                          );
                          if (ctx.mounted) { Navigator.pop(ctx); _loadMySkills(); }
                        } catch (e) {
                          if (ctx.mounted) _showError(ApiClient.mapError(e).localized(_isBn));
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

  InputDecoration _inputDeco(String hint) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: colors.outline),
    filled: true,
    fillColor: colors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );
  }

  Widget _sheetField(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1}) {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: colors.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.outline),
        prefixIcon: maxLines == 1 ? Icon(icon, color: colors.outline, size: 18) : null,
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'expert': return const Color(0xFFF59E0B);
      case 'intermediate': return const Color(0xFF3B82F6);
      default: return const Color(0xFF10B981);
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
        title: Text(_isBn ? 'স্কিল শেয়ার' : 'Skill Share', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.primary,
          unselectedLabelColor: colors.outline,
          indicatorColor: colors.primary,
          tabs: [
            Tab(text: _isBn ? 'খুঁজুন' : 'Discover'),
            Tab(text: _isBn ? 'আমার দক্ষতা' : 'My Skills'),
            Tab(text: _isBn ? 'অনুরোধ' : 'Requests'),
            Tab(text: _isBn ? 'এক্সচেঞ্জ' : 'Exchanges'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDiscoverTab(),
                _buildMySkillsTab(),
                _buildRequestsTab(),
                _buildExchangesTab(),
              ],
            ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) => FloatingActionButton(
          onPressed: _tabController.index == 2 ? _showPostRequestSheet : _showAddSkillSheet,
          backgroundColor: colors.primary,
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    );
  }

  // ── Discover ──────────────────────────────────────────────────────
  // Finding someone else's skill is the whole point of a skill exchange, but the screen
  // only ever listed your own skills and your own exchanges — GET /skill-share/skills/search
  // had no caller anywhere in the app.
  final _discoverCtrl = TextEditingController();
  List<Map<String, dynamic>> _discovered = [];
  bool _discovering = false;
  bool _discoverRan = false;

  Future<void> _runDiscover() async {
    final q = _discoverCtrl.text.trim();
    setState(() => _discovering = true);
    try {
      final rows = await SkillShareService.instance
          .searchSkills(skillName: q.isEmpty ? null : q);
      if (mounted) setState(() => _discovered = rows);
    } catch (_) {
      if (mounted) setState(() => _discovered = []);
    } finally {
      if (mounted) {
        setState(() {
          _discovering = false;
          _discoverRan = true;
        });
      }
    }
  }

  Widget _buildDiscoverTab() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discoverCtrl,
                  onSubmitted: (_) => _runDiscover(),
                  style: TextStyle(color: colors.onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _isBn
                        ? 'দক্ষতা খুঁজুন (যেমন: গিটার, ইংরেজি)'
                        : 'Search a skill (e.g. guitar, English)',
                    hintStyle: TextStyle(color: colors.outline, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: colors.outline, size: 20),
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _discovering ? null : _runDiscover,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _discovering
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _discovered.isEmpty
              ? Center(
                  child: Text(
                    _discoverRan
                        ? (_isBn ? 'কিছু পাওয়া যায়নি' : 'Nothing found')
                        : (_isBn
                            ? 'অন্যদের দক্ষতা খুঁজতে সার্চ করুন'
                            : "Search to find other people's skills"),
                    style: TextStyle(color: colors.outline, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: _discovered.length,
                  itemBuilder: (_, i) {
                    final r = _discovered[i];
                    final name = (r['skillName'] ?? '').toString();
                    final cat = (r['category'] ?? '').toString();
                    final level = (r['level'] ?? '').toString();
                    final desc = (r['description'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(name,
                                    style: TextStyle(
                                        color: colors.onSurface,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ),
                              if (level.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: colors.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: colors.outlineVariant),
                                  ),
                                  child: Text(level,
                                      style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                          if (cat.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(cat,
                                style: TextStyle(
                                    color: colors.primary, fontSize: 11.5)),
                          ],
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(desc,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: colors.onSurfaceVariant, fontSize: 12)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMySkillsTab() {
    final colors = Theme.of(context).colorScheme;
    if (_mySkills.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.auto_awesome_rounded, color: colors.outline, size: 56),
          const SizedBox(height: 12),
          Text(_isBn ? 'কোনো দক্ষতা নেই' : 'No skills yet', style: TextStyle(color: colors.outline)),
          const SizedBox(height: 8),
          TextButton(onPressed: _showAddSkillSheet, child: Text(_isBn ? 'যোগ করুন' : 'Add', style: TextStyle(color: colors.primary))),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _mySkills.length,
      itemBuilder: (ctx, i) {
        final s = _mySkills[i];
        final level = s['level'] as String? ?? 'beginner';
        return GestureDetector(
          onTap: () => _showEditSkillSheet(s),
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
              decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.auto_awesome_rounded, color: colors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['skillName'] as String? ?? '', style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(s['category'] as String? ?? '', style: TextStyle(color: colors.outline, fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _levelColor(level).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(level, style: TextStyle(color: _levelColor(level), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
      },
    );
  }

  /// Tap a skill card → edit it (PATCH /skill-share/skills/:id, only the
  /// fields that changed).
  void _showEditSkillSheet(Map<String, dynamic> s) {
    final colors = Theme.of(context).colorScheme;
    final skillId = s['id'] as String? ?? '';
    if (skillId.isEmpty) return;
    final nameCtrl = TextEditingController(text: s['skillName'] as String? ?? '');
    final descCtrl = TextEditingController(text: s['description'] as String? ?? '');
    String category = _kCategories.contains(s['category']) ? s['category'] as String : 'technology';
    String level = _kLevels.contains(s['level']) ? s['level'] as String : 'beginner';
    bool saving = false;

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
                    Text(_isBn ? 'দক্ষতা সম্পাদনা করুন' : 'Edit Skill', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _sheetField(nameCtrl, _isBn ? 'দক্ষতার নাম' : 'Skill name', Icons.star_outline_rounded),
                    const SizedBox(height: 12),
                    _sheetField(descCtrl, _isBn ? 'বিবরণ' : 'Description', Icons.description_outlined, maxLines: 3),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      dropdownColor: colors.surface,
                      style: TextStyle(color: colors.onSurface),
                      decoration: _inputDeco(_isBn ? 'বিভাগ' : 'Category'),
                      items: _kCategories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setS(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: level,
                      dropdownColor: colors.surface,
                      style: TextStyle(color: colors.onSurface),
                      decoration: _inputDeco(_isBn ? 'স্তর' : 'Level'),
                      items: _kLevels.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setS(() => level = v ?? level),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: _isBn ? 'সংরক্ষণ করুন' : 'Save',
                      isLoading: saving,
                      onPressed: saving ? null : () async {
                        final changes = <String, dynamic>{
                          if (nameCtrl.text.trim() != (s['skillName'] ?? '')) 'skillName': nameCtrl.text.trim(),
                          if (descCtrl.text.trim() != (s['description'] ?? '')) 'description': descCtrl.text.trim(),
                          if (category != s['category']) 'category': category,
                          if (level != s['level']) 'level': level,
                        };
                        if (changes.isEmpty) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          return;
                        }
                        setS(() => saving = true);
                        try {
                          await _svc.updateSkill(skillId, changes);
                          if (ctx.mounted) { Navigator.pop(ctx); _loadMySkills(); }
                        } catch (e) {
                          setS(() => saving = false);
                          if (ctx.mounted) _showError(ApiClient.mapError(e).localized(_isBn));
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

  // ── "অনুরোধ" tab: browse everyone's open (unclaimed) exchange posts;
  // FAB posts a new one. Previously this tab was a "search a specific person
  // & propose directly to them" flow that didn't match how the backend
  // actually models a proposal (an open post, not person-targeted) — every
  // proposal sent through the old flow failed backend validation outright.

  Widget _buildRequestsTab() {
    final colors = Theme.of(context).colorScheme;
    if (_openExchanges.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.campaign_outlined, color: colors.outline, size: 56),
          const SizedBox(height: 12),
          Text(_isBn ? 'এই মুহূর্তে কোনো খোলা অনুরোধ নেই' : 'No open requests right now', style: TextStyle(color: colors.outline)),
          const SizedBox(height: 8),
          TextButton(onPressed: _showPostRequestSheet, child: Text(_isBn ? 'একটি পোস্ট করুন' : 'Post one', style: TextStyle(color: colors.primary))),
        ]),
      );
    }
    return RefreshIndicator(
      color: colors.primary,
      backgroundColor: colors.surface,
      onRefresh: _loadOpenExchanges,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _openExchanges.length,
        itemBuilder: (ctx, i) {
          final e = _openExchanges[i];
          final offered = e['offeredSkill'] as Map<String, dynamic>?;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.auto_awesome_rounded, color: colors.primary, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_isBn ? 'দিচ্ছেন: ${offered?['skillName'] ?? '—'}' : 'Offering: ${offered?['skillName'] ?? '—'}', style: TextStyle(color: colors.onSurface, fontSize: 13.5, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.swap_horiz_rounded, color: colors.outline, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_isBn ? 'চাচ্ছেন: ${e['wantedSkillName'] ?? '—'} (${e['wantedSkillCategory'] ?? ''})' : 'Wants: ${e['wantedSkillName'] ?? '—'} (${e['wantedSkillCategory'] ?? ''})', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13))),
              ]),
              if ((e['message'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Text(e['message'] as String, style: TextStyle(color: colors.outline, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.repeat_rounded, color: colors.outline, size: 13),
                const SizedBox(width: 4),
                Text(_isBn ? '${e['agreedSessionCount'] ?? 1} সেশন' : '${e['agreedSessionCount'] ?? 1} sessions', style: TextStyle(color: colors.outline, fontSize: 11)),
                const Spacer(),
                TextButton(
                  onPressed: () => _showRespondSheet(e),
                  child: Text(_isBn ? 'রেসপন্স দিন' : 'Respond', style: TextStyle(color: colors.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
        },
      ),
    );
  }

  void _showPostRequestSheet() {
    final colors = Theme.of(context).colorScheme;
    if (_mySkills.isEmpty) {
      _showError(_isBn ? 'প্রথমে "আমার দক্ষতা" ট্যাবে অন্তত একটি দক্ষতা যোগ করুন' : 'First add at least one skill in the "My Skills" tab');
      return;
    }
    String? offeredSkillId = _mySkills.first['id'] as String?;
    final wantedNameCtrl = TextEditingController();
    String wantedCategory = 'technology';
    int sessions = 3;
    final msgCtrl = TextEditingController();
    bool submitting = false;

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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 16),
                      Text(_isBn ? 'অনুরোধ পোস্ট করুন' : 'Post a Request', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(_isBn ? 'যে কেউ এটা দেখে সাড়া দিতে পারবে' : 'Anyone who sees this can respond', style: TextStyle(color: colors.outline, fontSize: 12)),
                      const SizedBox(height: 16),
                      Text(_isBn ? 'আপনি কী দিচ্ছেন:' : 'What you\'re offering:', style: TextStyle(color: colors.outline, fontSize: 12)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: offeredSkillId,
                        dropdownColor: colors.surface,
                        style: TextStyle(color: colors.onSurface),
                        decoration: _inputDeco(_isBn ? 'আমার দক্ষতা' : 'My skill'),
                        items: _mySkills.map((s) => DropdownMenuItem<String>(value: s['id'] as String?, child: Text(s['skillName'] as String? ?? ''))).toList(),
                        onChanged: (v) => setS(() => offeredSkillId = v),
                      ),
                      const SizedBox(height: 14),
                      Text(_isBn ? 'আপনি কী চান:' : 'What you want:', style: TextStyle(color: colors.outline, fontSize: 12)),
                      const SizedBox(height: 8),
                      _sheetField(wantedNameCtrl, _isBn ? 'যেমন: React ডেভেলপমেন্ট' : 'e.g. React development', Icons.search_rounded),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: wantedCategory,
                        dropdownColor: colors.surface,
                        style: TextStyle(color: colors.onSurface),
                        decoration: _inputDeco(_isBn ? 'বিভাগ' : 'Category'),
                        items: _kCategories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setS(() => wantedCategory = v ?? wantedCategory),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Text(_isBn ? 'সেশন সংখ্যা:' : 'Number of sessions:', style: TextStyle(color: colors.outline, fontSize: 12)),
                        const Spacer(),
                        IconButton(onPressed: () => setS(() => sessions = (sessions - 1).clamp(1, 12)), icon: Icon(Icons.remove_rounded, color: colors.outline)),
                        Text('$sessions', style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700)),
                        IconButton(onPressed: () => setS(() => sessions = (sessions + 1).clamp(1, 12)), icon: Icon(Icons.add_rounded, color: colors.primary)),
                      ]),
                      const SizedBox(height: 12),
                      _sheetField(msgCtrl, _isBn ? 'বার্তা (ঐচ্ছিক)' : 'Message (optional)', Icons.message_outlined, maxLines: 2),
                      const SizedBox(height: 24),
                      GlassButton(
                        label: _isBn ? 'পোস্ট করুন' : 'Post',
                        isLoading: submitting,
                        onPressed: submitting ? null : () async {
                          if (offeredSkillId == null || wantedNameCtrl.text.trim().isEmpty) {
                            _showError(_isBn ? 'সব ঘর পূরণ করুন' : 'Fill in all fields');
                            return;
                          }
                          setS(() => submitting = true);
                          try {
                            await _svc.proposeExchange(
                              offeredSkillId: offeredSkillId!,
                              wantedSkillName: wantedNameCtrl.text.trim(),
                              wantedSkillCategory: wantedCategory,
                              message: msgCtrl.text.trim(),
                              agreedSessionCount: sessions,
                            );
                            if (ctx.mounted) { Navigator.pop(ctx); _loadMyExchanges(); _tabController.animateTo(2); }
                            _showSuccess(_isBn ? 'অনুরোধ পোস্ট হয়েছে' : 'Request posted');
                          } catch (e) {
                            setS(() => submitting = false);
                            if (ctx.mounted) _showError(ApiClient.mapError(e).localized(_isBn));
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
      ),
    );
  }

  void _showRespondSheet(Map<String, dynamic> exchange) {
    final colors = Theme.of(context).colorScheme;
    String? myOfferId = _mySkills.isNotEmpty ? _mySkills.first['id'] as String? : null;
    bool submitting = false;

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
                    Text(_isBn ? 'এই অনুরোধে সাড়া দিন' : 'Respond to This Request', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    if (_mySkills.isEmpty)
                      Text(_isBn ? 'গ্রহণ করতে হলে আগে অন্তত একটি দক্ষতা যোগ করুন' : 'Add at least one skill before you can accept', style: TextStyle(color: colors.outline, fontSize: 13))
                    else ...[
                      Text(_isBn ? 'বিনিময়ে আপনি কোন দক্ষতা দেবেন:' : 'What skill will you give in exchange:', style: TextStyle(color: colors.outline, fontSize: 12)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: myOfferId,
                        dropdownColor: colors.surface,
                        style: TextStyle(color: colors.onSurface),
                        decoration: _inputDeco(_isBn ? 'আমার দক্ষতা' : 'My skill'),
                        items: _mySkills.map((s) => DropdownMenuItem<String>(value: s['id'] as String?, child: Text(s['skillName'] as String? ?? ''))).toList(),
                        onChanged: (v) => setS(() => myOfferId = v),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(children: [
                      Expanded(
                        child: GlassButton(
                          label: _isBn ? 'পাস করুন' : 'Pass',
                          isOutlined: true,
                          isLoading: submitting,
                          onPressed: submitting ? null : () => _respond(ctx, exchange, false, null, (v) => setS(() => submitting = v)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlassButton(
                          label: _isBn ? 'গ্রহণ করুন' : 'Accept',
                          isLoading: submitting,
                          onPressed: (submitting || _mySkills.isEmpty) ? null : () => _respond(ctx, exchange, true, myOfferId, (v) => setS(() => submitting = v)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _respond(BuildContext ctx, Map<String, dynamic> exchange, bool accept, String? wantedSkillId, void Function(bool) setSubmitting) async {
    setSubmitting(true);
    try {
      await _svc.respondToExchange(exchange['id'] as String, accept: accept, wantedSkillId: wantedSkillId);
      if (ctx.mounted) Navigator.pop(ctx);
      _showSuccess(accept ? (_isBn ? 'গ্রহণ করা হয়েছে' : 'Accepted') : (_isBn ? 'পাস করা হয়েছে' : 'Passed'));
      await Future.wait([_loadOpenExchanges(), _loadMyExchanges()]);
      if (accept) _tabController.animateTo(2);
    } catch (e) {
      setSubmitting(false);
      // Most likely someone else already claimed it first — refresh so it drops off the feed.
      if (ctx.mounted) _showError(ApiClient.mapError(e).localized(_isBn));
      _loadOpenExchanges();
    }
  }

  Widget _buildExchangesTab() {
    final colors = Theme.of(context).colorScheme;
    if (_myExchanges.isEmpty) {
      return Center(child: Text(_isBn ? 'কোনো এক্সচেঞ্জ নেই' : 'No exchanges yet', style: TextStyle(color: colors.outline)));
    }
    return RefreshIndicator(
      color: colors.primary,
      backgroundColor: colors.surface,
      onRefresh: _loadMyExchanges,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _myExchanges.length,
        itemBuilder: (ctx, i) {
          final e = _myExchanges[i];
          final status = e['status'] as String? ?? 'proposed';
          final offered = e['offeredSkill'] as Map<String, dynamic>?;
          final statusColors = {
            'proposed': const Color(0xFFF59E0B),
            'accepted': const Color(0xFF10B981),
            'completed': const Color(0xFF8B5CF6),
            'cancelled': const Color(0xFFEF4444),
          };
          final color = statusColors[status] ?? colors.outline;
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExchangeDetailScreen(exchangeId: e['id'] as String? ?? ''))).then((_) => _loadMyExchanges()),
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
                  decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.swap_horiz_rounded, color: colors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${offered?['skillName'] ?? '—'} ↔ ${e['wantedSkillName'] ?? '—'}', style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(_isBn ? '${e['agreedSessionCount'] ?? 1} সেশন' : '${e['agreedSessionCount'] ?? 1} sessions', style: TextStyle(color: colors.outline, fontSize: 11)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.outline, size: 18),
              ]),
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
        },
      ),
    );
  }
}
