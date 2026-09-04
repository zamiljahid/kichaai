import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/ai_chat_service.dart';
import '../services/push_service.dart';
import '../theme/app_gradients.dart';

class _ChatBubbleData {
  final String text;
  final bool isUser;
  _ChatBubbleData(this.text, this.isUser);
}

/// App-wide floating AI support chat. Mounted once at the MaterialApp root
/// (see main.dart's `builder`) so it appears above every screen — service
/// pages, provider profiles, everywhere — without wiring it into each one.
class AiChatOverlay extends StatefulWidget {
  final Widget child;
  const AiChatOverlay({super.key, required this.child});

  @override
  State<AiChatOverlay> createState() => _AiChatOverlayState();
}

class _AiChatOverlayState extends State<AiChatOverlay> {
  final List<_ChatBubbleData> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _sessionId;
  bool _sending = false;

  Future<void> _send(bool isBn, StateSetter setSheetState) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setSheetState(() {
      _messages.add(_ChatBubbleData(text, true));
      _sending = true;
      _controller.clear();
    });
    _scrollToBottom();
    try {
      final res = await AiChatService.instance.send(text, sessionId: _sessionId);
      _sessionId = res.sessionId;
      setSheetState(() => _messages.add(_ChatBubbleData(res.reply, false)));
    } catch (_) {
      setSheetState(() => _messages.add(_ChatBubbleData(
            isBn
                ? 'দুঃখিত, একটু সমস্যা হয়েছে। আবার চেষ্টা করুন।'
                : 'Sorry, something went wrong. Please try again.',
            false,
          )));
    } finally {
      setSheetState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openChat(bool isBn) {
    final colors = Theme.of(context).colorScheme;
    // AiChatOverlay wraps MaterialApp.builder's `child` (the Navigator lives INSIDE that
    // child), so this State's own `context` is an ANCESTOR of the Navigator, not a descendant —
    // showModalBottomSheet's internal Navigator.of(context) lookup walks upward and never finds
    // one, throwing "Navigator operation requested with a context that does not include a
    // Navigator" (silently, since it's caught by the gesture handler rather than crashing the
    // app — which is why the button visibly did nothing). Use the app's global navigator key
    // (already wired to MaterialApp for push-notification navigation) to reach a real
    // Navigator-descendant context instead.
    final navContext = PushService.instance.navigatorKey.currentContext;
    if (navContext == null) return;
    showModalBottomSheet(
      context: navContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.5,
              maxChildSize: 0.92,
              expand: false,
              builder: (ctx, scrollCtl) => Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    _sheetHeader(ctx, isBn),
                    Expanded(
                      child: _messages.isEmpty
                          ? Center(
                              child: Text(
                                isBn ? 'আপনার প্রশ্ন লিখুন...' : 'Ask me anything about KiChaai...',
                                style: TextStyle(color: colors.outline),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length + (_sending ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (i == _messages.length) return _typingBubble();
                                return _bubble(_messages[i]);
                              },
                            ),
                    ),
                    _inputBar(isBn, setSheetState),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetHeader(BuildContext sheetCtx, bool isBn) {
    final colors = Theme.of(sheetCtx).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppGradients.primary(colors),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isBn ? 'KiChaai সহায়ক' : 'KiChaai Assistant',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: colors.onSurface),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: colors.outline),
            onPressed: () => Navigator.of(sheetCtx).pop(),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_ChatBubbleData m) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          gradient: m.isUser ? AppGradients.primary(colors) : null,
          color: m.isUser ? null : colors.surface,
          border: m.isUser ? null : Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(m.isUser ? 16 : 4),
            bottomRight: Radius.circular(m.isUser ? 4 : 16),
          ),
        ),
        child: Text(
          m.text,
          style: TextStyle(color: m.isUser ? Colors.white : colors.onSurface, fontSize: 14, height: 1.4),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 24,
          height: 12,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputBar(bool isBn, StateSetter setSheetState) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(isBn, setSheetState),
                decoration: InputDecoration(
                  hintText: isBn ? 'বার্তা লিখুন...' : 'Type a message...',
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(isBn, setSheetState),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(gradient: AppGradients.primary(colors), shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.watch<LanguageNotifier>().isBengali;
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: ApiClient.isLoggedIn,
          builder: (context, loggedIn, _) {
            if (!loggedIn) return const SizedBox.shrink();
            return Positioned(
              right: 16,
              bottom: 100,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () => _openChat(isBn),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary(colors),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 28),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
