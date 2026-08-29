import '../core/network/api_client.dart';
import '../models/matchmaking_model.dart';

class MatchmakingService {
  static final MatchmakingService instance = MatchmakingService._();
  MatchmakingService._();

  final _client = ApiClient.instance.dio;

  Future<List<MatchProviderModel>> listProviders({
    String? kind,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get('/matchmaking/providers', queryParameters: {
        if (kind != null) 'kind': kind,
        'limit': limit.toString(),
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => MatchProviderModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<MatchProviderModel> getProvider(String providerId) async {
    try {
      final res = await _client.get('/matchmaking/providers/$providerId');
      return MatchProviderModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // customerId/customerNameSnapshot/customerPhoneSnapshot are NOT accepted here — the
  // gateway binds them from the JWT server-side, so sending them would be pointless.
  Future<MatchRequestModel> createRequest({
    required String requestType,
    required String serviceTypeId,
    required String title,
    required String description,
    double? budgetMin,
    double? budgetMax,
    String? preferredStartDate,
    double? serviceLatitude,
    double? serviceLongitude,
    String? serviceAddressSnapshot,
    Map<String, dynamic>? tutorDetails,
    Map<String, dynamic>? messDetails,
    Map<String, dynamic>? petCareDetails,
    Map<String, dynamic>? helpingHandDetails,
    // Set when booking a SPECIFIC provider (e.g. from their profile) instead of a public
    // broadcast — only that provider will see this request in their inbox.
    String? targetProviderId,
  }) async {
    try {
      final res = await _client.post('/matchmaking/requests', data: {
        'requestType': requestType,
        'serviceTypeId': serviceTypeId,
        'title': title,
        'description': description,
        if (budgetMin != null) 'budgetMin': budgetMin,
        if (budgetMax != null) 'budgetMax': budgetMax,
        if (preferredStartDate != null) 'preferredStartDate': preferredStartDate,
        if (serviceLatitude != null) 'serviceLatitude': serviceLatitude,
        if (serviceLongitude != null) 'serviceLongitude': serviceLongitude,
        if (serviceAddressSnapshot != null) 'serviceAddressSnapshot': serviceAddressSnapshot,
        if (tutorDetails != null) 'tutorDetails': tutorDetails,
        if (messDetails != null) 'messDetails': messDetails,
        if (petCareDetails != null) 'petCareDetails': petCareDetails,
        if (helpingHandDetails != null) 'helpingHandDetails': helpingHandDetails,
        if (targetProviderId != null) 'targetProviderId': targetProviderId,
      });
      return MatchRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Flips a draft request to `open` so providers can see and respond to it.
  /// [expiresInDays] is the customer's own choice of how long to keep it open
  /// (server clamps 1-60, defaults to 7 if omitted).
  Future<MatchRequestModel> publishRequest(String id, {int? expiresInDays}) async {
    try {
      final res = await _client.patch('/matchmaking/requests/$id/status', data: {
        'status': 'open',
        if (expiresInDays != null) 'expiresInDays': expiresInDays,
      });
      return MatchRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<MatchRequestModel>> listRequests({
    String? requestType,
    String? status,
    String? customerId,
    // Tutor-browse precision filters (ignored server-side for anything but tutor requests).
    String? subject,
    String? studentClass,
    String? prefersGender,
    // Helping-hand-browse precision filter (ignored server-side for anything else).
    String? workType,
    // Pass true when a PROVIDER is browsing the open feed (not listing their own requests as a
    // customerId) — also surfaces requests privately targeted at them via targetProviderId.
    bool browseAsProvider = false,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final res = await _client.get('/matchmaking/requests', queryParameters: {
        if (requestType != null) 'requestType': requestType,
        if (status != null) 'status': status,
        if (customerId != null) 'customerId': customerId,
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (studentClass != null && studentClass.isNotEmpty) 'studentClass': studentClass,
        if (prefersGender != null && prefersGender.isNotEmpty) 'prefersGender': prefersGender,
        if (workType != null && workType.isNotEmpty) 'workType': workType,
        if (browseAsProvider) 'browseAsProvider': 'true',
        'limit': limit.toString(),
        'offset': offset.toString(),
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => MatchRequestModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<MatchRequestModel> getRequest(String id) async {
    try {
      final res = await _client.get('/matchmaking/requests/$id');
      return MatchRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<MatchResponseModel>> listResponses(String requestId) async {
    try {
      final res = await _client.get('/matchmaking/requests/$requestId/responses');
      final list = res.data as List<dynamic>;
      return list.map((e) => MatchResponseModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // providerId/providerNameSnapshot/providerAvgRatingSnapshot are NOT accepted here — the
  // gateway binds them from the JWT server-side (this used to be spoofable).
  Future<MatchResponseModel> createResponse(
    String requestId, {
    String? coverMessage,
    double? quotedAmount,
    String? quotedAmountType,
    String? estimatedStartDate,
  }) async {
    try {
      final res = await _client.post('/matchmaking/requests/$requestId/responses', data: {
        if (coverMessage != null) 'coverMessage': coverMessage,
        if (quotedAmount != null) 'quotedAmount': quotedAmount,
        if (quotedAmountType != null) 'quotedAmountType': quotedAmountType,
        if (estimatedStartDate != null) 'estimatedStartDate': estimatedStartDate,
      });
      return MatchResponseModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<MatchResponseModel> shortlistResponse(String responseId) async {
    try {
      final res = await _client.post('/matchmaking/responses/$responseId/shortlist');
      return MatchResponseModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<MatchRequestModel> awardResponse(String responseId) async {
    try {
      final res = await _client.post('/matchmaking/responses/$responseId/award');
      return MatchRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Starts the real SSLCommerz session for an awarded quote. Returns the raw transaction map
  /// (has `gatewayPageUrl`) — nothing is credited/unlocked until [confirmAwardPayment] verifies it.
  Future<Map<String, dynamic>> initiateAwardPayment(String requestId, {String? couponCode}) async {
    try {
      final res = await _client.post('/matchmaking/requests/$requestId/award-payment/initiate',
          data: couponCode != null ? {'couponCode': couponCode} : null);
      final data = res.data as Map<String, dynamic>;
      return (data['transaction'] as Map<String, dynamic>?) ?? data;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Verifies the payment server-to-server; only once this succeeds does the provider's wallet
  /// get credited and the chat thread open.
  Future<MatchRequestModel> confirmAwardPayment(String requestId) async {
    try {
      final res = await _client.post('/matchmaking/requests/$requestId/award-payment/confirm');
      return MatchRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Pre-hire meet call (optional, additive to award) ─────────────────────

  Future<void> requestMeet(String responseId) async {
    try {
      await _client.post('/matchmaking/responses/$responseId/request-meet');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> acceptMeet(String responseId) async {
    try {
      await _client.post('/matchmaking/responses/$responseId/accept-meet');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> initiateMeetFeePayment(String responseId, {String? couponCode}) async {
    try {
      final res = await _client.post('/matchmaking/responses/$responseId/meet-fee/initiate',
          data: couponCode != null ? {'couponCode': couponCode} : null);
      final data = res.data as Map<String, dynamic>;
      return (data['transaction'] as Map<String, dynamic>?) ?? data;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> confirmMeetFeePayment(String responseId) async {
    try {
      await _client.post('/matchmaking/responses/$responseId/meet-fee/confirm');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // Provider's own submitted responses (each with the parent request attached) — fills a real
  // gap: providers previously had no way to check back on a response after submitting it.
  Future<List<Map<String, dynamic>>> listMyResponses() async {
    try {
      final res = await _client.get('/matchmaking/my-responses');
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
