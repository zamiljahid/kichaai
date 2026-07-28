import '../core/network/api_client.dart';
import '../models/commerce_model.dart';

class CommerceService {
  static final CommerceService instance = CommerceService._();
  CommerceService._();

  final _client = ApiClient.instance.dio;

  // ── Provider Services ─────────────────────────────────────────────

  Future<ProviderServiceModel> createProviderService({
    required String serviceTypeId,
    String? title,
    String? description,
    bool isActive = true,
  }) async {
    try {
      final res = await _client.post('/commerce/provider-services', data: {
        'serviceTypeId': serviceTypeId,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        'isActive': isActive,
      });
      return ProviderServiceModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<ProviderServiceModel>> listProviderServices({
    String? providerId,
    String? serviceTypeId,
    String? status,
  }) async {
    try {
      final res = await _client.get('/commerce/provider-services', queryParameters: {
        if (providerId != null) 'providerId': providerId,
        if (serviceTypeId != null) 'serviceTypeId': serviceTypeId,
        if (status != null) 'status': status,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => ProviderServiceModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<ProviderServiceModel> getProviderService(String id) async {
    try {
      final res = await _client.get('/commerce/provider-services/$id');
      return ProviderServiceModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Offerings ─────────────────────────────────────────────────────

  Future<OfferingModel> createOffering({
    required String providerServiceId,
    required String title,
    required double price,
    String? description,
    int? durationMinutes,
  }) async {
    try {
      final res = await _client.post('/commerce/offerings', data: {
        'providerServiceId': providerServiceId,
        'title': title,
        'price': price,
        if (description != null) 'description': description,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
      });
      return OfferingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<OfferingModel>> listOfferings({
    String? providerServiceId,
    String? status,
  }) async {
    try {
      final res = await _client.get('/commerce/offerings', queryParameters: {
        if (providerServiceId != null) 'providerServiceId': providerServiceId,
        if (status != null) 'status': status,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => OfferingModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<OfferingModel> getOffering(String id) async {
    try {
      final res = await _client.get('/commerce/offerings/$id');
      return OfferingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<ReviewModel>> getOfferingReviews(String offeringId) async {
    try {
      final res = await _client.get('/commerce/offerings/$offeringId/reviews');
      final list = res.data as List<dynamic>;
      return list
          .map((e) => ReviewModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Bookings ──────────────────────────────────────────────────────

  Future<BookingModel> createBooking({
    required String offeringId,
    required DateTime scheduledAt,
    String? addressId,
    String? notes,
    int quantity = 1,
  }) async {
    try {
      final res = await _client.post('/commerce/bookings', data: {
        'offeringId': offeringId,
        'scheduledAt': scheduledAt.toIso8601String(),
        if (addressId != null) 'addressId': addressId,
        if (notes != null) 'notes': notes,
        'quantity': quantity,
      });
      return BookingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<BookingModel>> listBookings({
    String? customerId,
    String? offeringId,
    String? status,
  }) async {
    try {
      final res = await _client.get('/commerce/bookings', queryParameters: {
        if (customerId != null) 'customerId': customerId,
        if (offeringId != null) 'offeringId': offeringId,
        if (status != null) 'status': status,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => BookingModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<BookingModel> getBooking(String id) async {
    try {
      final res = await _client.get('/commerce/bookings/$id');
      return BookingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<BookingModel> updateBookingStatus(String id, String status) async {
    try {
      final res = await _client.patch(
        '/commerce/bookings/$id/status',
        data: {'status': status},
      );
      return BookingModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Reviews ───────────────────────────────────────────────────────

  Future<ReviewModel> createReview({
    required String bookingId,
    required String offeringId,
    required int rating,
    String? comment,
  }) async {
    try {
      final res = await _client.post('/commerce/reviews', data: {
        'bookingId': bookingId,
        'offeringId': offeringId,
        'rating': rating,
        if (comment != null) 'comment': comment,
      });
      return ReviewModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
