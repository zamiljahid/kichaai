import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';

class DisputeScreen extends StatefulWidget {
  const DisputeScreen({super.key});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _client = ApiClient.instance.dio;
  List<dynamic> _disputes = [];
  bool _isLoading = true;
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
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.get('/disputes/mine');
      if (mounted) {
        setState(() {
          _disputes = (res.data is List ? res.data : (res.data['items'] ?? res.data['data'] ?? [])) as List;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showNewDisputeSheet() {
    final jobIdCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedReason = 'POOR_QUALITY';
    bool isSaving = false;

    // Values are backend DisputeCategory enum codes.
    final reasons = [
      {'value': 'POOR_QUALITY', 'label': _isBn ? 'সেবার মান খারাপ' : 'Poor service quality'},
      {'value': 'JOB_NOT_DONE', 'label': _isBn ? 'প্রোভাইডার আসেননি / কাজ হয়নি' : 'Provider no-show / not done'},
      {'value': 'OVERCHARGING', 'label': _isBn ? 'অতিরিক্ত চার্জ' : 'Overcharging'},
      {'value': 'PROPERTY_DAMAGE', 'label': _isBn ? 'ক্ষতি হয়েছে' : 'Property damage'},
      {'value': 'BAD_BEHAVIOR', 'label': _isBn ? 'খারাপ আচরণ' : 'Bad behavior'},
      {'value': 'FALSE_CLAIM', 'label': _isBn ? 'মিথ্যা দাবি' : 'False claim'},
    ];

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
                    Text(_isBn ? 'অভিযোগ দাখিল করুন' : 'File a dispute', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    _sheetField(jobIdCtrl, _isBn ? 'জব আইডি' : 'Job ID', Icons.work_outline_rounded),
                    const SizedBox(height: 12),
                    Text(_isBn ? 'কারণ' : 'Reason', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      dropdownColor: AppColors.bgMid,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.glassWhite,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: reasons.map((r) => DropdownMenuItem(value: r['value'], child: Text(r['label']!))).toList(),
                      onChanged: (v) => setS(() => selectedReason = v ?? selectedReason),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: _isBn ? 'বিস্তারিত বিবরণ দিন...' : 'Describe in detail...',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.glassWhite,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlassButton(
                      label: isSaving ? (_isBn ? 'পাঠানো হচ্ছে...' : 'Sending...') : (_isBn ? 'অভিযোগ পাঠান' : 'Submit dispute'),
                      onPressed: isSaving ? null : () async {
                        if (jobIdCtrl.text.trim().isEmpty) return;
                        setS(() => isSaving = true);
                        try {
                          await _client.post('/disputes', data: {
                            'jobId': jobIdCtrl.text.trim(),
                            'category': selectedReason,
                            'description': descCtrl.text.trim(),
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            _load();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_isBn ? 'অভিযোগ দাখিল হয়েছে' : 'Dispute filed', style: const TextStyle(color: Colors.white)),
                                backgroundColor: const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          final ex = ApiClient.mapError(e);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ex.messageBn, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFEF4444), behavior: SnackBarBehavior.floating),
                            );
                          }
                          setS(() => isSaving = false);
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

  Widget _sheetField(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
        filled: true,
        fillColor: AppColors.glassWhite,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    final open = _disputes.where((d) => (d['status'] ?? '') != 'resolved' && (d['status'] ?? '') != 'closed').toList();
    final resolved = _disputes.where((d) => (d['status'] ?? '') == 'resolved' || (d['status'] ?? '') == 'closed').toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'অভিযোগ' : 'Disputes', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.deepBlue,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.deepBlue,
          tabs: [Tab(text: _isBn ? 'চলমান' : 'Open'), Tab(text: _isBn ? 'সমাধান হয়েছে' : 'Resolved')],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(open),
                _buildList(resolved),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewDisputeSheet,
        backgroundColor: const Color(0xFFEF4444),
        icon: const Icon(Icons.report_outlined, color: Colors.white),
        label: Text(_isBn ? 'নতুন অভিযোগ' : 'New dispute', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildList(List<dynamic> items) {
    if (items.isEmpty) {
      return Center(child: Text(_isBn ? 'কোনো অভিযোগ নেই' : 'No disputes', style: const TextStyle(color: AppColors.textMuted)));
    }
    return RefreshIndicator(
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final d = items[i] as Map<String, dynamic>;
          final status = d['status'] as String? ?? 'pending';
          final statusColor = switch (status) {
            'resolved' => const Color(0xFF10B981),
            'closed' => const Color(0xFF6B7280),
            'under_review' => AppColors.deepBlue,
            _ => const Color(0xFFF59E0B),
          };
          final statusLabel = _isBn
              ? switch (status) {
                  'resolved' => 'সমাধান হয়েছে',
                  'closed' => 'বন্ধ',
                  'under_review' => 'পর্যালোচনায়',
                  _ => 'অপেক্ষমাণ',
                }
              : switch (status) {
                  'resolved' => 'Resolved',
                  'closed' => 'Closed',
                  'under_review' => 'Under review',
                  _ => 'Pending',
                };

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgMid,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  Text(d['createdAt']?.toString().substring(0, 10) ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
                const SizedBox(height: 10),
                Text(
                  _reasonLabel((d['category'] ?? d['reason'])?.toString() ?? ''),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (d['description'] != null) ...[
                  const SizedBox(height: 4),
                  Text(d['description'] as String, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (d['resolution'] != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(d['resolution'] as String, style: const TextStyle(color: Color(0xFF10B981), fontSize: 12))),
                    ]),
                  ),
                ],
              ],
            ),
          ).animate(delay: Duration(milliseconds: i * 60)).fadeIn().slideY(begin: 0.05, end: 0);
        },
      ),
    );
  }

  String _reasonLabel(String reason) => _isBn
      ? switch (reason) {
          'POOR_QUALITY' => 'সেবার মান সন্তোষজনক নয়',
          'JOB_NOT_DONE' => 'প্রোভাইডার আসেননি / কাজ হয়নি',
          'OVERCHARGING' => 'অতিরিক্ত চার্জ করা হয়েছে',
          'PROPERTY_DAMAGE' => 'সম্পত্তির ক্ষতি হয়েছে',
          'BAD_BEHAVIOR' => 'খারাপ আচরণ',
          'FALSE_CLAIM' => 'মিথ্যা দাবি',
          _ => 'অন্যান্য অভিযোগ',
        }
      : switch (reason) {
          'POOR_QUALITY' => 'Poor service quality',
          'JOB_NOT_DONE' => 'Provider no-show / not done',
          'OVERCHARGING' => 'Overcharged',
          'PROPERTY_DAMAGE' => 'Property damage',
          'BAD_BEHAVIOR' => 'Bad behavior',
          'FALSE_CLAIM' => 'False claim',
          _ => 'Other',
        };
}
