import '../core/network/api_client.dart';
import '../models/laundry_model.dart';

class LaundryService {
  static final LaundryService instance = LaundryService._();
  LaundryService._();

  final _client = ApiClient.instance.dio;

  Future<List<LaundryRateCardModel>> getCatalog() async {
    try {
      final res = await _client.get('/laundry/catalog');
      return (res.data as List).map((e) => LaundryRateCardModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<LaundryHubModel>> listHubs() async {
    try {
      final res = await _client.get('/laundry/hubs');
      return (res.data as List).map((e) => LaundryHubModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<LaundryBookingModel> createBooking({
    required String hubId,
    required String serviceKind,
    required String pricingUnit,
    required double estimatedLoad,
    required String pickupAddress,
    double? pickupLatitude,
    double? pickupLongitude,
    required DateTime pickupSlotStart,
    required DateTime pickupSlotEnd,
    required String paymentTiming,
  }) async {
    try {
      final res = await _client.post('/laundry/bookings', data: {
        'hubId': hubId,
        'serviceKind': serviceKind,
        'pricingUnit': pricingUnit,
        'estimatedLoad': estimatedLoad,
        'pickupAddress': pickupAddress,
        if (pickupLatitude != null) 'pickupLatitude': pickupLatitude,
        if (pickupLongitude != null) 'pickupLongitude': pickupLongitude,
        'pickupSlotStart': pickupSlotStart.toIso8601String(),
        'pickupSlotEnd': pickupSlotEnd.toIso8601String(),
        'paymentTiming': paymentTiming,
      });
      return LaundryBookingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<LaundryBookingModel>> listMyBookings({String? status}) async {
    try {
      final res = await _client.get('/laundry/bookings', queryParameters: {if (status != null) 'status': status});
      return (res.data as List).map((e) => LaundryBookingModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<LaundryBookingModel> getBooking(String id) async {
    try {
      final res = await _client.get('/laundry/bookings/$id');
      return LaundryBookingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> cancelBooking(String id) async {
    try {
      await _client.post('/laundry/bookings/$id/cancel');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> initiatePayment(String id, {String? couponCode}) async {
    try {
      final res = await _client.post('/laundry/bookings/$id/payment/initiate',
          data: couponCode != null ? {'couponCode': couponCode} : null);
      final data = res.data as Map<String, dynamic>;
      return (data['transaction'] as Map<String, dynamic>?) ?? data;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<LaundryBookingModel> confirmPayment(String id) async {
    try {
      final res = await _client.post('/laundry/bookings/$id/payment/confirm');
      return LaundryBookingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Hub staff ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMyStaffHubs() async {
    try {
      final res = await _client.get('/laundry/hub-staff/me');
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<LaundryBookingModel>> getHubQueue(String hubId) async {
    try {
      final res = await _client.get('/laundry/hub/$hubId/queue');
      return (res.data as List).map((e) => LaundryBookingModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> receiveBooking(String id) async {
    try {
      await _client.post('/laundry/bookings/$id/receive');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> weighIn(String id, double actualLoad) async {
    try {
      await _client.post('/laundry/bookings/$id/weigh', data: {'actualLoad': actualLoad});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> updateStage(String id, String status) async {
    try {
      await _client.post('/laundry/bookings/$id/status', data: {'status': status});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
