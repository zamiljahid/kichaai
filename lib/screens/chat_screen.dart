import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/utils/app_strings.dart';
import '../models/messaging_model.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  final String threadId;
  final String currentUserId;
  final String participantName;
  final bool isParticipantOnline;

  const ChatScreen({
    super.key,
    required this.threadId,
    required this.currentUserId,
    required this.participantName,
    this.isParticipantOnline = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _oldestMessageId;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markRead();
    _scrollController.addListener(_onScroll);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final msgs = await MessagingService.instance.listMessages(widget.threadId, limit: 50);
      if (!mounted) return;
      setState(() => _messages = msgs);
    } catch (_) {}
  }

  Future<void> _loadMessages({bool loadMore = false}) async {
    if (!loadMore) setState(() => _isLoading = true);
    try {
      final msgs = await MessagingService.instance.listMessages(
        widget.threadId,
        limit: 50,
        beforeMessageId: loadMore ? _oldestMessageId : null,
      );
      if (mounted) {
        setState(() {
          if (loadMore) {
            _messages = [..._messages, ...msgs];
          } else {
            _messages = msgs;
          }
          if (msgs.isNotEmpty) _oldestMessageId = msgs.last.id;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markRead() async {
    try {
      await MessagingService.instance.markAllAsRead(widget.threadId);
    } catch (_) {}
  }

  void _onScroll() {
    // Load older messages when scrolled to bottom (list is reversed)
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMessages(loadMore: true);
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _isSending) return;

    _messageController.clear();
    setState(() => _isSending = true);
    try {
      final msg = await MessagingService.instance.sendMessage(
        widget.threadId,
        body: body,
      );
      if (mounted) {
        setState(() => _messages = [msg, ..._messages]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString(),
                style: const TextStyle(color: AppColors.ivory)),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: _buildAppBar(strings),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(strings)),
          _buildInputBar(strings),
        ],
      ),
    );
  }

  AppBar _buildAppBar(AppStrings strings) {
    return AppBar(
      backgroundColor: AppColors.bgMid,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.blueGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.participantName.isNotEmpty
                        ? widget.participantName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.ivory,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (widget.isParticipantOnline)
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgMid, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.participantName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                widget.isParticipantOnline
                    ? (context.read<LanguageNotifier>().isBengali
                        ? 'অনলাইন'
                        : 'Online')
                    : (context.read<LanguageNotifier>().isBengali
                        ? 'অফলাইন'
                        : 'Offline'),
                style: TextStyle(
                  color: widget.isParticipantOnline
                      ? const Color(0xFF4CAF50)
                      : AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () => context.read<LanguageNotifier>().toggle(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.glassBorder, width: 1),
                  ),
                  child: Text(
                    strings.langToggle,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList(AppStrings strings) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.deepBlue,
          strokeWidth: 2,
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          strings.noMessages,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _buildMessageBubble(_messages[i], i),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, int index) {
    final isMe = msg.senderId == widget.currentUserId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: AppColors.blueGradient,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.participantName.isNotEmpty
                      ? widget.participantName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.ivory,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe ? AppColors.blueGradient : null,
                color: isMe ? null : AppColors.glassWhite,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: isMe
                    ? null
                    : Border.all(color: AppColors.glassBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    msg.body ?? '[attachment]',
                    style: TextStyle(
                      color: isMe ? AppColors.ivory : AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatTime(msg.createdAt),
                    style: TextStyle(
                      color: isMe
                          ? AppColors.ivory.withValues(alpha: 0.7)
                          : AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: 30 * (index < 10 ? index : 0)))
        .fadeIn(duration: 200.ms);
  }

  Widget _buildInputBar(AppStrings strings) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          decoration: const BoxDecoration(
            color: AppColors.bgMid,
            border: Border(
              top: BorderSide(color: AppColors.glassBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: strings.typeMessage,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                              color: AppColors.glassBorder, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                              color: AppColors.glassBorder, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                              color: AppColors.deepBlue, width: 1.5),
                        ),
                        filled: true,
                        fillColor: AppColors.glassWhite,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.blueGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepBlue.withValues(alpha: 0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: _isSending
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.ivory,
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: AppColors.ivory, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
