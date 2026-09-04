import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_button.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class _AgentInfo {
  final String id;
  final String code;
  final String status;
  final double totalEarnings;
  final double pendingEarnings;
  final int totalReferrals;

  const _AgentInfo({
    required this.id,
    required this.code,
    required this.status,
    required this.totalEarnings,
    required this.pendingEarnings,
    required this.totalReferrals,
  });

  factory _AgentInfo.fromJson(Map<String, dynamic> json) {
    return _AgentInfo(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      totalEarnings: (json['totalEarnings'] as num?)?.toDouble() ?? 0.0,
      pendingEarnings: (json['pendingEarnings'] as num?)?.toDouble() ?? 0.0,
      totalReferrals: (json['totalReferrals'] as num?)?.toInt() ?? 0,
    );
  }
}

class _Technician {
  final String id;
  final String technicianName;
  final String phone;
  final String? nidNumber;
  final bool isActive;

  const _Technician({
    required this.id,
    required this.technicianName,
    required this.phone,
    this.nidNumber,
    this.isActive = true,
  });

  factory _Technician.fromJson(Map<String, dynamic> json) => _Technician(
        id: json['id']?.toString() ?? '',
        technicianName: json['technicianName']?.toString() ?? json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        nidNumber: json['nidNumber']?.toString(),
        isActive: json['isActive'] as bool? ?? true,
      );
}

class _MessProperty {
  final String id;
  final String messName;
  final String address;
  final int totalSeats;

  const _MessProperty({
    required this.id,
    required this.messName,
    required this.address,
    required this.totalSeats,
  });

  factory _MessProperty.fromJson(Map<String, dynamic> json) => _MessProperty(
        id: json['id']?.toString() ?? '',
        messName: json['messName']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        totalSeats: (json['totalSeats'] as num?)?.toInt() ?? 0,
      );
}

// ── Screen ────────────────────────────────────────────────────────────────────

