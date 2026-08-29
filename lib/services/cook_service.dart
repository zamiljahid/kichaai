import '../core/network/api_client.dart';
import '../models/cook_model.dart';

class CookService {
  static final CookService instance = CookService._();
  CookService._();

  final _client = ApiClient.instance.dio;

  // ── Provider: availability ─────────────────────────────────────────

  Future<void> setRecurringAvailability({required int dayOfWeek, required String startTime, required String endTime, int? maxConcurrentOrders}) async {
    try {
      await _client.post('/cook/availability/recurring', data: {
        'dayOfWeek': dayOfWeek, 'startTime': startTime, 'endTime': endTime,
        if (maxConcurrentOrders != null) 'maxConcurrentOrders': maxConcurrentOrders,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> setAvailabilityOverride({required DateTime specificDate, bool isBlackout = true, String? startTime, String? endTime}) async {
    try {
      await _client.post('/cook/availability/override', data: {
        'specificDate': specificDate.toIso8601String().split('T').first,
        'isBlackout': isBlackout,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<CookAvailabilityModel>> getMyAvailability() async {
    try {
      final res = await _client.get('/cook/availability/me');
      return (res.data as List).map((e) => CookAvailabilityModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Provider: self-serve verification ──────────────────────────────

  Future<void> requestProviderVerification() async {
    try {
      await _client.post('/cook/become-provider');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> getMyProviderStatus() async {
    try {
      final res = await _client.get('/cook/my-provider-status');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // Full "become a cook" onboarding submission — NID docs, guardian contact, specialty,
  // address, platform-pricing choice, per-dish menu table, policy acknowledgment.
  // Resubmittable — the backend replaces the menu wholesale on every call.
  Future<void> submitCookProfile({
    required String ownNidUrl,
    required String guardianNidUrl,
    required String guardianPhone,
    required String cookingSpecialty,
    required String homeAddress,
    required bool acceptsPlatformPricing,
    required bool policyAcknowledged,
    required List<Map<String, dynamic>> menuItems,
  }) async {
    try {
      await _client.post('/cook/provider-profile', data: {
        'ownNidUrl': ownNidUrl,
        'guardianNidUrl': guardianNidUrl,
        'guardianPhone': guardianPhone,
        'cookingSpecialty': cookingSpecialty,
        'homeAddress': homeAddress,
        'acceptsPlatformPricing': acceptsPlatformPricing,
        'policyAcknowledged': policyAcknowledged,
        'menuItems': menuItems,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> getMyCookProfile() async {
    try {
      final res = await _client.get('/cook/my-cook-profile');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Customer: requests ────────────────────────────────────────────

  Future<CookRequestModel> createRequest({
    required String dishName, required String quantity, String? notes, required String pickupArea,
    double? pickupLatitude, double? pickupLongitude, required DateTime windowDate,
    required String windowStart, required String windowEnd, double? budgetAmount,
  }) async {
    try {
      final res = await _client.post('/cook/requests', data: {
        'dishName': dishName, 'quantity': quantity, if (notes != null) 'notes': notes,
        'pickupArea': pickupArea,
        if (pickupLatitude != null) 'pickupLatitude': pickupLatitude,
        if (pickupLongitude != null) 'pickupLongitude': pickupLongitude,
        'windowDate': windowDate.toIso8601String().split('T').first,
        'windowStart': windowStart, 'windowEnd': windowEnd,
        if (budgetAmount != null) 'budgetAmount': budgetAmount,
      });
      return CookRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<CookRequestModel>> listOpenRequests({String? pickupArea}) async {
    try {
      final res = await _client.get('/cook/requests/open', queryParameters: {if (pickupArea != null) 'pickupArea': pickupArea});
      return (res.data as List).map((e) => CookRequestModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<CookRequestModel>> listMyRequests({String? status}) async {
    try {
      final res = await _client.get('/cook/requests', queryParameters: {if (status != null) 'status': status});
      return (res.data as List).map((e) => CookRequestModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<CookRequestModel> getRequest(String id) async {
    try {
      final res = await _client.get('/cook/requests/$id');
      return CookRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<CookConfirmationModel>> listConfirmations(String requestId) async {
    try {
      final res = await _client.get('/cook/requests/$requestId/confirmations');
      return (res.data as List).map((e) => CookConfirmationModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Provider: my own responses (each with the parent request attached) ────

  Future<List<Map<String, dynamic>>> listMyConfirmations({String? status}) async {
    try {
      final res = await _client.get('/cook/my-confirmations', queryParameters: {if (status != null) 'status': status});
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> confirmRequest(String requestId, {double? quotedAmount}) async {
    try {
      await _client.post('/cook/requests/$requestId/confirm', data: {if (quotedAmount != null) 'quotedAmount': quotedAmount});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> finalizeRequest(String requestId, String confirmationId) async {
    try {
      await _client.post('/cook/requests/$requestId/finalize', data: {'confirmationId': confirmationId});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> updateConfirmationStatus(String requestId, String status) async {
    try {
      await _client.post('/cook/requests/$requestId/status', data: {'status': status});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> cancelConfirmation(String requestId, {String? reason}) async {
    try {
      await _client.post('/cook/requests/$requestId/confirmation/cancel', data: {if (reason != null) 'reason': reason});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> cancelRequest(String id) async {
    try {
      await _client.post('/cook/requests/$id/cancel');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> markPickedUp(String id) async {
    try {
      await _client.post('/cook/requests/$id/pickup');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> updateProviderLocation(String id, double latitude, double longitude) async {
    try {
      await _client.post('/cook/requests/$id/location', data: {'latitude': latitude, 'longitude': longitude});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> rateProvider(String requestId, int rating, {String? comment}) async {
    try {
      await _client.post('/cook/requests/$requestId/rate', data: {'rating': rating, if (comment != null) 'comment': comment});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> initiatePayment(String id) async {
    try {
      final res = await _client.post('/cook/requests/$id/payment/initiate');
      final data = res.data as Map<String, dynamic>;
      return (data['transaction'] as Map<String, dynamic>?) ?? data;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<CookRequestModel> confirmPayment(String id) async {
    try {
      final res = await _client.post('/cook/requests/$id/payment/confirm');
      return CookRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
