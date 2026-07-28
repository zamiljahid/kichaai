import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/network/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_button.dart';

// ── Local models ──────────────────────────────────────────────────

class _MatchRequest {
  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final double? budgetMin;
  final double? budgetMax;

  const _MatchRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.budgetMin,
    this.budgetMax,
  });

  factory _MatchRequest.fromJson(Map<String, dynamic> json) => _MatchRequest(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'open',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        budgetMin: (json['budgetMin'] as num?)?.toDouble(),
        budgetMax: (json['budgetMax'] as num?)?.toDouble(),
      );
}

class _ProviderResponse {
  final String id;
  final String providerId;
  final String providerName;
  final double? priceOffered;
  final String? note;

  const _ProviderResponse({
    required this.id,
    required this.providerId,
    required this.providerName,
    this.priceOffered,
    this.note,
  });

  factory _ProviderResponse.fromJson(Map<String, dynamic> json) => _ProviderResponse(
        id: json['id'] as String? ?? '',
        providerId: json['providerId'] as String? ?? '',
        providerName: json['providerName'] as String? ??
            json['providerFullName'] as String? ??
            json['name'] as String? ??
            'অজানা সেবাদাতা',
        priceOffered: (json['priceOffered'] as num?)?.toDouble() ??
            (json['price'] as num?)?.toDouble() ??
            (json['amount'] as num?)?.toDouble(),
        note: json['note'] as String? ?? json['message'] as String?,
      );
}

// ── Main screen ───────────────────────────────────────────────────

class MyMatchRequestsScreen extends StatefulWidget {
  const MyMatchRequestsScreen({super.key});

  @override
  State<MyMatchRequestsScreen> createState() => _MyMatchRequestsScreenState();
}

class _MyMatchRequestsScreenState extends State<MyMatchRequestsScreen> {
  List<_MatchRequest> _requests = [];
  bool _isLoading = true;
  String? _error;

  // Which request id is currently expanded
  String? _expandedId;

  // Per-request response lists (lazy-loaded)
  final Map<String, List<_ProviderResponse>> _responses = {};
  final Map<String, bool> _responsesLoading = {};
  final Map<String, String?> _responsesError = {};

