import '../core/network/api_client.dart';

/// Skill-share (barter pattern) — no typed models here, matching how this
/// corner of the app already worked (skill_share_screen.dart /
/// exchange_detail_screen.dart both consume raw Maps); this just centralizes
/// the actual HTTP calls, which previously lived inline in the screens with
/// several field-name mismatches against the real backend DTOs.
class SkillShareService {
  static final SkillShareService instance = SkillShareService._();
  SkillShareService._();

  final _client = ApiClient.instance.dio;

  // ── Skills ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> addSkill({
    required String skillName,
    required String category,
    required String level,
    String? description,
    bool isOffering = true,
    bool isWanting = false,
  }) async {
    try {
      final res = await _client.post('/skill-share/skills', data: {
        'skillName': skillName,
        'category': category,
        'level': level,
        if (description != null) 'description': description,
        'isOffering': isOffering,
        'isWanting': isWanting,
      });
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> updateSkill(String skillId, Map<String, dynamic> changes) async {
    try {
      await _client.patch('/skill-share/skills/$skillId', data: changes);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<Map<String, dynamic>>> listUserSkills(String userId, {bool? isOffering, bool? isWanting}) async {
    try {
      final res = await _client.get('/skill-share/skills/user/$userId', queryParameters: {
        if (isOffering != null) 'isOffering': isOffering.toString(),
        if (isWanting != null) 'isWanting': isWanting.toString(),
      });
      return _asList(res.data);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<Map<String, dynamic>>> searchSkills({String? category, String? skillName, String? level}) async {
    try {
      final res = await _client.get('/skill-share/skills/search', queryParameters: {
        if (category != null) 'category': category,
        if (skillName != null) 'skillName': skillName,
        if (level != null) 'level': level,
      });
      return _asList(res.data);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Exchanges (open-post + respond, like matchmaking's requests) ───

  Future<Map<String, dynamic>> proposeExchange({
    required String offeredSkillId,
    required String wantedSkillName,
    required String wantedSkillCategory,
    String? message,
    int agreedSessionCount = 1,
  }) async {
    try {
      final res = await _client.post('/skill-share/exchanges', data: {
        'offeredSkillId': offeredSkillId,
        'wantedSkillName': wantedSkillName,
        'wantedSkillCategory': wantedSkillCategory,
        if (message != null && message.isNotEmpty) 'message': message,
        'agreedSessionCount': agreedSessionCount,
      });
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// [accept] false = pass on it (no wantedSkillId needed). true = claim it —
  /// [wantedSkillId] is which of the responder's own skills they're offering
  /// back in return.
  Future<Map<String, dynamic>> respondToExchange(String exchangeId, {required bool accept, String? wantedSkillId}) async {
    try {
      final res = await _client.post('/skill-share/exchanges/$exchangeId/respond', data: {
        'accept': accept,
        if (wantedSkillId != null) 'wantedSkillId': wantedSkillId,
      });
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// My own exchanges (as requester or responder), any status.
  Future<List<Map<String, dynamic>>> listMyExchanges({String? status}) async {
    try {
      final res = await _client.get('/skill-share/exchanges', queryParameters: {
        if (status != null) 'status': status,
      });
      return _asList(res.data);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Everyone's open, unclaimed exchange posts — the discovery feed.
  Future<List<Map<String, dynamic>>> listOpenExchanges() async {
    try {
      final res = await _client.get('/skill-share/exchanges', queryParameters: {'openOnly': 'true'});
      return _asList(res.data);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> getExchange(String id) async {
    try {
      final res = await _client.get('/skill-share/exchanges/$id');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> cancelExchange(String id) async {
    try {
      await _client.post('/skill-share/exchanges/$id/cancel');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> reviewExchange(String id, {required int rating, required String review}) async {
    try {
      await _client.post('/skill-share/exchanges/$id/review', data: {'rating': rating, 'review': review});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Platform fee (৳100, both sides — required before a session can be
  // scheduled). Requester pays any time after proposing; responder pays any
  // time after accepting. Mirrors DispatchService's
  // initiateDepositPayment/confirmDepositPayment pair 1:1.

  /// Starts a real SSLCommerz session for the caller's ৳100 platform fee on
  /// this exchange. Returns the raw transaction map — read `gatewayPageUrl`
  /// and hand it to [PaymentWaitingScreen].
  Future<Map<String, dynamic>> initiateFeePayment(String exchangeId) async {
    try {
      final res = await _client.post('/skill-share/exchanges/$exchangeId/fee/initiate');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Verifies (server-to-server) that the caller's fee payment actually
  /// completed and marks their side paid. Throws if it hasn't completed yet
  /// — callers should treat that as "still pending", not a hard failure.
  Future<Map<String, dynamic>> confirmFeePayment(String exchangeId) async {
    try {
      final res = await _client.post('/skill-share/exchanges/$exchangeId/fee/confirm');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Reciprocity report (post-completion) ────────────────────────

  /// One-shot, per side, only after the exchange is 'completed': did the
  /// partner actually teach the skill they offered? [wasTaught]=false
  /// permanently bans the OTHER party from skill-share.
  Future<void> reportNonReciprocity(String exchangeId, {required bool wasTaught}) async {
    try {
      await _client.post('/skill-share/exchanges/$exchangeId/reciprocity', data: {'wasTaught': wasTaught});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Sessions ─────────────────────────────────────────────────────

  Future<void> scheduleSession({
    required String exchangeId,
    required String scheduledAt,
    int durationMins = 60,
    String? meetingLink,
    String? notes,
  }) async {
    try {
      await _client.post('/skill-share/sessions', data: {
        'exchangeId': exchangeId,
        'scheduledAt': scheduledAt,
        'durationMins': durationMins,
        if (meetingLink != null) 'meetingLink': meetingLink,
        if (notes != null) 'notes': notes,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> completeSession(String sessionId) async {
    try {
      await _client.post('/skill-share/sessions/$sessionId/complete');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
    return (list as List).cast<Map<String, dynamic>>();
  }
}
