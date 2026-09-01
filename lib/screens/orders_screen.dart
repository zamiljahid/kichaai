import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/dispatch_model.dart';
import '../models/groceries_model.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../services/groceries_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_card.dart';
import 'job_tracking_screen.dart';
import 'my_match_requests_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<JobModel> _jobs = [];
  List<GroceryOrderModel> _groceryOrders = [];
  List<CancelReview> _cancelReviews = [];
  bool _reviewDialogOpen = false;
  bool _isLoading = true;
  String? _error;
  bool _isBn = true; // set from LanguageNotifier in build() so helpers can read it

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final user = await AuthService.instance.getCurrentUser();
      final uid = user.id;
      List<JobModel> jobs = [];
      List<GroceryOrderModel> groceryOrders = [];
      List<CancelReview> reviews = [];
      await Future.wait([
        DispatchService.instance.listJobs(customerId: uid).then((v) => jobs = v),
        GroceriesService.instance.listOrders(userId: uid).then((v) => groceryOrders = v),
        DispatchService.instance.getMyCancelReviews().then((v) => reviews = v).catchError((_) => <CancelReview>[]),
      ]);
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _groceryOrders = groceryOrders;
          _cancelReviews = reviews;
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptCancelReview());
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // A provider cancelled a committed job without confirming start — ask whether they still
  // did the work off-app. "Yes" charges the provider the commission (anti-bypass).
  Future<void> _maybePromptCancelReview() async {
    final colors = Theme.of(context).colorScheme;
    if (_reviewDialogOpen || _cancelReviews.isEmpty || !mounted) return;
    final r = _cancelReviews.first;
    _reviewDialogOpen = true;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isBn ? 'কাজটি কি হয়েছিল?' : 'Was the job done?',
            style: TextStyle(color: colors.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          _isBn
              ? '${r.providerName ?? 'প্রোভাইডার'} আপনার "${r.title}" কাজটি বাতিল করেছে। '
                  'সে কি তবুও কাজটি করে দিয়েছিল?'
              : '${r.providerName ?? 'The provider'} cancelled your "${r.title}" job. '
                  'Did they still do the work?',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isBn ? 'না, করেনি' : 'No', style: TextStyle(color: colors.outline)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isBn ? 'হ্যাঁ, করেছিল' : 'Yes, they did',
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    _reviewDialogOpen = false;
    if (answer == null || !mounted) return;
    try {
      await DispatchService.instance.answerCancelReview(r.jobId, answer);
      _loadData(); // refetch — answered review drops off; next one (if any) will prompt
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isBn ? 'উত্তর পাঠাতে সমস্যা হয়েছে' : 'Could not submit answer',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _isBn = context.watch<LanguageNotifier>().isBengali;
    return RefreshIndicator(
      onRefresh: _loadData,
      color: colors.primary,
      backgroundColor: colors.surface,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(_isBn ? 'আমার অর্ডার' : 'My Orders', style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700)),
            floating: true, snap: true, backgroundColor: Colors.transparent,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.outlineVariant, width: 1.5),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(gradient: AppGradients.primary(colors), borderRadius: BorderRadius.circular(10)),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: const EdgeInsets.all(3),
                        dividerColor: Colors.transparent,
                        labelColor: colors.onPrimary,
                        unselectedLabelColor: colors.outline,
                        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        tabs: [
                          Tab(text: _isBn ? 'সেবা' : 'Services'),
                          Tab(text: _isBn ? 'গ্রোসারি' : 'Groceries'),
                          Tab(text: _isBn ? 'অনুরোধ' : 'Requests'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 100), child: Center(child: CircularProgressIndicator(color: colors.primary))))
          else if (_error != null)
            SliverToBoxAdapter(child: _buildError())
          else
            SliverFillRemaining(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildJobsTab(),
                  _buildGroceryTab(),
                  const MyMatchRequestsScreen(),
                ],
               ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildJobsTab() {
    if (_jobs.isEmpty) return _buildEmpty(_isBn ? 'কোনো সেবার অনুরোধ নেই' : 'No service requests', Icons.work_off_rounded);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _jobs.length,
      itemBuilder: (_, i) => _buildJobCard(_jobs[i], i),
    );
  }

  Widget _buildJobCard(JobModel job, int index) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = _statusColor(job.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => JobTrackingScreen(jobId: job.id),
        )),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
                ),
                child: Icon(_statusIcon(job.status), color: statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job.title, style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(_serviceKindLabel(job.serviceKind), style: TextStyle(color: colors.outline, fontSize: 12)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(job.statusBn(), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(_formatDate(job.createdAt), style: TextStyle(color: colors.outline, fontSize: 10)),
              ]),
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: 40 * index)).fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }

  Widget _buildGroceryTab() {
    if (_groceryOrders.isEmpty) return _buildEmpty(_isBn ? 'কোনো গ্রোসারি অর্ডার নেই' : 'No grocery orders', Icons.shopping_basket_outlined);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _groceryOrders.length,
      itemBuilder: (_, i) => _buildGroceryOrderCard(_groceryOrders[i], i),
    );
  }

  Widget _buildGroceryOrderCard(GroceryOrderModel order, int index) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: AppGradients.primary(colors),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.shopping_basket_rounded, color: colors.onPrimary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${order.id.substring(0, 8).toUpperCase()}', style: TextStyle(color: colors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                Text('${order.items.length} ${_isBn ? 'পণ্য' : 'items'}', style: TextStyle(color: colors.outline, fontSize: 12)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('৳ ${order.totalAmount.toStringAsFixed(0)}', style: TextStyle(color: colors.primary, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: colors.outlineVariant)),
                child: Text(order.status, style: TextStyle(color: colors.outline, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ]),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: 40 * index)).fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }

  Widget _buildEmpty(String message, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: colors.outline, size: 56),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: colors.outline, fontSize: 14)),
      ]),
    );
  }

  Widget _buildError() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, color: colors.outline, size: 48),
          const SizedBox(height: 12),
          Text(_isBn ? 'তথ্য লোড হয়নি' : 'Failed to load', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 16),
          GestureDetector(onTap: _loadData, child: Text(_isBn ? 'আবার চেষ্টা করুন' : 'Try again', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  Color _statusColor(String status) {
    final colors = Theme.of(context).colorScheme;
    switch (status) {
      case 'searching': return colors.primary;
      case 'assigned': case 'accepted': return const Color(0xFF8B5CF6);
      case 'arriving': return const Color(0xFF06B6D4);
      case 'in_progress': return const Color(0xFF10B981);
      case 'completed': return const Color(0xFF22C55E);
      case 'cancelled': return const Color(0xFFEF4444);
      default: return colors.outline;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'searching': return Icons.search_rounded;
      case 'assigned': case 'accepted': return Icons.person_rounded;
      case 'arriving': return Icons.near_me_rounded;
      case 'in_progress': return Icons.build_rounded;
      case 'completed': return Icons.check_circle_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      default: return Icons.info_rounded;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _serviceKindLabel(String kind) {
    const bn = {
      'technician': 'টেকনিশিয়ান', 'task_runner': 'কাজের লোক', 'caregiver': 'কেয়ারগিভার',
      'lawyer': 'আইনজীবী', 'photographer': 'ফটোগ্রাফার', 'cinematographer': 'সিনেমাটোগ্রাফার',
      'makeup_artist': 'মেকআপ আর্টিস্ট', 'scrap_collection': 'স্ক্র্যাপ',
      'cook': 'রাঁধুনি', 'commute': 'রাইড',
    };
    const en = {
      'technician': 'Technician', 'task_runner': 'Task Runner', 'caregiver': 'Caregiver',
      'lawyer': 'Lawyer', 'photographer': 'Photographer', 'cinematographer': 'Cinematographer',
      'makeup_artist': 'Makeup Artist', 'scrap_collection': 'Scrap',
      'cook': 'Cook', 'commute': 'Ride',
    };
    return (_isBn ? bn[kind] : en[kind]) ?? kind;
  }
}
