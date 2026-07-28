import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import 'notification_preferences_screen.dart';

// ── Notification Bell Widget ─────────────────────────────────────────────────

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unreadCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchCount();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _fetchCount());
    // Foreground pushes refresh the bell immediately instead of waiting up to
    // 60s for the timer to tick.
    PushService.instance.foregroundPushTick.addListener(_fetchCount);
  }

  @override
  void dispose() {
    _timer?.cancel();
    PushService.instance.foregroundPushTick.removeListener(_fetchCount);
    super.dispose();
  }

  Future<void> _fetchCount() async {
    final userId = await ApiClient.getUserId();
    if (userId == null || userId.isEmpty) return;
    final count = await NotificationService.instance.getUnreadCount(userId);
    if (mounted) setState(() => _unreadCount = count);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationListScreen()),
        );
        _fetchCount();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined, color: AppColors.textPrimary, size: 20),
                if (_unreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Notification List Screen ─────────────────────────────────────────────────

class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  final _notifications = <NotificationModel>[];
  final _scrollController = ScrollController();
  String? _userId;
  bool _isLoading = true;
  bool _hasMore = true;
  int _offset = 0;
  static const _limit = 20;
  bool _isBn = true;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _userId = await ApiClient.getUserId();
    await _loadNotifications(reset: true);
  }

  Future<void> _loadNotifications({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _offset = 0;
        _notifications.clear();
        _hasMore = true;
      });
    }
    try {
      final items = await NotificationService.instance.listNotifications(
        userId: _userId,
        limit: _limit,
        offset: _offset,
      );
      if (mounted) {
        setState(() {
          _notifications.addAll(items);
          _offset += items.length;
          _hasMore = items.length == _limit;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadNotifications();
    }
  }

  Future<void> _markRead(NotificationModel n) async {
    if (n.isRead) return;
    await NotificationService.instance.markAsRead([n.id]);
    if (mounted) {
      final idx = _notifications.indexWhere((x) => x.id == n.id);
      if (idx >= 0) {
        setState(() => _notifications[idx] = n.copyWith(isRead: true));
      }
    }
  }

  /// Chat pushes carry no jobId — a bare tap stays on the list (upstream
  /// PushService.openTarget opens the list in that case, which is a no-op here).
  Future<void> _openTarget(NotificationModel n) async {
    final meta = n.metadata;
    final jobId = meta?['jobId'] as String?;
    if (meta == null || jobId == null || jobId.isEmpty) return;
    await PushService.instance.openTarget(meta);
  }

  Future<void> _markAllRead() async {
    final unread = _notifications.where((n) => !n.isRead).map((n) => n.id).toList();
    if (unread.isEmpty) return;
    await NotificationService.instance.markAsRead(unread);
    if (mounted) {
      setState(() {
        for (int i = 0; i < _notifications.length; i++) {
          if (!_notifications[i].isRead) {
            _notifications[i] = _notifications[i].copyWith(isRead: true);
          }
        }
      });
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (_isBn) {
      if (diff.inSeconds < 60) return 'এইমাত্র';
      if (diff.inMinutes < 60) return '${diff.inMinutes} মিনিট আগে';
      if (diff.inHours < 24) return '${diff.inHours} ঘন্টা আগে';
      if (diff.inDays < 7) return '${diff.inDays} দিন আগে';
    } else {
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours} hr ago';
      if (diff.inDays < 7) return '${diff.inDays} d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'job_update':
        return Icons.work_outline_rounded;
      case 'payment':
        return Icons.payment_rounded;
      case 'marketing':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'job_update':
        return const Color(0xFF3B82F6);
      case 'payment':
        return const Color(0xFF10B981);
      case 'marketing':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF8B5CF6);
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
        title: Text(_isBn ? 'নোটিফিকেশন' : 'Notifications', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: Text(_isBn ? 'সব পড়া হয়েছে' : 'Mark all read', style: const TextStyle(color: AppColors.deepBlue, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.textMuted, size: 20),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPreferencesScreen())),
            tooltip: _isBn ? 'সেটিংস' : 'Settings',
          ),
        ],
      ),
      body: _isLoading && _notifications.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
          : _notifications.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: AppColors.deepBlue,
                  backgroundColor: AppColors.bgMid,
                  onRefresh: () => _loadNotifications(reset: true),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _notifications.length + (_hasMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _notifications.length) {
                        return const Center(child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(color: AppColors.deepBlue, strokeWidth: 2),
                        ));
                      }
                      return _buildTile(_notifications[i], i);
                    },
                  ),
                ),
    );
  }

  Widget _buildTile(NotificationModel n, int index) {
    final color = _typeColor(n.type);
    return Dismissible(
      key: Key(n.id),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.done_all_rounded, color: Color(0xFF10B981)),
      ),
      onDismissed: (_) => _markRead(n),
      child: GestureDetector(
        onTap: () {
          _markRead(n);
          _openTarget(n);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.bgMid,
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(
                color: n.isRead ? Colors.transparent : color,
                width: 3,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_typeIcon(n.type), color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            n.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _relativeTime(n.createdAt),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    if (!n.isRead)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: index * 40)).slideY(begin: 0.1, end: 0),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text(_isBn ? 'কোনো নোটিফিকেশন নেই' : 'No notifications', style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
        ],
      ),
    );
  }
}
