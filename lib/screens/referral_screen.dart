import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_button.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _client = ApiClient.instance.dio;
  Map<String, dynamic>? _referral;
  List<dynamic> _referrals = [];
  bool _isLoading = true;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _client.get('/auth/referral'),
        _client.get('/auth/referrals'),
      ]);
      if (mounted) {
        setState(() {
          _referral = results[0].data as Map<String, dynamic>?;
          final listData = results[1].data;
          _referrals = (listData is List ? listData : (listData['items'] ?? listData['data'] ?? [])) as List;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyCode() {
    final code = _referral?['referralCode'] as String? ?? '';
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isBn ? 'রেফারেল কোড কপি হয়েছে' : 'Referral code copied', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
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
        title: Text(_isBn ? 'রেফারেল' : 'Referral', style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : RefreshIndicator(
              color: colors.primary,
              backgroundColor: colors.surface,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _buildCodeCard(),
                  const SizedBox(height: 20),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  Text(_isBn ? 'রেফারেল তালিকা' : 'Referral list', style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  if (_referrals.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(_isBn ? 'এখনো কোনো রেফারেল নেই' : 'No referrals yet', style: TextStyle(color: colors.outline)),
                      ),
                    )
                  else
                    ..._referrals.asMap().entries.map((e) => _buildReferralTile(e.value as Map<String, dynamic>, e.key)),
                ],
              ),
            ),
    );
  }

  Widget _buildCodeCard() {
    final colors = Theme.of(context).colorScheme;
    final code = _referral?['referralCode'] as String? ?? '------';
    final earnings = ((_referral?['creditsEarned'] ?? 0) as num).toDouble();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppGradients.primary(colors),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(_isBn ? 'আপনার রেফারেল কোড' : 'Your referral code', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              code,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: GlassButton(
                label: _isBn ? 'কপি করুন' : 'Copy',
                onPressed: _copyCode,
                isOutlined: true,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text('${_isBn ? 'মোট আয়' : 'Total earnings'}: ৳${earnings.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1, end: 0);
  }

  Widget _buildStatsRow() {
    final total = _referrals.length;
    final active = _referrals.where((r) => (r['status'] ?? '') == 'active').length;
    final pending = _referrals.where((r) => (r['status'] ?? '') == 'pending').length;

    return Row(children: [
      _statCard(_isBn ? 'মোট' : 'Total', '$total', const Color(0xFF3B82F6)),
      const SizedBox(width: 12),
      _statCard(_isBn ? 'সক্রিয়' : 'Active', '$active', const Color(0xFF10B981)),
      const SizedBox(width: 12),
      _statCard(_isBn ? 'অপেক্ষমাণ' : 'Pending', '$pending', const Color(0xFFF59E0B)),
    ]);
  }

  Widget _statCard(String label, String value, Color color) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: colors.outline, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _buildReferralTile(Map<String, dynamic> r, int index) {
    final colors = Theme.of(context).colorScheme;
    final status = r['status'] as String? ?? 'pending';
    final statusColor = status == 'active' ? const Color(0xFF10B981) : status == 'completed' ? colors.primary : const Color(0xFFF59E0B);
    final statusLabel = _isBn
        ? (status == 'active' ? 'সক্রিয়' : status == 'completed' ? 'সম্পন্ন' : 'অপেক্ষমাণ')
        : (status == 'active' ? 'Active' : status == 'completed' ? 'Completed' : 'Pending');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.person_outline_rounded, color: colors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['fullName'] ?? (_isBn ? 'ব্যবহারকারী' : 'User'), style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(r['createdAt']?.toString().substring(0, 10) ?? '', style: TextStyle(color: colors.outline, fontSize: 11)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ]),
    ).animate(delay: Duration(milliseconds: index * 50)).fadeIn().slideX(begin: 0.05, end: 0);
  }
}
