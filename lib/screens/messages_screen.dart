import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/messaging_model.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'chat_screen.dart';

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
    final strings = AppStrings.of(context);
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.deepBlue,
      backgroundColor: AppColors.bgMid,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(strings.messages),
            floating: true,
            snap: true,
            backgroundColor: Colors.transparent,
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
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildSearch(AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            style: const TextStyle(color: AppColors.textPrimary),
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: context.read<LanguageNotifier>().isBengali
                  ? 'বার্তা খুঁজুন...'
                  : 'Search messages...',
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.textMuted),
            ),
          ),
        ),
      ),
    ).animate().fadeIn();
  }

  // ── Skeleton ──────────────────────────────────────────────────────

  Widget _buildSkeletonList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, __) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder, width: 1.5),
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: GlassCard(
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(strings.errNetwork,
                style:
                    const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppColors.blueGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(strings.retry,
                    style: const TextStyle(
                        color: AppColors.ivory,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const Icon(Icons.chat_bubble_outline_rounded,
              size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(strings.noMessages,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
        ],
      ),
    );
  }

  // ── Thread item ───────────────────────────────────────────────────

  Widget _buildThreadItem(
      ThreadModel thread, int index, AppStrings strings) {
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
            hasUnread ? AppColors.glassBorderBlue : AppColors.glassBorder,
        glassColor: hasUnread ? AppColors.glassBlue : AppColors.glassWhite,
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
                    gradient: AppColors.blueGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepBlue.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      otherName.isNotEmpty
                          ? otherName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppColors.ivory,
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
                            Border.all(color: AppColors.bgDark, width: 2),
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
                          color: AppColors.textPrimary,
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
                              ? AppColors.deepBlue
                              : AppColors.textMuted,
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
                                ? AppColors.textSecondary
                                : AppColors.textMuted,
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
                            gradient: AppColors.blueGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${thread.unreadCount > 9 ? '9+' : thread.unreadCount}',
                              style: const TextStyle(
                                  color: AppColors.ivory,
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
