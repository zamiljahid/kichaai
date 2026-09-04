import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_gradients.dart';
import '../widgets/glass_card.dart';
import 'chat_screen.dart';
import '../widgets/custom_bottom_nav.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<ThreadModel> _threads = [];
  bool _isLoading = true;
  String? _error;
  String _currentUserId = '';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = await AuthService.instance.getCurrentUser();
      final threads =
          await MessagingService.instance.listThreads(user.id);
      if (mounted) {
        setState(() {
          _currentUserId = user.id;
          _threads = threads;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<ThreadModel> get _filteredThreads {
    if (_searchQuery.isEmpty) return _threads;
    final q = _searchQuery.toLowerCase();
    return _threads.where((t) {
      final name =
          t.otherParticipantName(_currentUserId).toLowerCase();
      final lastMsg = t.lastMessagePreview?.toLowerCase() ?? '';
      return name.contains(q) || lastMsg.contains(q);
    }).toList();
  }

  void _openThread(ThreadModel thread) {
    final otherName = thread.otherParticipantName(_currentUserId);
    final otherOnline = thread.participants
        .where((p) => p.userId != _currentUserId)
        .any((p) => p.isOnline);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          threadId: thread.id,
          currentUserId: _currentUserId,
          participantName: otherName,
          isParticipantOnline: otherOnline,
        ),
      ),
    ).then((_) => _loadData()); // refresh unread count on return
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);
    return RefreshIndicator(
      onRefresh: _loadData,
      color: colors.primary,
      backgroundColor: colors.surface,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(strings.messages),
            floating: true,
            snap: true,
            backgroundColor: Colors.transparent,
            foregroundColor: colors.onSurface,
            // foregroundColor reaches the icons but NOT the title — a non-null
            // AppBarTheme.titleTextStyle (this app defines one, in onPrimary)
            // wins outright. See profile_screen.dart for the full precedence.
            titleTextStyle: Theme.of(context)
                .appBarTheme
                .titleTextStyle
                ?.copyWith(color: colors.onSurface),
            // This bar is transparent over the light canvas, so it must not
            // inherit the theme's primary-bar rounding either.
            shape: const RoundedRectangleBorder(),
            actions: [
              // Global language toggle is in the nav bar — no per-screen chip.
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                onPressed: () {},
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildSearch(strings)),
          if (_isLoading)
            _buildSkeletonList()
          else if (_error != null)
            SliverToBoxAdapter(child: _buildErrorState(strings))
          else if (_filteredThreads.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(strings))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _buildThreadItem(_filteredThreads[i], i, strings),
                childCount: _filteredThreads.length,
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomNavClearance(context))),
        ],
      ),
    );
  }

  Widget _buildSearch(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            style: TextStyle(color: colors.onSurface),
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: context.read<LanguageNotifier>().isBengali
                  ? 'বার্তা খুঁজুন...'
                  : 'Search messages...',
              prefixIcon:
                  Icon(Icons.search_rounded, color: colors.outline),
            ),
          ),
        ),
      ),
    ).animate().fadeIn();
  }

  // ── Skeleton ──────────────────────────────────────────────────────

  Widget _buildSkeletonList() {
    final colors = Theme.of(context).colorScheme;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, __) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            height: 74,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant, width: 1.5),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 600.ms),
        ),
        childCount: 4,
      ),
    );
  }

  // ── Error / empty ─────────────────────────────────────────────────

  Widget _buildErrorState(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: GlassCard(
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded,
                color: colors.outline, size: 48),
            const SizedBox(height: 12),
            Text(strings.errNetwork,
                style:
                    TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppGradients.primary(colors),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(strings.retry,
                    style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 64, color: colors.outline),
          const SizedBox(height: 16),
          Text(strings.noMessages,
              style: TextStyle(color: colors.outline, fontSize: 16)),
        ],
      ),
    );
  }

  // ── Thread item ───────────────────────────────────────────────────

  Widget _buildThreadItem(
      ThreadModel thread, int index, AppStrings strings) {
    final colors = Theme.of(context).colorScheme;
    final hasUnread = thread.unreadCount > 0;
    final otherName = thread.otherParticipantName(_currentUserId);
    final isOnline = thread.participants
        .where((p) => p.userId != _currentUserId)
        .any((p) => p.isOnline);
    final lastMsg = thread.lastMessagePreview ?? '';
    final timeStr = _formatThreadTime(
        thread.lastMessageAt ?? thread.createdAt, context.read<LanguageNotifier>().isBengali);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderColor:
            hasUnread ? colors.primary.withValues(alpha: 0.20) : colors.outlineVariant,
        glassColor: hasUnread ? colors.primary.withValues(alpha: 0.08) : colors.surface,
        onTap: () => _openThread(thread),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary(colors),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      otherName.isNotEmpty
                          ? otherName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: colors.surfaceContainerHighest, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        otherName,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 14,
                          fontWeight: hasUnread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: hasUnread
                              ? colors.primary
                              : colors.outline,
                          fontSize: 11,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMsg.isNotEmpty
                              ? lastMsg
                              : (context
                                      .read<LanguageNotifier>()
                                      .isBengali
                                  ? 'কথোপকথন শুরু করুন'
                                  : 'Start a conversation'),
                          style: TextStyle(
                            color: hasUnread
                                ? colors.onSurfaceVariant
                                : colors.outline,
                            fontSize: 12,
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            gradient: AppGradients.primary(colors),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${thread.unreadCount > 9 ? '9+' : thread.unreadCount}',
                              style: TextStyle(
                                  color: colors.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: Duration(milliseconds: 80 * index)).fadeIn().slideX(begin: 0.05);
  }

  String _formatThreadTime(DateTime dt, bool isBn) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return isBn ? '${diff.inMinutes} মি' : '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return isBn ? '${diff.inHours} ঘ' : '${diff.inHours}h';
    } else if (diff.inDays == 1) {
      return isBn ? 'গতকাল' : 'Yesterday';
    } else {
      return isBn ? '${diff.inDays} দিন' : '${diff.inDays}d';
    }
  }
}
