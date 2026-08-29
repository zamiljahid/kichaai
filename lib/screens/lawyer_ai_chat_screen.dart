import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import '../services/ai_chat_service.dart';
import '../theme/app_theme.dart';

class _Bubble {
  final String text;
  final bool isUser;
  final String? draftUrl;
  final String? draftTitle;
  _Bubble(this.text, this.isUser, {this.draftUrl, this.draftTitle});
}

/// Dedicated AI chat for the lawyer-matching triage — separate from the general
/// support chatbot ([[AiChatOverlay]]). Helps a customer figure out which kind of
/// lawyer they need, and can draft a starting-point document (PDF) once it has
/// enough facts. On close, returns a {legalArea, legalService, description} map to
/// pre-fill the booking form if the AI reached a confident suggestion — or null.
class LawyerAiChatScreen extends StatefulWidget {
  final bool isBn;
  const LawyerAiChatScreen({super.key, required this.isBn});

  @override
  State<LawyerAiChatScreen> createState() => _LawyerAiChatScreenState();
}

class _LawyerAiChatScreenState extends State<LawyerAiChatScreen> {
  final List<_Bubble> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = stt.SpeechToText();

  String? _sessionId;
  LegalSuggestion? _latestSuggestion;
  bool _sending = false;
  bool _speechAvailable = false;
  bool _listening = false;
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final latest = await AiChatService.instance.getLatestSession(botType: 'lawyer');
      if (!mounted) return;
      setState(() {
        _sessionId = latest.sessionId;
        _messages.addAll(latest.messages.map((m) => _Bubble(m.content, m.role == 'user')));
        _loadingHistory = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      localeId: widget.isBn ? 'bn_BD' : 'en_US',
      onResult: (result) {
        setState(() => _controller.text = result.recognizedWords);
      },
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (_listening) await _speech.stop();
    setState(() {
      _messages.add(_Bubble(text, true));
      _sending = true;
      _listening = false;
      _controller.clear();
    });
    _scrollToBottom();
    try {
      final res = await AiChatService.instance.send(
        text,
        sessionId: _sessionId,
        botType: 'lawyer',
      );
      _sessionId = res.sessionId;
      setState(() {
        _messages.add(_Bubble(res.reply, false, draftUrl: res.draftUrl, draftTitle: res.draftTitle));
        if (res.suggestion?.legalArea != null && res.suggestion?.legalService != null) {
          _latestSuggestion = res.suggestion;
        }
      });
    } catch (_) {
      setState(() => _messages.add(_Bubble(
            widget.isBn ? 'দুঃখিত, একটু সমস্যা হয়েছে। আবার চেষ্টা করুন।' : 'Sorry, something went wrong. Please try again.',
            false,
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
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

  Future<void> _openDraft(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack(widget.isBn ? 'ফাইল খোলা যায়নি' : 'Could not open the file');
    } catch (_) {
      if (mounted) _snack(widget.isBn ? 'ফাইল খোলা যায়নি' : 'Could not open the file');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _useSuggestion() {
    if (_latestSuggestion == null) return;
    Navigator.of(context).pop({
      'legalArea': _latestSuggestion!.legalArea,
      'legalService': _latestSuggestion!.legalService,
      'description': _latestSuggestion!.description,
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgMid,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          widget.isBn ? 'AI দিয়ে lawyer খুঁজুন' : 'Find a lawyer with AI',
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator(color: AppColors.deepBlue))
                : _messages.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        widget.isBn
                            ? 'আপনার আইনি সমস্যাটি বলুন — কী হয়েছে, কে জড়িত, কী চান। আমি বুঝে নেব কোন ধরনের lawyer লাগবে, এবং চাইলে একটা প্রাথমিক নোটিশ/ডকুমেন্ট draft করে দিতে পারি।'
                            : 'Tell me about your legal issue — what happened, who\'s involved, what you want. I\'ll figure out which kind of lawyer you need, and can draft a starting-point notice/document if you ask.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
                      ),
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
          if (_latestSuggestion != null) _suggestionBar(),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _suggestionBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorderBlue),
      ),
      child: Row(
        children: [
          const Icon(Icons.gavel_rounded, color: AppColors.deepBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isBn ? 'AI একটা lawyer category suggest করেছে' : 'AI has a lawyer category suggestion',
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _useSuggestion,
            child: Text(widget.isBn ? 'ব্যবহার করুন' : 'Use this'),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Bubble m) {
    return Column(
      crossAxisAlignment: m.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              gradient: m.isUser ? AppColors.blueGradient : null,
              color: m.isUser ? null : AppColors.glassWhite,
              border: m.isUser ? null : Border.all(color: AppColors.glassBorder),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(m.isUser ? 16 : 4),
                bottomRight: Radius.circular(m.isUser ? 4 : 16),
              ),
            ),
            child: Text(
              m.text,
              style: TextStyle(color: m.isUser ? Colors.white : AppColors.textPrimary, fontSize: 14, height: 1.4),
            ),
          ),
        ),
        if (m.draftUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: GestureDetector(
              onTap: () => _openDraft(m.draftUrl!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.fuchsiaGradient.colors.first.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.fuchsia.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: AppColors.fuchsia, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        m.draftTitle ?? (widget.isBn ? 'Draft PDF দেখুন' : 'View draft PDF'),
                        style: const TextStyle(color: AppColors.fuchsia, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          border: Border.all(color: AppColors.glassBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.deepBlue),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            if (_speechAvailable)
              GestureDetector(
                onTap: _toggleListening,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _listening ? const Color(0xFFEF4444) : AppColors.glassWhite,
                    shape: BoxShape.circle,
                    border: Border.all(color: _listening ? const Color(0xFFEF4444) : AppColors.glassBorder),
                  ),
                  child: Icon(
                    _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _listening ? Colors.white : AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _listening
                      ? (widget.isBn ? 'শুনছি...' : 'Listening...')
                      : (widget.isBn ? 'আপনার সমস্যা লিখুন...' : 'Describe your issue...'),
                  filled: true,
                  fillColor: AppColors.bgDark,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: AppColors.glassBorder),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
