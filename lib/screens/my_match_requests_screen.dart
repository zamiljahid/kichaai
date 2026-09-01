import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/matchmaking_model.dart';
import '../services/matchmaking_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_button.dart';
import '../widgets/policy_agreement_checkbox.dart';
import 'payment_waiting_screen.dart';

const _kMeetFeeAmount = 100.0;

class MyMatchRequestsScreen extends StatefulWidget {
  const MyMatchRequestsScreen({super.key});

  @override
  State<MyMatchRequestsScreen> createState() => _MyMatchRequestsScreenState();
}

class _MyMatchRequestsScreenState extends State<MyMatchRequestsScreen> {
  final _matchmaking = MatchmakingService.instance;

  List<MatchRequestModel> _requests = [];
  bool _isLoading = true;
  String? _error;
  bool _isBn = true;

  // Which request id is currently expanded
  String? _expandedId;

  // Per-request response lists (lazy-loaded)
  final Map<String, List<MatchResponseModel>> _responses = {};
  final Map<String, bool> _responsesLoading = {};
  final Map<String, String?> _responsesError = {};

  // Per-response action lock
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
            _error = _isBn ? 'লগইন তথ্য পাওয়া যায়নি।' : 'Login information not found.';
            _isLoading = false;
          });
        }
        return;
      }
      final requests = await _matchmaking.listRequests(customerId: userId, limit: 50);
      if (mounted) setState(() { _requests = requests; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        final ex = ApiClient.mapError(e);
        setState(() { _error = ex.localized(_isBn); _isLoading = false; });
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
      final responses = await _matchmaking.listResponses(requestId);
      if (mounted) {
        setState(() {
          _responses[requestId] = responses;
          _responsesLoading[requestId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final ex = ApiClient.mapError(e);
        setState(() { _responsesError[requestId] = ex.localized(_isBn); _responsesLoading[requestId] = false; });
      }
    }
  }

  Future<void> _shortlist(String responseId) async {
    final key = '${responseId}_shortlist';
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      await _matchmaking.shortlistResponse(responseId);
      if (mounted) _showSuccess(_isBn ? 'সেবাদাতা শর্টলিস্ট করা হয়েছে।' : 'Provider shortlisted.');
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  // Award locks the pick in — if the response carried a quote, the request now owes
  // awardAmount with awardPaymentStatus:'pending'. Nothing is credited to the provider and no
  // chat opens until that's actually paid, so we chain straight into the payment flow here
  // instead of leaving the customer on an "awarded" card with no way to finish the booking.
  Future<void> _award(String requestId, String responseId) async {
    final key = '${responseId}_award';
    if (_saving.contains(key)) return;

    final confirmed = await _confirmAward();
    if (!confirmed) return;

    setState(() => _saving.add(key));
    try {
      final updated = await _matchmaking.awardResponse(responseId);
      if (!mounted) return;
      if (updated.awardAmount != null && updated.awardPaymentStatus == 'pending') {
        await _payForAward(requestId, updated.awardAmount!);
      } else {
        _showSuccess(_isBn ? 'কাজ পুরস্কার দেওয়া হয়েছে!' : 'Job awarded!');
      }
      await _loadRequests();
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  /// Re-entry point for a request that's already `awarded` but still `awardPaymentStatus:
  /// 'pending'` — e.g. the customer awarded it, backed out of the payment screen, and came back.
  Future<void> _resumePayment(MatchRequestModel req) async {
    if (req.awardAmount == null) return;
    await _payForAward(req.id, req.awardAmount!);
    await _loadRequests();
  }

  Future<void> _payForAward(String requestId, double amount) async {
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
    try {
      final transaction = await _matchmaking.initiateAwardPayment(requestId);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted) return;
      if (gatewayPageUrl == null) {
        _showError(_isBn ? 'পেমেন্ট শুরু করা যায়নি — আবার চেষ্টা করুন' : 'Could not start the payment — please try again');
        return;
      }
      final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'সেবাদাতার ফি' : 'Provider Fee',
          titleEn: 'Provider Fee',
          amount: amount,
          checkStatus: () async {
            try {
              final r = await _matchmaking.confirmAwardPayment(requestId);
              return r.awardPaymentStatus == 'paid' ? PaymentCheckStatus.completed : PaymentCheckStatus.pending;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(true),
          applyCoupon: (code) async {
            final t = await _matchmaking.initiateAwardPayment(requestId, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? amount};
          },
        ),
      ));
      if (mounted && result == true) _showSuccess(_isBn ? 'পেমেন্ট সম্পন্ন হয়েছে — চ্যাট এখন খোলা!' : 'Payment complete — chat is now open!');
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  // ── Pre-hire meet call ──────────────────────────────────────────

  Future<void> _requestMeet(String requestId, String responseId) async {
    final key = '${responseId}_meet';
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      await _matchmaking.requestMeet(responseId);
      if (mounted) _showSuccess(_isBn ? 'মিটিং-এর অনুরোধ পাঠানো হয়েছে' : 'Meet request sent');
      await _loadResponses(requestId);
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<void> _joinMeet(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _showError(_isBn ? 'মিটিং লিংক খোলা যায়নি' : 'Could not open the meeting link');
    } catch (_) {
      if (mounted) _showError(_isBn ? 'মিটিং লিংক খোলা যায়নি' : 'Could not open the meeting link');
    }
  }

  Future<void> _payMeetFee(String requestId, String responseId) async {
    if (!await PolicyAgreementCheckbox.confirm(context, isBn: _isBn)) return;
    try {
      final transaction = await _matchmaking.initiateMeetFeePayment(responseId);
      final gatewayPageUrl = transaction['gatewayPageUrl'] as String?;
      if (!mounted || gatewayPageUrl == null) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (waitingContext) => PaymentWaitingScreen(
          gatewayPageUrl: gatewayPageUrl,
          title: _isBn ? 'মিটিং ফি' : 'Meet Fee',
          titleEn: 'Meet Fee',
          amount: _kMeetFeeAmount,
          checkStatus: () async {
            try {
              await _matchmaking.confirmMeetFeePayment(responseId);
              return PaymentCheckStatus.completed;
            } catch (_) {
              return PaymentCheckStatus.pending;
            }
          },
          onConfirmed: () => Navigator.of(waitingContext).pop(),
          applyCoupon: (code) async {
            final t = await _matchmaking.initiateMeetFeePayment(responseId, couponCode: code);
            return {'gatewayPageUrl': t['gatewayPageUrl'], 'amount': double.tryParse('${t['amount']}') ?? _kMeetFeeAmount};
          },
        ),
      ));
      await _loadResponses(requestId);
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    }
  }

  /// Customer: cancel an open request — no provider gets awarded, responses stop.
  Future<void> _cancelRequest(String requestId) async {
    final colors = Theme.of(context).colorScheme;
    final key = '${requestId}_cancel';
    if (_saving.contains(key)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _isBn ? 'অনুরোধ বাতিল করুন' : 'Cancel request',
          style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700),
        ),
        content: Text(
          _isBn ? 'আপনি কি নিশ্চিতভাবে এই অনুরোধটি বাতিল করতে চান? সেবাদাতারা আর সাড়া দিতে পারবেন না।' : 'Are you sure you want to cancel this request? Providers will no longer be able to respond.',
          style: TextStyle(color: colors.outline, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_isBn ? 'না' : 'No', style: TextStyle(color: colors.outline)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _isBn ? 'হ্যাঁ, বাতিল করুন' : 'Yes, cancel',
              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
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
        _showSuccess(_isBn ? 'অনুরোধ বাতিল করা হয়েছে।' : 'Request cancelled.');
        await _loadRequests();
      }
    } catch (e) {
      if (mounted) _showError(ApiClient.mapError(e).localized(_isBn));
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<bool> _confirmAward() async {
    final colors = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _isBn ? 'কাজ পুরস্কার দিন' : 'Award the job',
          style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700),
        ),
        content: Text(
          _isBn ? 'পুরস্কার দেওয়ার পর পেমেন্ট করতে হবে — তারপর চ্যাট খুলবে।' : "After awarding you'll need to pay — the chat opens once that's done.",
          style: TextStyle(color: colors.outline, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_isBn ? 'বাতিল' : 'Cancel', style: TextStyle(color: colors.outline)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _isBn ? 'হ্যাঁ, পুরস্কার দিন' : 'Yes, award it',
              style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700),
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
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: colors.onPrimary, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showError(String msg) {
    final colors = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: colors.onPrimary)),
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
    final colors = Theme.of(context).colorScheme;
    switch (status.toLowerCase()) {
      case 'open':
      case 'in_negotiation':
        return colors.primary;
      case 'awarded':
        return colors.secondary;
      case 'booked':
        return const Color(0xFF22C55E);
      case 'cancelled':
      case 'expired':
      case 'closed':
      case 'draft':
      default:
        return colors.outline;
    }
  }

  String _statusLabel(String status) {
    final s = status.toLowerCase();
    if (_isBn) {
      switch (s) {
        case 'draft': return 'খসড়া';
        case 'open': return 'খোলা';
        case 'in_negotiation': return 'আলোচনা চলছে';
        case 'awarded': return 'পুরস্কৃত — পেমেন্ট বাকি';
        case 'booked': return 'বুক হয়েছে';
        case 'cancelled': return 'বাতিল';
        case 'expired': return 'মেয়াদ শেষ';
        case 'closed': return 'বন্ধ';
        default: return status;
      }
    }
    switch (s) {
      case 'draft': return 'Draft';
      case 'open': return 'Open';
      case 'in_negotiation': return 'In Discussion';
      case 'awarded': return 'Awarded — Payment Due';
      case 'booked': return 'Booked';
      case 'cancelled': return 'Cancelled';
      case 'expired': return 'Expired';
      case 'closed': return 'Closed';
      default: return status;
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return Scaffold(
      backgroundColor: colors.surfaceContainerHighest,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: colors.surface,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.outlineVariant, width: 1.5),
          ),
          child: Icon(Icons.arrow_back_ios_new_rounded, color: colors.onSurface, size: 16),
        ),
      ),
      title: Text(
        _isBn ? 'আমার অনুরোধ' : 'My Requests',
        style: TextStyle(color: colors.onSurface, fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildBody() {
    final colors = Theme.of(context).colorScheme;
    if (_isLoading) return Center(child: CircularProgressIndicator(color: colors.primary));
    if (_error != null) return _buildErrorState();
    if (_requests.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: colors.primary,
      backgroundColor: colors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _requests.length,
        itemBuilder: (_, i) => _buildRequestCard(_requests[i], i),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, color: colors.outline, size: 64),
          const SizedBox(height: 16),
          Text(_isBn ? 'কোনো অনুরোধ নেই' : 'No requests',
              style: TextStyle(color: colors.outline, fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildErrorState() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: colors.outline, size: 52),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.outline, fontSize: 14)),
            const SizedBox(height: 20),
            GlassButton(label: _isBn ? 'আবার চেষ্টা করুন' : 'Try again', onPressed: _loadRequests, width: 200),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(MatchRequestModel req, int index) {
    final colors = Theme.of(context).colorScheme;
    final isExpanded = _expandedId == req.id;
    final statusColor = _statusColor(req.status);
    final needsPayment = req.status.toLowerCase() == 'awarded' && req.awardPaymentStatus == 'pending';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded ? colors.primary.withOpacity(0.5) : colors.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: () => _toggleExpand(req.id),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            req.title.isNotEmpty ? req.title : (_isBn ? 'শিরোনাম নেই' : 'No title'),
                            style: TextStyle(color: colors.onSurface, fontSize: 15, fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            _buildStatusBadge(req.status, statusColor),
                            const SizedBox(width: 8),
                            Text(_formatDate(req.createdAt), style: TextStyle(color: colors.outline, fontSize: 11)),
                          ]),
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
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: colors.outline, size: 24),
                    ),
                  ],
                ),
              ),
            ),

            if (needsPayment)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SizedBox(
                  height: 44,
                  child: GlassButton(
                    label: _isBn
                        ? 'পেমেন্ট সম্পন্ন করুন (৳ ${req.awardAmount?.toStringAsFixed(0)})'
                        : 'Complete Payment (৳ ${req.awardAmount?.toStringAsFixed(0)})',
                    onPressed: () => _resumePayment(req),
                  ),
                ),
              ),

            if (isExpanded) _buildResponsesSection(req),

            if (isExpanded && req.status.toLowerCase() == 'open')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _saving.contains('${req.id}_cancel') ? null : () => _cancelRequest(req.id),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 16),
                    label: Text(
                      _isBn ? 'অনুরোধ বাতিল করুন' : 'Cancel request',
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: 50 * index)).fadeIn(duration: 300.ms).slideY(begin: 0.06);
  }

  Widget _buildMeetSection(String requestId, MatchResponseModel resp) {
    final colors = Theme.of(context).colorScheme;
    final meetKey = '${resp.id}_meet';
    final isSaving = _saving.contains(meetKey);

    if (resp.meetLink != null && resp.meetFeeStatus == 'paid') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _joinMeet(resp.meetLink!),
          icon: const Icon(Icons.video_camera_front_rounded, color: Color(0xFF10B981), size: 16),
          label: Text(_isBn ? 'মিটিং-এ যোগ দিন' : 'Join the meet', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF10B981)), padding: const EdgeInsets.symmetric(vertical: 12)),
        ),
      );
    }
    if (resp.meetLink != null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _payMeetFee(requestId, resp.id),
          style: OutlinedButton.styleFrom(side: BorderSide(color: colors.primary), padding: const EdgeInsets.symmetric(vertical: 12)),
          child: Text(_isBn ? '৳১০০ পে করে মিটিং-এ যোগ দিন' : 'Pay ৳100 to join the meet', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700)),
        ),
      );
    }
    if (resp.meetRequestedAt != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.outline.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: Text(_isBn ? 'সেবাদাতার সাড়ার অপেক্ষায়...' : 'Waiting for the provider to accept...', style: TextStyle(color: colors.outline, fontSize: 12.5)),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: isSaving ? null : () => _requestMeet(requestId, resp.id),
        icon: Icon(Icons.video_call_outlined, color: colors.primary, size: 16),
        label: Text(_isBn ? 'আগে ভিডিও কলে কথা বলতে চান?' : 'Want to talk on video first?', style: TextStyle(color: colors.primary, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildBudgetRow(double? min, double? max) {
    final colors = Theme.of(context).colorScheme;
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
    return Row(children: [
      Icon(Icons.account_balance_wallet_rounded, color: colors.outline, size: 13),
      const SizedBox(width: 4),
      Text(budgetText, style: TextStyle(color: colors.outline, fontSize: 12)),
    ]);
  }

  Widget _buildResponsesSection(MatchRequestModel req) {
    final colors = Theme.of(context).colorScheme;
    final loading = _responsesLoading[req.id] ?? false;
    final error = _responsesError[req.id];
    final responses = _responses[req.id];
    final alreadyAwarded = req.awardedResponseId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: colors.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 16)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.people_alt_rounded, color: colors.outline, size: 16),
            const SizedBox(width: 6),
            Text(_isBn ? 'সেবাদাতাদের প্রস্তাব' : 'Provider offers',
                style: TextStyle(color: colors.outline, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 10),
        if (loading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: colors.primary, strokeWidth: 2)),
          )
        else if (error != null)
          _buildResponsesError(error, req.id)
        else if (responses == null || responses.isEmpty)
          _buildNoResponses()
        else
          ...responses.asMap().entries.map(
                (entry) => _buildResponseCard(req.id, entry.value, entry.key, canAct: alreadyAwarded == null),
              ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildNoResponses() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Center(
        child: Text(_isBn ? 'এখনো কোনো প্রস্তাব আসেনি' : 'No offers yet',
            style: TextStyle(color: colors.outline, fontSize: 13)),
      ),
    );
  }

  Widget _buildResponsesError(String error, String requestId) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(children: [
        Text(error, style: TextStyle(color: colors.outline, fontSize: 13)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _loadResponses(requestId),
          child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again',
              style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _buildResponseCard(String requestId, MatchResponseModel resp, int index, {required bool canAct}) {
    final colors = Theme.of(context).colorScheme;
    final shortlistKey = '${resp.id}_shortlist';
    final awardKey = '${resp.id}_award';
    final isSaving = _saving.contains(shortlistKey) || _saving.contains(awardKey);
    final isShortlisting = _saving.contains(shortlistKey);
    final isAwarding = _saving.contains(awardKey);
    final name = (resp.providerNameSnapshot?.trim().isNotEmpty ?? false)
        ? resp.providerNameSnapshot!
        : (_isBn ? 'অজানা সেবাদাতা' : 'Unknown provider');
    final isSelected = resp.status.toLowerCase() == 'selected';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? colors.primary : colors.outlineVariant, width: isSelected ? 1.5 : 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(10)),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name.characters.first.toUpperCase() : (_isBn ? 'স' : '?'),
                      style: TextStyle(color: colors.onPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(children: [
                        if (resp.quotedAmount != null)
                          Text('৳ ${resp.quotedAmount!.toStringAsFixed(0)}',
                              style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                        if (resp.providerAvgRatingSnapshot != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 14),
                          const SizedBox(width: 2),
                          Text(resp.providerAvgRatingSnapshot!.toStringAsFixed(1),
                              style: TextStyle(color: colors.outline, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ]),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: colors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(_isBn ? 'নির্বাচিত' : 'Selected',
                        style: TextStyle(color: colors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            if (resp.coverMessage != null && resp.coverMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.outlineVariant, width: 1),
                ),
                child: Text(resp.coverMessage!, style: TextStyle(color: colors.outline, fontSize: 13, height: 1.5)),
              ),
            ],
            if (canAct) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: GlassButton(
                      label: _isBn ? 'শর্টলিস্ট করুন' : 'Shortlist',
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
                      label: _isBn ? 'পুরস্কার দিন' : 'Award',
                      onPressed: isSaving ? null : () => _award(requestId, resp.id),
                      isLoading: isAwarding,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _buildMeetSection(requestId, resp),
            ],
          ],
        ),
      ).animate(delay: Duration(milliseconds: 60 * index)).fadeIn(duration: 250.ms).slideY(begin: 0.04),
    );
  }
}
