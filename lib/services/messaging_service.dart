import '../core/network/api_client.dart';
import '../models/messaging_model.dart';

class MessagingService {
  static final MessagingService instance = MessagingService._();
  MessagingService._();

  final _client = ApiClient.instance.dio;

  // ── Threads ───────────────────────────────────────────────────────

  /// [contextChunk] must be one of: 'dispatch', 'marketplace' (booking), 'commerce' (order),
  /// 'direct' (plain 1:1, no business context), or anything else (defaults to a matchmaking
  /// thread server-side). Most threads are now created automatically by dispatch-service (on
  /// job accept) and matchmaking-service (on award) — this is mainly for a direct/general chat.
  Future<ThreadModel> createThread({
    required List<String> participantUserIds,
    required String contextChunk,
    String? dispatchJobId,
    String? bookingId,
    String? orderId,
    String? serviceRequestId,
    String? responseId,
  }) async {
    try {
      final res = await _client.post('/messaging/threads', data: {
        'participantUserIds': participantUserIds,
        'contextChunk': contextChunk,
        if (dispatchJobId != null) 'dispatchJobId': dispatchJobId,
        if (bookingId != null) 'bookingId': bookingId,
        if (orderId != null) 'orderId': orderId,
        if (serviceRequestId != null) 'serviceRequestId': serviceRequestId,
        if (responseId != null) 'responseId': responseId,
      });
      return ThreadModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<ThreadModel>> listThreads(String userId) async {
    try {
      final res = await _client.get(
        '/messaging/threads',
        queryParameters: {'userId': userId},
      );
      final list = res.data as List<dynamic>;
      return list
          .map((e) => ThreadModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<ThreadModel> getThread(String id) async {
    try {
      final res = await _client.get('/messaging/threads/$id');
      return ThreadModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Messages ──────────────────────────────────────────────────────

  Future<MessageModel> sendMessage(String threadId, {
    required String body,
    String messageType = 'text',
  }) async {
    try {
      final res = await _client.post('/messaging/threads/$threadId/messages', data: {
        'body': body,
        'messageType': messageType,
      });
      return MessageModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<MessageModel>> listMessages(
    String threadId, {
    int limit = 50,
    String? beforeMessageId,
  }) async {
    try {
      final res = await _client.get(
        '/messaging/threads/$threadId/messages',
        queryParameters: {
          'limit': limit.toString(),
          if (beforeMessageId != null) 'beforeMessageId': beforeMessageId,
        },
      );
      final list = res.data as List<dynamic>;
      return list
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Read status ───────────────────────────────────────────────────

  Future<void> markAsRead(String threadId) async {
    try {
      await _client.post('/messaging/threads/$threadId/read');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> markAllAsRead(String threadId) async {
    try {
      await _client.post('/messaging/threads/$threadId/read-all');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Always the logged-in user's own count — /messaging/unread-count/:userId doesn't exist
  /// server-side, only the self-service /me route (userId is bound from the JWT there).
  Future<int> getUnreadCount() async {
    try {
      final res = await _client.get('/messaging/unread-count/me');
      final data = res.data as Map<String, dynamic>;
      return data['count'] as int? ?? data['unreadCount'] as int? ?? 0;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Participants ──────────────────────────────────────────────────

  Future<void> addParticipant(String threadId, String userId) async {
    try {
      await _client.post('/messaging/threads/$threadId/participants', data: {
        'userId': userId,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> removeParticipant(String threadId, String userId) async {
    try {
      await _client.delete('/messaging/threads/$threadId/participants/$userId');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