  // Per-provider action lock: key = "${requestId}_${providerId}"
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  // ── Data fetching ─────────────────────────────────────────────

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = await ApiClient.getUserId();
      if (userId == null || userId.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'লগইন তথ্য পাওয়া যায়নি।';
            _isLoading = false;
          });
        }
        return;
      }

      final response = await ApiClient.instance.dio.get(
        '/matchmaking/requests',
        queryParameters: {'customerId': userId},
      );

      final raw = response.data;
      List<dynamic> list = [];
      if (raw is List) {
        list = raw;
      } else if (raw is Map && raw['data'] is List) {
        list = raw['data'] as List;
      } else if (raw is Map && raw['requests'] is List) {
        list = raw['requests'] as List;
      }

      if (mounted) {
        setState(() {
          _requests = list
              .whereType<Map<String, dynamic>>()
              .map(_MatchRequest.fromJson)
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final ex = ApiClient.mapError(e);
        setState(() {
          _error = ex.messageBn;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadResponses(String requestId) async {
    if (_responsesLoading[requestId] == true) return;
    setState(() {
      _responsesLoading[requestId] = true;
      _responsesError[requestId] = null;
    });
    try {
      final response = await ApiClient.instance.dio
          .get('/matchmaking/requests/$requestId/responses');

      final raw = response.data;
      List<dynamic> list = [];
      if (raw is List) {
        list = raw;
      } else if (raw is Map && raw['data'] is List) {
        list = raw['data'] as List;
      } else if (raw is Map && raw['responses'] is List) {
        list = raw['responses'] as List;
      }

      if (mounted) {
        setState(() {
          _responses[requestId] = list
              .whereType<Map<String, dynamic>>()
              .map(_ProviderResponse.fromJson)
              .toList();
          _responsesLoading[requestId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final ex = ApiClient.mapError(e);
        setState(() {
          _responsesError[requestId] = ex.messageBn;
          _responsesLoading[requestId] = false;
        });
      }
    }
  }

  Future<void> _shortlist(String responseId) async {
    final key = '${responseId}_shortlist';
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      // Shortlist/award target the RESPONSE id, not the request/provider.
      await ApiClient.instance.dio.post('/matchmaking/responses/$responseId/shortlist');
      if (mounted) _showSuccess('সেবাদাতা শর্টলিস্ট করা হয়েছে।');
    } catch (e) {
      if (mounted) {
        final ex = ApiClient.mapError(e);
        _showError(ex.messageBn);
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<void> _award(String responseId) async {
    final key = '${responseId}_award';
    if (_saving.contains(key)) return;

    final confirmed = await _confirmAward();
    if (!confirmed) return;

    setState(() => _saving.add(key));
    try {
      await ApiClient.instance.dio.post('/matchmaking/responses/$responseId/award');
      if (mounted) {
        _showSuccess('কাজ পুরস্কার দেওয়া হয়েছে!');
        await _loadRequests();
      }
    } catch (e) {
      if (mounted) {
        final ex = ApiClient.mapError(e);
        _showError(ex.messageBn);
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  /// Customer: cancel an open request — no provider gets awarded, responses stop.
  Future<void> _cancelRequest(String requestId) async {
    final key = '${requestId}_cancel';
    if (_saving.contains(key)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'অনুরোধ বাতিল করুন',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'আপনি কি নিশ্চিতভাবে এই অনুরোধটি বাতিল করতে চান? সেবাদাতারা আর সাড়া দিতে পারবেন না।',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('না', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'হ্যাঁ, বাতিল করুন',
              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving.add(key));
    try {
      await ApiClient.instance.dio.patch(
        '/matchmaking/requests/$requestId/status',
        data: {'status': 'cancelled'},
      );
      if (mounted) {
        _showSuccess('অনুরোধ বাতিল করা হয়েছে।');
        await _loadRequests();
      }
    } catch (e) {
      if (mounted) {
        final ex = ApiClient.mapError(e);
        _showError(ex.messageBn);
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<bool> _confirmAward() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'কাজ পুরস্কার দিন',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'আপনি কি নিশ্চিতভাবে এই সেবাদাতাকে কাজটি পুরস্কার দিতে চান?',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('বাতিল', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'হ্যাঁ, পুরস্কার দিন',
              style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Toggle expand ─────────────────────────────────────────────

  void _toggleExpand(String requestId) {
    if (_expandedId == requestId) {
      setState(() => _expandedId = null);
      return;
    }
    setState(() => _expandedId = requestId);
    if (!_responses.containsKey(requestId)) {
      _loadResponses(requestId);
    }
  }

  // ── Snackbars ─────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.ivory)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return AppColors.deepBlue;
      case 'matched':
        return const Color(0xFF22C55E);
      case 'closed':
      case 'awarded':
        return AppColors.textMuted;
      default:
        return AppColors.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return 'খোলা';
      case 'matched':
        return 'মিলেছে';
      case 'closed':
        return 'বন্ধ';
      case 'awarded':
        return 'পুরস্কৃত';
      default:
        return status;
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bgMid,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorder, width: 1.5),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 16),
        ),
      ),
      title: const Text(
        'আমার অনুরোধ',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.deepBlue),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_requests.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _requests.length,
        itemBuilder: (_, i) => _buildRequestCard(_requests[i], i),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          const Text(
            'কোনো অনুরোধ নেই',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 52),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            GlassButton(
              label: 'আবার চেষ্টা করুন',
              onPressed: _loadRequests,
              width: 200,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(_MatchRequest req, int index) {
    final isExpanded = _expandedId == req.id;
    final statusColor = _statusColor(req.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded ? AppColors.deepBlue.withOpacity(0.5) : AppColors.glassBorder,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row — tap to expand
            GestureDetector(
              onTap: () => _toggleExpand(req.id),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status indicator dot
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
                      ),
                      child: Icon(Icons.handshake_rounded, color: statusColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req.title.isNotEmpty ? req.title : 'শিরোনাম নেই',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildStatusBadge(req.status, statusColor),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(req.createdAt),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          if (req.budgetMin != null || req.budgetMax != null) ...[
                            const SizedBox(height: 5),
                            _buildBudgetRow(req.budgetMin, req.budgetMax),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Expanded responses section
            if (isExpanded) _buildResponsesSection(req),

            // Cancel — only while the request is still open (awarded/closed
            // requests are past the point of cancelling).
            if (isExpanded && req.status.toLowerCase() == 'open')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _saving.contains('${req.id}_cancel')
                        ? null
                        : () => _cancelRequest(req.id),
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFFEF4444), size: 16),
                    label: const Text(
                      'অনুরোধ বাতিল করুন',
                      style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: 50 * index)).fadeIn(duration: 300.ms).slideY(begin: 0.06);
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBudgetRow(double? min, double? max) {
    String budgetText;
    if (min != null && max != null && min != max) {
      budgetText = '৳ ${min.toStringAsFixed(0)} – ${max.toStringAsFixed(0)}';
    } else if (min != null) {
      budgetText = '৳ ${min.toStringAsFixed(0)}';
    } else if (max != null) {
      budgetText = '৳ ${max.toStringAsFixed(0)}';
    } else {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        const Icon(Icons.account_balance_wallet_rounded, color: AppColors.textMuted, size: 13),
        const SizedBox(width: 4),
        Text(
          budgetText,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildResponsesSection(_MatchRequest req) {
    final loading = _responsesLoading[req.id] ?? false;
    final error = _responsesError[req.id];
    final responses = _responses[req.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 1,
          color: AppColors.glassBorder,
          margin: const EdgeInsets.symmetric(horizontal: 16),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: AppColors.textMuted, size: 16),
              const SizedBox(width: 6),
              const Text(
                'সেবাদাতাদের প্রস্তাব',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.deepBlue, strokeWidth: 2)),
          )
        else if (error != null)
          _buildResponsesError(error, req.id)
        else if (responses == null || responses.isEmpty)
          _buildNoResponses()
        else
          ...responses.asMap().entries.map(
                (entry) => _buildResponseCard(req.id, entry.value, entry.key),
              ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildNoResponses() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Center(
        child: Text(
          'এখনো কোনো প্রস্তাব আসেনি',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildResponsesError(String error, String requestId) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        children: [
          Text(error, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _loadResponses(requestId),
            child: const Text(
              'আবার চেষ্টা করুন',
              style: TextStyle(color: AppColors.deepBlue, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseCard(String requestId, _ProviderResponse resp, int index) {
    final shortlistKey = '${resp.id}_shortlist';
    final awardKey = '${resp.id}_award';
    final isSaving = _saving.contains(shortlistKey) || _saving.contains(awardKey);
    final isShortlisting = _saving.contains(shortlistKey);
    final isAwarding = _saving.contains(awardKey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder, width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider info row
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.blueGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      resp.providerName.isNotEmpty
                          ? resp.providerName.characters.first.toUpperCase()
                          : 'স',
                      style: const TextStyle(
                        color: AppColors.ivory,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resp.providerName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (resp.priceOffered != null)
                        Text(
                          '৳ ${resp.priceOffered!.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.deepBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Note
            if (resp.note != null && resp.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgDark.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.glassBorder, width: 1),
                ),
                child: Text(
                  resp.note!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: GlassButton(
                      label: 'শর্টলিস্ট করুন',
                      isOutlined: true,
                      onPressed: isSaving ? null : () => _shortlist(resp.id),
                      isLoading: isShortlisting,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: GlassButton(
                      label: 'পুরস্কার দিন',
                      onPressed: isSaving ? null : () => _award(resp.id),
                      isLoading: isAwarding,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate(delay: Duration(milliseconds: 60 * index)).fadeIn(duration: 250.ms).slideY(begin: 0.04),
    );
  }
}
