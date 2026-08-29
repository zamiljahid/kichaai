import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_theme.dart';

class CommissionScreen extends StatefulWidget {
  const CommissionScreen({super.key});

  @override
  State<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends State<CommissionScreen> {
  final _client = ApiClient.instance.dio;
  List<dynamic> _commissions = [];
  bool _isLoading = true;
  double _totalPending = 0;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await _client.get('/dispatch/commissions/mine');
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      final commissions = (list as List).cast<Map<String, dynamic>>();
      final pending = commissions
          .where((c) => (c['status'] as String? ?? '').toLowerCase() == 'pending')
          .fold<double>(0, (sum, c) => sum + (double.tryParse('${c['commissionAmount']}') ?? 0));
      if (mounted) {
        setState(() {
          _commissions = commissions;
          _totalPending = pending;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid': return const Color(0xFF10B981);
      case 'overdue': return const Color(0xFFEF4444);
      default: return const Color(0xFFF59E0B);
    }
  }

  String _statusLabel(String status) {
    if (_isBn) {
      switch (status) {
        case 'paid': return 'পরিশোধিত';
        case 'overdue': return 'বকেয়া';
        default: return 'অপেক্ষমাণ';
      }
    }
    switch (status) {
      case 'paid': return 'Paid';
      case 'overdue': return 'Overdue';
      default: return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBn ? 'কমিশন' : 'Commission', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : RefreshIndicator(
              color: AppColors.deepBlue,
              backgroundColor: AppColors.bgMid,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _buildPendingCard(),
                  const SizedBox(height: 16),
                  Text(_isBn ? 'কমিশন ইতিহাস' : 'Commission History', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(height: 10),
                  if (_commissions.isEmpty)
                    Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_isBn ? 'কোনো কমিশন নেই' : 'No commissions', style: const TextStyle(color: AppColors.textMuted))))
                  else
                    ..._commissions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final c = entry.value as Map<String, dynamic>;
                      final status = (c['status'] as String? ?? 'pending').toLowerCase();
                      final color = _statusColor(status);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppColors.bgMid,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: Icon(status == 'paid' ? Icons.check_circle_outline_rounded : Icons.schedule_rounded, color: color, size: 22),
                              ),
                              title: Text('${_isBn ? 'জব' : 'Job'} #${(c['jobId'] as String? ?? '').substring(0, 8.clamp(0, (c['jobId'] as String? ?? '').length))}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(c['dueAt']?.toString().substring(0, 10) ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('৳${(double.tryParse('${c['commissionAmount']}') ?? 0).toStringAsFixed(0)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
                    }),
                ],
              ),
            ),
    );
  }

  Widget _buildPendingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFF59E0B).withOpacity(0.8), const Color(0xFFD97706).withOpacity(0.8)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isBn ? 'মোট বকেয়া কমিশন' : 'Total Pending Commission', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text('৳${_totalPending.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
        ]),
        const Spacer(),
        const Icon(Icons.account_balance_outlined, color: Colors.white38, size: 44),
      ]),
    ).animate().fadeIn().slideY(begin: -0.2, end: 0);
  }
}
