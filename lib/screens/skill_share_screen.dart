import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';
import 'exchange_detail_screen.dart';

class SkillShareScreen extends StatefulWidget {
  const SkillShareScreen({super.key});

  @override
  State<SkillShareScreen> createState() => _SkillShareScreenState();
}

class _SkillShareScreenState extends State<SkillShareScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _client = ApiClient.instance.dio;
  String? _userId;

  List<dynamic> _mySkills = [];
  List<dynamic> _searchResults = [];
  List<dynamic> _myExchanges = [];
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await Future.wait([_loadMySkills(), _loadMyExchanges()]);
  }

  Future<void> _loadMySkills() async {
    if (_userId == null) return;
    try {
      final res = await _client.get('/skill-share/skills/user/$_userId');
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      if (mounted) setState(() { _mySkills = list as List; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMyExchanges() async {
    if (_userId == null) return;
    try {
      final res = await _client.get('/skill-share/exchanges', queryParameters: {'userId': _userId});
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      if (mounted) setState(() => _myExchanges = list as List);
    } catch (_) {}
  }

  Future<void> _searchSkills(String query) async {
    if (query.isEmpty) return;
    try {
      final res = await _client.get('/skill-share/skills/search', queryParameters: {'name': query});
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      if (mounted) setState(() => _searchResults = list as List);
    } catch (_) {}
  }

  void _showAddSkillSheet() {
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
                color: AppColors.bgMid,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    const Text('নতুন দক্ষতা যোগ করুন', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _sheetField(nameCtrl, 'দক্ষতার নাম', Icons.star_outline_rounded),
                    const SizedBox(height: 12),
                    _sheetField(descCtrl, 'বিবরণ', Icons.description_outlined, maxLines: 3),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: category,
                      dropdownColor: AppColors.bgMid,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDeco('বিভাগ'),
                      items: ['technology', 'language', 'art', 'music', 'sports', 'cooking', 'business']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setS(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: level,
                      dropdownColor: AppColors.bgMid,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDeco('স্তর'),
                      items: ['beginner', 'intermediate', 'expert']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setS(() => level = v ?? level),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: 'যোগ করুন',
                                            onPressed: () async {
                        try {
                          await _client.post('/skill-share/skills', data: {
                            'userId': _userId,
                            'skillName': nameCtrl.text,
                            'description': descCtrl.text,
                            'category': category,
                            'level': level,
                          });
                          if (ctx.mounted) { Navigator.pop(ctx); _loadMySkills(); }
                        } catch (_) {}
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

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textMuted),
    filled: true,
    fillColor: AppColors.glassWhite,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  Widget _sheetField(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: maxLines == 1 ? Icon(icon, color: AppColors.textMuted, size: 18) : null,
        filled: true,
        fillColor: AppColors.glassWhite,
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
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('স্কিল শেয়ার', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.deepBlue,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.deepBlue,
          tabs: const [Tab(text: 'আমার দক্ষতা'), Tab(text: 'খুঁজুন'), Tab(text: 'এক্সচেঞ্জ')],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMySkillsTab(),
                _buildSearchTab(),
                _buildExchangesTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSkillSheet,
        backgroundColor: AppColors.deepBlue,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildMySkillsTab() {
    if (_mySkills.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.textMuted, size: 56),
          const SizedBox(height: 12),
          const Text('কোনো দক্ষতা নেই', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          TextButton(onPressed: _showAddSkillSheet, child: const Text('যোগ করুন', style: TextStyle(color: AppColors.deepBlue))),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _mySkills.length,
      itemBuilder: (ctx, i) {
        final s = _mySkills[i] as Map<String, dynamic>;
        final level = s['level'] as String? ?? 'beginner';
        return GestureDetector(
          onTap: () => _showEditSkillSheet(s),
          child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgMid,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.auto_awesome_rounded, color: AppColors.deepBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['skillName'] as String? ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(s['category'] as String? ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _levelColor(level).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
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
    final skillId = s['id'] as String? ?? '';
    if (skillId.isEmpty) return;
    final nameCtrl = TextEditingController(text: s['skillName'] as String? ?? '');
    final descCtrl = TextEditingController(text: s['description'] as String? ?? '');
    String category = s['category'] as String? ?? 'technology';
    String level = s['level'] as String? ?? 'beginner';
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
                color: AppColors.bgMid,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    const Text('দক্ষতা সম্পাদনা করুন', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _sheetField(nameCtrl, 'দক্ষতার নাম', Icons.star_outline_rounded),
                    const SizedBox(height: 12),
                    _sheetField(descCtrl, 'বিবরণ', Icons.description_outlined, maxLines: 3),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: ['technology', 'language', 'art', 'music', 'sports', 'cooking', 'business'].contains(category) ? category : 'technology',
                      dropdownColor: AppColors.bgMid,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDeco('বিভাগ'),
                      items: ['technology', 'language', 'art', 'music', 'sports', 'cooking', 'business']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setS(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: ['beginner', 'intermediate', 'advanced', 'expert'].contains(level) ? level : 'beginner',
                      dropdownColor: AppColors.bgMid,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDeco('স্তর'),
                      items: ['beginner', 'intermediate', 'advanced', 'expert']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setS(() => level = v ?? level),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: 'সংরক্ষণ করুন',
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
                          await _client.patch('/skill-share/skills/$skillId', data: changes);
                          if (ctx.mounted) { Navigator.pop(ctx); _loadMySkills(); }
                        } catch (_) {
                          setS(() => saving = false);
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

  Widget _buildSearchTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.textPrimary),
          onSubmitted: _searchSkills,
          decoration: InputDecoration(
            hintText: 'দক্ষতা খুঁজুন...',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
            suffixIcon: IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.deepBlue), onPressed: () => _searchSkills(_searchCtrl.text)),
            filled: true,
            fillColor: AppColors.bgMid,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.glassBorder)),
          ),
        ),
      ),
      Expanded(
        child: _searchResults.isEmpty
            ? const Center(child: Text('কিছু লিখে খুঁজুন', style: TextStyle(color: AppColors.textMuted)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: _searchResults.length,
                itemBuilder: (ctx, i) {
                  final s = _searchResults[i] as Map<String, dynamic>;
                  final level = s['level'] as String? ?? 'beginner';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgMid,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s['skillName'] as String? ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(s['category'] as String? ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: _levelColor(level).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text(level, style: TextStyle(color: _levelColor(level), fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _proposeExchange(s),
                        child: const Text('প্রস্তাব', style: TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  void _proposeExchange(Map<String, dynamic> responderSkill) {
    if (_mySkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('প্রথমে আপনার দক্ষতা যোগ করুন', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFFF59E0B), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    String? mySkillId = (_mySkills.first as Map<String, dynamic>)['id'] as String?;
    int sessions = 3;
    final msgCtrl = TextEditingController();

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
                color: AppColors.bgMid,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    const Text('এক্সচেঞ্জ প্রস্তাব', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    const Text('আপনার দক্ষতা নির্বাচন করুন:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: mySkillId,
                      dropdownColor: AppColors.bgMid,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDeco('আমার দক্ষতা'),
                      items: _mySkills.map((s) {
                        final skill = s as Map<String, dynamic>;
                        return DropdownMenuItem<String>(value: skill['id'] as String?, child: Text(skill['skillName'] as String? ?? ''));
                      }).toList(),
                      onChanged: (v) => setS(() => mySkillId = v),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('সেশন সংখ্যা:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const Spacer(),
                      IconButton(onPressed: () => setS(() => sessions = (sessions - 1).clamp(1, 12)), icon: const Icon(Icons.remove_rounded, color: AppColors.textMuted)),
                      Text('$sessions', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                      IconButton(onPressed: () => setS(() => sessions = (sessions + 1).clamp(1, 12)), icon: const Icon(Icons.add_rounded, color: AppColors.deepBlue)),
                    ]),
                    const SizedBox(height: 12),
                    _sheetField(msgCtrl, 'বার্তা (ঐচ্ছিক)', Icons.message_outlined),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: 'প্রস্তাব পাঠান',
                                            onPressed: () async {
                        final responderId = responderSkill['userId'] as String?;
                        try {
                          await _client.post('/skill-share/exchanges', data: {
                            'requesterId': _userId,
                            'responderId': responderId,
                            'requesterSkillId': mySkillId,
                            'responderSkillId': responderSkill['id'],
                            'proposedSessions': sessions,
                            'message': msgCtrl.text,
                          });
                          if (ctx.mounted) { Navigator.pop(ctx); _loadMyExchanges(); _tabController.animateTo(2); }
                        } catch (_) {}
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

  Widget _buildExchangesTab() {
    if (_myExchanges.isEmpty) {
      return const Center(child: Text('কোনো এক্সচেঞ্জ নেই', style: TextStyle(color: AppColors.textMuted)));
    }
    return RefreshIndicator(
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      onRefresh: _loadMyExchanges,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _myExchanges.length,
        itemBuilder: (ctx, i) {
          final e = _myExchanges[i] as Map<String, dynamic>;
          final status = e['status'] as String? ?? 'proposed';
          final statusColors = {
            'proposed': const Color(0xFFF59E0B),
            'accepted': const Color(0xFF10B981),
            'completed': const Color(0xFF8B5CF6),
            'cancelled': const Color(0xFFEF4444),
          };
          final color = statusColors[status] ?? AppColors.textMuted;
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExchangeDetailScreen(exchangeId: e['id'] as String? ?? ''))).then((_) => _loadMyExchanges()),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgMid,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.deepBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.swap_horiz_rounded, color: AppColors.deepBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('এক্সচেঞ্জ #${(e['id'] as String? ?? '').substring(0, 8)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${e['proposedSessions'] ?? 0} সেশন', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
              ]),
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
        },
      ),
    );
  }
}
