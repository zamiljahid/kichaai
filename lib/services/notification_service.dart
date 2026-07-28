import '../core/network/api_client.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _client = ApiClient.instance.dio;

  Future<List<NotificationModel>> listNotifications({
    String? userId,
    int limit = 20,
    int offset = 0,
    bool? isRead,
  }) async {
    try {
      final res = await _client.get('/notifications', queryParameters: {
        if (userId != null) 'userId': userId,
        'limit': limit,
        'offset': offset,
        // Backend filters by status, not a boolean — 'read' works directly;
        // "unread" spans pending/sent/delivered so we filter client-side.
        if (isRead == true) 'status': 'read',
      });
      final data = res.data;
      final items = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (items as List).map((e) => NotificationModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<int> getUnreadCount(String userId) async {
    try {
      final res = await _client.get('/notifications/unread-count/$userId');
      final data = res.data;
      if (data is Map) return (data['count'] ?? data['unreadCount'] ?? 0) as int;
      return (data as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAsRead(List<String> notificationIds) async {
    try {
      // Backend accepts ONE id per call ({notificationId}) — a plural array key
      // is silently ignored, so this was a no-op before. Loop instead.
      for (final id in notificationIds) {
        await _client.post('/notifications/read', data: {'notificationId': id});
      }
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<NotificationPreference> getPreferences(String userId) async {
    try {
      final res = await _client.get('/notifications/preferences/$userId');
      final data = res.data;
      final pref = data is List ? (data.isNotEmpty ? data.first : {}) : data;
      return NotificationPreference.fromJson(pref as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> upsertPreferences(NotificationPreference pref) async {
    try {
      await _client.put('/notifications/preferences', data: pref.toJson());
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> registerPushToken(String userId, String token, String platform, {String? deviceId}) async {
    try {
      // userId intentionally NOT sent — the backend derives it from the JWT
      // and ignores anything in the body (kept in the signature for existing callers).
      await _client.post('/notifications/push-tokens', data: {
        'token': token,
        'platform': platform,
        if (deviceId != null) 'deviceId': deviceId,
      });
    } catch (_) {
      // Non-fatal — token registration best-effort
    }
  }

  /// Call on logout so a signed-out device stops receiving push for this
  /// account. Must run BEFORE the JWT is cleared — the backend uses the token's
  /// user to scope the deactivation.
  Future<void> deactivatePushToken(String token) async {
    try {
      await _client.delete('/notifications/push-tokens', data: {'token': token});
    } catch (_) {
      // Non-fatal — best-effort, same as registration
    }
  }
}
