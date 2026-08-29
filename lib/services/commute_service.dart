import '../core/network/api_client.dart';
import '../models/commute_model.dart';

class CommuteService {
  static final CommuteService instance = CommuteService._();
  CommuteService._();

  final _client = ApiClient.instance.dio;

  // ── Profile ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMyProfile() async {
    try {
      final res = await _client.get('/commute/profile/me');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> upsertMyProfile({String? defaultOriginArea, String? frequentInstitutionId, String? vehicleType}) async {
    try {
      await _client.post('/commute/profile/me', data: {
        if (defaultOriginArea != null) 'defaultOriginArea': defaultOriginArea,
        if (frequentInstitutionId != null) 'frequentInstitutionId': frequentInstitutionId,
        if (vehicleType != null) 'vehicleType': vehicleType,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> requestVerification() async {
    try {
      await _client.post('/commute/profile/request-verification');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // "Become a Commute Partner" — identity + vehicle documents + employment/student info.
  // employmentStatus is 'employed' or 'student'; pass the matching pair of fields.
  Future<void> submitPartnerDetails({
    required String ownNidUrl,
    required String parentNidUrl,
    required String vehicleRegistrationUrl,
    required String drivingLicenseUrl,
    required String vehicleLicenseUrl,
    required String employmentStatus,
    String? employerName,
    String? jobId,
    String? instituteName,
    String? studentId,
  }) async {
    try {
      await _client.post('/commute/profile/partner-details', data: {
        'ownNidUrl': ownNidUrl,
        'parentNidUrl': parentNidUrl,
        'vehicleRegistrationUrl': vehicleRegistrationUrl,
        'drivingLicenseUrl': drivingLicenseUrl,
        'vehicleLicenseUrl': vehicleLicenseUrl,
        'employmentStatus': employmentStatus,
        if (employerName != null) 'employerName': employerName,
        if (jobId != null) 'jobId': jobId,
        if (instituteName != null) 'instituteName': instituteName,
        if (studentId != null) 'studentId': studentId,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Institutions ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listInstitutions({String? area}) async {
    try {
      final res = await _client.get('/commute/institutions', queryParameters: {if (area != null) 'area': area});
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Driver-acting: Pattern A ──────────────────────────────────────

  Future<CommuteOfferModel> createOffer({
    required String originArea, String? destinationInstitutionId, String? destinationArea,
    required List<String> daysOfWeek, required String windowStart, required String windowEnd,
    required String vehicleType, required int seatsAvailable, required double costShareAmount,
    double? originLatitude, double? originLongitude,
    double? destinationLatitude, double? destinationLongitude,
  }) async {
    try {
      final res = await _client.post('/commute/offers', data: {
        'originArea': originArea,
        if (destinationInstitutionId != null) 'destinationInstitutionId': destinationInstitutionId,
        if (destinationArea != null) 'destinationArea': destinationArea,
        'daysOfWeek': daysOfWeek, 'windowStart': windowStart, 'windowEnd': windowEnd,
        'vehicleType': vehicleType, 'seatsAvailable': seatsAvailable, 'costShareAmount': costShareAmount,
        // Without the route as points the server cannot price a trip and falls back to
        // costShareAmount, so send them whenever the driver has dropped both pins.
        if (originLatitude != null) 'originLatitude': originLatitude,
        if (originLongitude != null) 'originLongitude': originLongitude,
        if (destinationLatitude != null) 'destinationLatitude': destinationLatitude,
        if (destinationLongitude != null) 'destinationLongitude': destinationLongitude,
      });
      return CommuteOfferModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<CommuteOfferModel>> listMyOffers() async {
    try {
      final res = await _client.get('/commute/offers/mine');
      return (res.data as List).map((e) => CommuteOfferModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<Map<String, dynamic>>> listOfferRequests(String offerId) async {
    try {
      final res = await _client.get('/commute/offers/$offerId/requests');
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> acceptRequest(String requestId) async {
    try {
      await _client.post('/commute/requests/$requestId/accept');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> declineRequest(String requestId) async {
    try {
      await _client.post('/commute/requests/$requestId/decline');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Passenger-acting: Pattern A ───────────────────────────────────

  Future<List<CommuteOfferModel>> searchOffers({String? originArea, String? destinationInstitutionId, String? destinationArea}) async {
    try {
      final res = await _client.get('/commute/offers/search', queryParameters: {
        if (originArea != null) 'originArea': originArea,
        if (destinationInstitutionId != null) 'destinationInstitutionId': destinationInstitutionId,
        if (destinationArea != null) 'destinationArea': destinationArea,
      });
      return (res.data as List).map((e) => CommuteOfferModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> requestToJoin(String offerId) async {
    try {
      await _client.post('/commute/offers/$offerId/request');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Shared: pairings ───────────────────────────────────────────────

  // Each entry also carries the parent offer (route/cost) under 'offer' — pairings have no
  // route fields of their own.
  Future<List<Map<String, dynamic>>> listMyPairings() async {
    try {
      final res = await _client.get('/commute/pairings/mine');
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> logTrip(String pairingId, DateTime tripDate, String status) async {
    try {
      await _client.post('/commute/pairings/$pairingId/trip-log', data: {'tripDate': tripDate.toIso8601String().split('T').first, 'status': status});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> endPairing(String pairingId) async {
    try {
      await _client.post('/commute/pairings/$pairingId/end');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── HALF-FARE TRIPS ───────────────────────────────────────────────────
  // A commute partner is not a monthly plan: the passenger pays half the normal fare for
  // that same route, every trip. Both sides have to accept that before any trip counts.

  Future<Map<String, dynamic>> agreeHalfFare(String pairingId) async {
    try {
      final res = await _client.post('/commute/pairings/$pairingId/agree-half-fare');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// What one trip costs — the full on-demand fare and the half the passenger actually pays.
  Future<Map<String, dynamic>> tripQuote(String pairingId) async {
    try {
      final res = await _client.get('/commute/pairings/$pairingId/trip-quote');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> recordCommuteTrip(String pairingId, {String? paymentMethod}) async {
    try {
      final res = await _client.post('/commute/pairings/$pairingId/trips', data: {
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
      });
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> listCommuteTrips(String pairingId, {int limit = 30, int offset = 0}) async {
    try {
      final res = await _client.get('/commute/pairings/$pairingId/trips',
          queryParameters: {'limit': limit, 'offset': offset});
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> settleCommuteTrip(String tripId) async {
    try {
      await _client.post('/commute/trips/$tripId/settle');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> initiatePairingPayment(String pairingId) async {
    try {
      final res = await _client.post('/commute/pairings/$pairingId/payment/initiate');
      final data = res.data as Map<String, dynamic>;
      return (data['transaction'] as Map<String, dynamic>?) ?? data;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> confirmPairingPayment(String pairingId) async {
    try {
      await _client.post('/commute/pairings/$pairingId/payment/confirm');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> initiateTripPayment(String tripId) async {
    try {
      final res = await _client.post('/commute/trips/$tripId/pay');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> confirmTripPayment(String tripId) async {
    try {
      await _client.post('/commute/trips/$tripId/pay/confirm');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> ratePairing(String pairingId, String ratedUserId, int rating, {String? comment}) async {
    try {
      await _client.post('/commute/pairings/$pairingId/rate', data: {'ratedUserId': ratedUserId, 'rating': rating, if (comment != null) 'comment': comment});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Pattern B: one-off (either direction) ─────────────────────────

  Future<OneOffCommutePostModel> createOneOffPost({
    required String postedByRole, required String originArea, String? destinationInstitutionId,
    String? destinationArea, required DateTime tripDateTime, int seatsOrNeed = 1, double? costShareAmount,
  }) async {
    try {
      final res = await _client.post('/commute/one-off', data: {
        'postedByRole': postedByRole, 'originArea': originArea,
        if (destinationInstitutionId != null) 'destinationInstitutionId': destinationInstitutionId,
        if (destinationArea != null) 'destinationArea': destinationArea,
        'tripDateTime': tripDateTime.toIso8601String(), 'seatsOrNeed': seatsOrNeed,
        if (costShareAmount != null) 'costShareAmount': costShareAmount,
      });
      return OneOffCommutePostModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<OneOffCommutePostModel>> searchOneOffPosts({String? originArea, String? destinationArea, String? postedByRole}) async {
    try {
      final res = await _client.get('/commute/one-off', queryParameters: {
        if (originArea != null) 'originArea': originArea,
        if (destinationArea != null) 'destinationArea': destinationArea,
        if (postedByRole != null) 'postedByRole': postedByRole,
      });
      return (res.data as List).map((e) => OneOffCommutePostModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> matchOneOffPost(String postId) async {
    try {
      final res = await _client.post('/commute/one-off/$postId/match');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> completeOneOffTrip(String tripId) async {
    try {
      await _client.post('/commute/one-off-trips/$tripId/complete');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> initiateOneOffPayment(String tripId) async {
    try {
      final res = await _client.post('/commute/one-off-trips/$tripId/payment/initiate');
      final data = res.data as Map<String, dynamic>;
      return (data['transaction'] as Map<String, dynamic>?) ?? data;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> confirmOneOffPayment(String tripId) async {
    try {
      await _client.post('/commute/one-off-trips/$tripId/payment/confirm');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> rateOneOffTrip(String tripId, String ratedUserId, int rating, {String? comment}) async {
    try {
      await _client.post('/commute/one-off-trips/$tripId/rate', data: {'ratedUserId': ratedUserId, 'rating': rating, if (comment != null) 'comment': comment});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
