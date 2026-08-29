import '../core/network/api_client.dart';

class LegalSuggestion {
  final String? legalArea;
  final String? legalService;
  final String? description;

  LegalSuggestion({this.legalArea, this.legalService, this.description});

  factory LegalSuggestion.fromJson(Map<String, dynamic> json) => LegalSuggestion(
        legalArea: json['legalArea'] as String?,
        legalService: json['legalService'] as String?,
        description: json['description'] as String?,
      );
}

class AiChatReply {
  final String sessionId;
  final String reply;
  final LegalSuggestion? suggestion;
  final String? draftUrl;
  final String? draftTitle;

  AiChatReply({
    required this.sessionId,
    required this.reply,
    this.suggestion,
    this.draftUrl,
    this.draftTitle,
  });

  factory AiChatReply.fromJson(Map<String, dynamic> json) => AiChatReply(
        sessionId: json['sessionId'] as String,
        reply: json['reply'] as String,
        suggestion: json['suggestion'] is Map
            ? LegalSuggestion.fromJson(json['suggestion'] as Map<String, dynamic>)
            : null,
        draftUrl: json['draftUrl'] as String?,
        draftTitle: json['draftTitle'] as String?,
      );
}

class AiChatHistoryMessage {
  final String role;
  final String content;
  AiChatHistoryMessage({required this.role, required this.content});

  factory AiChatHistoryMessage.fromJson(Map<String, dynamic> json) => AiChatHistoryMessage(
        role: json['role'] as String? ?? 'assistant',
        content: json['content'] as String? ?? '',
      );
}

class AiChatLatestSession {
  final String? sessionId;
  final List<AiChatHistoryMessage> messages;
  AiChatLatestSession({this.sessionId, required this.messages});

  factory AiChatLatestSession.fromJson(Map<String, dynamic> json) => AiChatLatestSession(
        sessionId: json['sessionId'] as String?,
        messages: (json['messages'] as List? ?? [])
            .map((e) => AiChatHistoryMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AiChatService {
  static final AiChatService instance = AiChatService._();
  AiChatService._();

  final _client = ApiClient.instance.dio;

  // Resumes the most recent session for this bot type (with full history) — used on screen
  // open so an in-progress conversation isn't lost every time the chat is reopened.
  Future<AiChatLatestSession> getLatestSession({String? botType}) async {
    try {
      final res = await _client.get('/messaging/ai-chat/latest', queryParameters: {if (botType != null) 'botType': botType});
      return AiChatLatestSession.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<AiChatReply> send(
    String message, {
    String? sessionId,
    String? serviceKind,
    String? providerId,
    String? botType,
  }) async {
    try {
      final res = await _client.post('/messaging/ai-chat', data: {
        'message': message,
        if (sessionId != null) 'sessionId': sessionId,
        if (serviceKind != null) 'serviceKind': serviceKind,
        if (providerId != null) 'providerId': providerId,
        if (botType != null) 'botType': botType,
      });
      return AiChatReply.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
