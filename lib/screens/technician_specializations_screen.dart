import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// Technician onboarding — "আমি কোন কোন কাজ পারি?"
///
/// The taxonomy (5 groups × 36 types) is fetched from the backend. Bengali
/// labels + Material icon names come from there — never hard-code these.
/// Ticks are saved to /auth/provider-profile/specializations-new (JWT).
/// Without this snapshot an online technician never receives specialized jobs.
class TechnicianSpecializationsScreen extends StatefulWidget {
  const TechnicianSpecializationsScreen({super.key});

  @override
  State<TechnicianSpecializationsScreen> createState() =>
      _TechnicianSpecializationsScreenState();
}

class _TechnicianSpecializationsScreenState
    extends State<TechnicianSpecializationsScreen> {
  TechnicianSpecializationTaxonomy? _taxonomy;
  final Set<String> _selected = {};
  final Set<String> _expandedGroups = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        CatalogService.instance.getTechnicianSpecializationsNew(),
        AuthService.instance.getMeRaw(),
      ]);
      if (!mounted) return;
      final tax = results[0] as TechnicianSpecializationTaxonomy;
      final me = results[1] as Map<String, dynamic>;
      final pp = me['providerProfile'];
      final existing = (pp is Map ? pp['specializations'] : null) as List?;
      setState(() {
        _taxonomy = tax;
        _selected
          ..clear()
          ..addAll(
            (existing ?? const <dynamic>[]).whereType<String>(),
          );
        // Auto-expand any group that already has at least one tick so the user
        // can see what's saved without hunting for it.
        _expandedGroups
          ..clear()
          ..addAll(
            tax.tree
                .where(
                  (n) => n.types.any((t) => _selected.contains(t.code)),
                )
                .map((n) => n.group.code),
          );
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiClient.mapError(e).localized(_isBn);
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final persisted = await AuthService.instance
          .saveTechnicianSpecializations(_selected.toList());
      if (!mounted) return;
      setState(() {
        // Backend drops unknown codes — trust the response as the source of truth.
        _selected
          ..clear()
          ..addAll(persisted);
        _saving = false;
      });
      _snack(
        persisted.isEmpty
            ? (_isBn ? 'কোনো বিশেষত্ব যুক্ত হয়নি' : 'No specializations added')
            : (_isBn ? 'সংরক্ষিত হয়েছে — ${persisted.length} টি বিশেষত্ব' : 'Saved — ${persisted.length} specialization(s)'),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(_isBn ? 'সংরক্ষণ ব্যর্থ: ${ApiClient.mapError(e).localized(_isBn)}' : 'Save failed: ${ApiClient.mapError(e).localized(_isBn)}', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor:
          error ? const Color(0xFFEF4444) : const Color(0xFF10B981),
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
              _buildAppBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: colors.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              _isBn ? 'আমি কোন কোন কাজ পারি?' : 'What jobs can I do?',
              style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
          ),
          if (!_loading && _taxonomy != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_selected.length}',
                style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              GlassButton(
                  label: _isBn ? 'আবার চেষ্টা করুন' : 'Try again',
                  isOutlined: true,
                  onPressed: _load),
            ],
          ),
        ),
      );
    }
    final tax = _taxonomy!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.lightbulb_outline_rounded,
                      color: colors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isBn
                        ? 'যেসব কাজ পারেন সেগুলো টিক দিন — শুধু এই কাজের অনুরোধই আপনার কাছে যাবে।'
                        : 'Tick the jobs you can do — only requests for these will reach you.',
                    style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            itemCount: tax.tree.length,
            itemBuilder: (_, i) => _buildGroupCard(tax.tree[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: GlassButton(
            label: _isBn ? 'সংরক্ষণ করুন' : 'Save',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupCard(TechnicianSpecTreeNode node) {
    final colors = Theme.of(context).colorScheme;
    final expanded = _expandedGroups.contains(node.group.code);
    final selectedInGroup =
        node.types.where((t) => _selected.contains(t.code)).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() {
                if (expanded) {
                  _expandedGroups.remove(node.group.code);
                } else {
                  _expandedGroups.add(node.group.code);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: AppGradients.primary(colors),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(technicianSpecIcon(node.group.icon),
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isBn ? node.group.bn : node.group.en,
                            style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedInGroup > 0
                                ? (_isBn ? '$selectedInGroup / ${node.types.length} নির্বাচিত' : '$selectedInGroup / ${node.types.length} selected')
                                : (_isBn ? '${node.types.length} টি বিকল্প' : '${node.types.length} options'),
                            style: TextStyle(
                              color: selectedInGroup > 0
                                  ? colors.primary
                                  : colors.outline,
                              fontSize: 11.5,
                              fontWeight: selectedInGroup > 0
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: colors.outline,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: node.types.map((t) {
                    final isSelected = _selected.contains(t.code);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _selected.remove(t.code);
                        } else {
                          _selected.add(t.code);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient:
                              isSelected ? AppGradients.primary(colors) : null,
                          color:
                              isSelected ? null : colors.surface,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isSelected
                                ? colors.primary
                                : colors.outlineVariant,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              _isBn ? t.bn : t.en,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : colors.onSurfaceVariant,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