enum _ScreenState { loading, notAgent, isAgent }

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final _client = ApiClient.instance.dio;
  final _motivationController = TextEditingController();

  _ScreenState _screenState = _ScreenState.loading;
  _AgentInfo? _agentInfo;
  List<_Technician> _technicians = [];
  List<_MessProperty> _properties = [];

  bool _isRegistering = false;
  bool _isLoadingCrew = false;
  String? _errorMessage;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _loadAgentInfo();
  }

  @override
  void dispose() {
    _motivationController.dispose();
    super.dispose();
  }

  // ── API calls ──────────────────────────────────────────────────────────────

  Future<void> _loadAgentInfo() async {
    setState(() {
      _screenState = _ScreenState.loading;
      _errorMessage = null;
    });

    try {
      final res = await _client.get('/auth/agents/me');
      final data = res.data as Map<String, dynamic>;
      final agent = _AgentInfo.fromJson(data);
      if (mounted) {
        setState(() {
          _agentInfo = agent;
          _screenState = _ScreenState.isAgent;
        });
        _loadCrew();
      }
    } catch (e) {
      final ex = ApiClient.mapError(e);
      if (mounted) {
        if (ex.statusCode == 404) {
          setState(() => _screenState = _ScreenState.notAgent);
        } else {
          setState(() {
            _screenState = _ScreenState.notAgent;
            _errorMessage = ex.localized(_isBn);
          });
        }
      }
    }
  }

  Future<void> _loadCrew() async {
    if (!mounted) return;
    setState(() => _isLoadingCrew = true);
    try {
      final results = await Future.wait([
        _client.get('/auth/agents/me/technicians', queryParameters: {'limit': 100, 'offset': 0}),
        _client.get('/auth/agents/me/properties', queryParameters: {'limit': 100, 'offset': 0}),
      ]);
      List<dynamic> unwrap(dynamic data) =>
          data is List ? data : (data['items'] ?? data['data'] ?? []) as List;
      if (mounted) {
        setState(() {
          _technicians = unwrap(results[0].data)
              .map((e) => _Technician.fromJson(e as Map<String, dynamic>))
              .toList();
          _properties = unwrap(results[1].data)
              .map((e) => _MessProperty.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoadingCrew = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCrew = false);
    }
  }

  Future<void> _addOrEditTechnician({_Technician? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.technicianName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final nidCtrl = TextEditingController(text: existing?.nidNumber ?? '');
    final saved = await _showFormSheet(
      title: existing == null
          ? (_isBn ? 'নতুন টেকনিশিয়ান' : 'New Technician')
          : (_isBn ? 'টেকনিশিয়ান সম্পাদনা' : 'Edit Technician'),
      fields: [
        (nameCtrl, _isBn ? 'নাম' : 'Name', TextInputType.text),
        (phoneCtrl, _isBn ? 'ফোন নম্বর' : 'Phone number', TextInputType.phone),
        (nidCtrl, _isBn ? 'NID নম্বর' : 'NID number', TextInputType.number),
      ],
      onSubmit: () async {
        final name = nameCtrl.text.trim();
        final phone = phoneCtrl.text.trim();
        final nid = nidCtrl.text.trim();
        if (name.isEmpty || phone.isEmpty || nid.isEmpty) {
          throw _isBn ? 'নাম, ফোন ও NID দিন' : 'Enter name, phone and NID';
        }
        if (existing == null) {
          await _client.post('/auth/agents/me/technicians',
              data: {'technicianName': name, 'phone': phone, 'nidNumber': nid});
        } else {
          await _client.patch('/auth/agents/me/technicians/${existing.id}',
              data: {'technicianName': name, 'phone': phone, 'nidNumber': nid});
        }
      },
    );
    if (saved) { _showSnackBar(existing == null ? (_isBn ? 'টেকনিশিয়ান যোগ হয়েছে' : 'Technician added') : (_isBn ? 'আপডেট হয়েছে' : 'Updated'), const Color(0xFF10B981)); _loadCrew(); }
  }

  Future<void> _deleteTechnician(_Technician t) async {
    final colors = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isBn ? 'মুছবেন?' : 'Delete?', style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(_isBn ? '"${t.technicianName}" সরানো হবে।' : '"${t.technicianName}" will be removed.', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isBn ? 'বাতিল' : 'Cancel', style: TextStyle(color: colors.outline))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_isBn ? 'মুছুন' : 'Delete', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.delete('/auth/agents/me/technicians/${t.id}');
      _showSnackBar(_isBn ? 'মুছে ফেলা হয়েছে' : 'Deleted', const Color(0xFF10B981));
      _loadCrew();
    } catch (e) {
      _showSnackBar(ApiClient.mapError(e).localized(_isBn), const Color(0xFFEF4444));
    }
  }

  Future<void> _addProperty() async {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final seatsCtrl = TextEditingController();
    final saved = await _showFormSheet(
      title: _isBn ? 'নতুন মেস প্রপার্টি' : 'New Mess Property',
      fields: [
        (nameCtrl, _isBn ? 'মেসের নাম' : 'Mess name', TextInputType.text),
        (addressCtrl, _isBn ? 'ঠিকানা' : 'Address', TextInputType.text),
        (seatsCtrl, _isBn ? 'মোট আসন' : 'Total seats', TextInputType.number),
      ],
      onSubmit: () async {
        final name = nameCtrl.text.trim();
        final address = addressCtrl.text.trim();
        final seats = int.tryParse(seatsCtrl.text.trim());
        if (name.isEmpty || address.isEmpty || seats == null) {
          throw _isBn ? 'নাম, ঠিকানা ও আসন সংখ্যা দিন' : 'Enter name, address and seat count';
        }
        await _client.post('/auth/agents/me/properties', data: {
          'messName': name,
          'address': address,
          'totalSeats': seats,
          'photosUrls': <String>[],
        });
      },
    );
    if (saved) { _showSnackBar(_isBn ? 'প্রপার্টি যোগ হয়েছে' : 'Property added', const Color(0xFF10B981)); _loadCrew(); }
  }

  /// Generic bottom-sheet form. Returns true if onSubmit succeeded.
  Future<bool> _showFormSheet({
    required String title,
    required List<(TextEditingController, String, TextInputType)> fields,
    required Future<void> Function() onSubmit,
  }) async {
    final colors = Theme.of(context).colorScheme;
    bool saving = false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              Text(title, style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              ...fields.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: f.$1,
                      keyboardType: f.$3,
                      style: TextStyle(color: colors.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: f.$2,
                        hintStyle: TextStyle(color: colors.outline, fontSize: 13),
                        filled: true,
                        fillColor: colors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.outlineVariant)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.outlineVariant)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.primary)),
                      ),
                    ),
                  )),
              const SizedBox(height: 10),
              GlassButton(
                label: _isBn ? 'সংরক্ষণ করুন' : 'Save',
                isLoading: saving,
                onPressed: saving ? null : () async {
                  setS(() => saving = true);
                  try {
                    await onSubmit();
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    setS(() => saving = false);
                    _showSnackBar(e is String ? e : ApiClient.mapError(e).localized(_isBn), const Color(0xFFEF4444));
                  }
                },
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _registerAsAgent() async {
    setState(() {
      _isRegistering = true;
      _errorMessage = null;
    });

    try {
      final body = <String, dynamic>{};
      final motivation = _motivationController.text.trim();
      if (motivation.isNotEmpty) body['motivation'] = motivation;

      final res = await _client.post('/auth/agents/register', data: body);
      final data = res.data as Map<String, dynamic>;
      final agent = _AgentInfo.fromJson(data);

      if (mounted) {
        setState(() {
          _agentInfo = agent;
          _screenState = _ScreenState.isAgent;
          _isRegistering = false;
        });
        _loadCrew();
        _showSnackBar(_isBn ? 'এজেন্ট হিসেবে সফলভাবে নিবন্ধিত হয়েছেন!' : 'Successfully registered as an agent!', const Color(0xFF10B981));
      }
    } catch (e) {
      final ex = ApiClient.mapError(e);
      if (mounted) {
        setState(() {
          _errorMessage = ex.localized(_isBn);
          _isRegistering = false;
        });
      }
    }
  }

  void _copyAgentCode() {
    final code = _agentInfo?.code ?? '';
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    _showSnackBar(_isBn ? 'এজেন্ট কোড কপি হয়েছে' : 'Agent code copied', const Color(0xFF10B981));
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isBn ? 'এজেন্ট' : 'Agent',
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colors.onSurface,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_screenState == _ScreenState.isAgent)
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: colors.outline, size: 20),
              onPressed: _loadAgentInfo,
            ),
        ],
      ),
      body: switch (_screenState) {
        _ScreenState.loading => Center(
            child: CircularProgressIndicator(color: colors.primary),
          ),
        _ScreenState.notAgent => _buildRegistrationView(),
        _ScreenState.isAgent => _buildDashboardView(),
      },
    );
  }

  // ── State A: Registration view ─────────────────────────────────────────────

  Widget _buildRegistrationView() {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          _buildIllustration(),
          const SizedBox(height: 28),
          Text(
            _isBn ? 'এজেন্ট হয়ে আয় করুন' : 'Earn as an Agent',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 10),
          Text(
            _isBn
                ? 'সার্ভিস প্রদানকারীদের নিয়োগ করুন এবং প্রতিটি সফল রেফারেলে কমিশন উপার্জন করুন।'
                : 'Recruit service providers and earn commission on every successful referral.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.outline,
              fontSize: 14,
              height: 1.6,
            ),
          ).animate().fadeIn(delay: 150.ms),
          const SizedBox(height: 28),
          _buildBenefitChips(),
          const SizedBox(height: 32),
          _buildMotivationField(),
          const SizedBox(height: 12),
          if (_errorMessage != null) ...[
            _buildErrorBanner(_errorMessage!),
            const SizedBox(height: 12),
          ],
          GlassButton(
            label: _isBn ? 'এজেন্ট হিসেবে নিবন্ধন করুন' : 'Register as Agent',
            isLoading: _isRegistering,
            onPressed: _isRegistering ? null : _registerAsAgent,
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
        ],
      ),
    );
  }

  Widget _buildIllustration() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        gradient: AppGradients.primary(colors),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colors.primary.withOpacity(0.4),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Icon(
        Icons.groups_rounded,
        color: Colors.white,
        size: 54,
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1));
  }

  Widget _buildBenefitChips() {
    final chips = _isBn
        ? const [
            (Icons.percent_rounded, 'কমিশন আয়', Color(0xFF2563EB)),
            (Icons.card_giftcard_rounded, 'রেফারেল বোনাস', Color(0xFF10B981)),
            (Icons.hub_rounded, 'নেটওয়ার্ক তৈরি', Color(0xFFF59E0B)),
          ]
        : const [
            (Icons.percent_rounded, 'Commission Earnings', Color(0xFF2563EB)),
            (Icons.card_giftcard_rounded, 'Referral Bonus', Color(0xFF10B981)),
            (Icons.hub_rounded, 'Build Network', Color(0xFFF59E0B)),
          ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: chips.asMap().entries.map((entry) {
        final i = entry.key;
        final chip = entry.value;
        return _BenefitChip(
          icon: chip.$1,
          label: chip.$2,
          color: chip.$3,
        ).animate().fadeIn(delay: Duration(milliseconds: 200 + i * 80)).slideY(begin: 0.15, end: 0);
      }).toList(),
    );
  }

  Widget _buildMotivationField() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isBn ? 'আপনার উদ্দেশ্য (ঐচ্ছিক)' : 'Your Motivation (optional)',
          style: TextStyle(
            color: colors.outline,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: TextField(
              controller: _motivationController,
              maxLines: 3,
              style: TextStyle(color: colors.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: _isBn ? 'আপনি কেন এজেন্ট হতে চান তা লিখুন...' : 'Write why you want to become an agent...',
                hintStyle: TextStyle(color: colors.outline, fontSize: 13),
                filled: true,
                fillColor: colors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.outlineVariant, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.outlineVariant, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 250.ms);
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1, end: 0);
  }

  // ── State B: Agent dashboard ───────────────────────────────────────────────

  Widget _buildDashboardView() {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: colors.primary,
      backgroundColor: colors.surface,
      onRefresh: _loadAgentInfo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _buildAgentCard(),
          const SizedBox(height: 24),
          _sectionHeader(_isBn ? 'আমার টেকনিশিয়ান' : 'My Technicians', Icons.engineering_rounded, () => _addOrEditTechnician()),
          const SizedBox(height: 12),
          _buildTechnicianList(),
          const SizedBox(height: 24),
          _sectionHeader(_isBn ? 'মেস প্রপার্টি' : 'Mess Properties', Icons.home_work_rounded, _addProperty),
          const SizedBox(height: 12),
          _buildPropertyList(),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, VoidCallback onAdd) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.outline, size: 16),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const Spacer(),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, color: colors.onPrimary, size: 15),
              const SizedBox(width: 3),
              Text(_isBn ? 'যোগ' : 'Add', style: TextStyle(color: colors.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildTechnicianList() {
    final colors = Theme.of(context).colorScheme;
    if (_isLoadingCrew) {
      return Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(color: colors.primary)));
    }
    if (_technicians.isEmpty) return _emptyBox(_isBn ? 'এখনো কোনো টেকনিশিয়ান যোগ করা হয়নি' : 'No technicians added yet');
    return Column(
      children: _technicians.asMap().entries.map((e) {
        final t = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: colors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.engineering_rounded, color: colors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.technicianName, style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(t.phone, style: TextStyle(color: colors.outline, fontSize: 11)),
            ])),
            IconButton(icon: Icon(Icons.edit_outlined, color: colors.outline, size: 18), onPressed: () => _addOrEditTechnician(existing: t)),
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18), onPressed: () => _deleteTechnician(t)),
          ]),
        ).animate(delay: Duration(milliseconds: e.key * 50)).fadeIn().slideX(begin: 0.05, end: 0);
      }).toList(),
    );
  }

  Widget _buildPropertyList() {
    final colors = Theme.of(context).colorScheme;
    if (_isLoadingCrew) return const SizedBox.shrink();
    if (_properties.isEmpty) return _emptyBox(_isBn ? 'এখনো কোনো মেস প্রপার্টি যোগ করা হয়নি' : 'No mess properties added yet');
    return Column(
      children: _properties.asMap().entries.map((e) {
        final p = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.home_work_rounded, color: Color(0xFF8B5CF6), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.messName, style: TextStyle(color: colors.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.outline, fontSize: 11)),
            ])),
            Text(_isBn ? '${p.totalSeats} আসন' : '${p.totalSeats} seats', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ).animate(delay: Duration(milliseconds: e.key * 50)).fadeIn().slideX(begin: 0.05, end: 0);
      }).toList(),
    );
  }

  Widget _emptyBox(String msg) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
      child: Center(child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: colors.outline, fontSize: 13))),
    );
  }

  Widget _buildAgentCard() {
    final colors = Theme.of(context).colorScheme;
    final agent = _agentInfo!;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppGradients.primary(colors),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isBn ? 'এজেন্ট কোড' : 'Agent Code',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              _buildStatusBadge(agent.status),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _copyAgentCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    agent.code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.copy_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildEarningTile(_isBn ? 'মোট আয়' : 'Total Earnings', agent.totalEarnings, Icons.account_balance_wallet_outlined)),
              const SizedBox(width: 12),
              Expanded(child: _buildEarningTile(_isBn ? 'বকেয়া আয়' : 'Pending Earnings', agent.pendingEarnings, Icons.schedule_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.people_outline_rounded, color: Colors.white60, size: 16),
              const SizedBox(width: 6),
              Text(
                _isBn ? 'মোট রেফারেল: ${agent.totalReferrals}' : 'Total Referrals: ${agent.totalReferrals}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.08, end: 0);
  }

  Widget _buildEarningTile(String label, double amount, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white60, size: 14),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '৳${amount.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status.toLowerCase()) {
      case 'active':
        color = const Color(0xFF10B981);
        label = _isBn ? 'সক্রিয়' : 'Active';
        break;
      case 'suspended':
        color = const Color(0xFFEF4444);
        label = _isBn ? 'স্থগিত' : 'Suspended';
        break;
      default:
        color = const Color(0xFFF59E0B);
        label = _isBn ? 'অপেক্ষমাণ' : 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

}

// ── Benefit chip widget ───────────────────────────────────────────────────────

class _BenefitChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BenefitChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
