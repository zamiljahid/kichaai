import '../core/network/api_client.dart';
import '../models/dispatch_model.dart';

class DispatchService {
  static final DispatchService instance = DispatchService._();
  DispatchService._();

  final _client = ApiClient.instance.dio;

  // ── Jobs ──────────────────────────────────────────────────────────

  Future<JobModel> createJob({
    required String customerId,
    required String serviceTypeId,
    required String serviceKind,
    required String title,
    required double pickupLatitude,
    required double pickupLongitude,
    String? customerNameSnapshot,
    String? customerPhoneSnapshot,
    String? description,
    String? pickupAddressSnapshot,
    double? estimatedAmount,
    String? preferredProviderId,
    String urgencyLevel = 'normal',
    String? taskCategory,     // technician jobs — backend resolves estimatedAmount from this
    String? specialization,   // technician jobs — narrows matching to techs who ticked this type
    String? legalArea,        // lawyer only — required for a lawyer consultation
    String? legalService,     // lawyer only — decides which role is eligible
    String? consultationMode, // lawyer only — phone | video | chat | in_person
    DateTime? eventDate,      // advance-booking (photographer/cinematographer/makeup_artist) —
                              // presence flips the backend to browse-and-confirm instead of nearest-first
    int? estimatedDurationHours, // advance-booking only — job duration for the calendar slot
  }) async {
    try {
      final res = await _client.post('/dispatch/jobs', data: {
        'customerId': customerId,
        'serviceTypeId': serviceTypeId,
        'serviceKind': serviceKind,
        'title': title,
        'pickupLatitude': pickupLatitude,
        'pickupLongitude': pickupLongitude,
        'urgencyLevel': urgencyLevel,
        if (customerNameSnapshot != null) 'customerNameSnapshot': customerNameSnapshot,
        if (customerPhoneSnapshot != null) 'customerPhoneSnapshot': customerPhoneSnapshot,
        if (description != null) 'description': description,
        if (pickupAddressSnapshot != null) 'pickupAddressSnapshot': pickupAddressSnapshot,
        if (estimatedAmount != null) 'estimatedAmount': estimatedAmount,
        if (preferredProviderId != null) 'preferredProviderId': preferredProviderId,
        if (taskCategory != null) 'taskCategory': taskCategory,
        if (specialization != null) 'specialization': specialization,
        if (legalArea != null) 'legalArea': legalArea,
        if (legalService != null) 'legalService': legalService,
        if (consultationMode != null) 'consultationMode': consultationMode,
        if (eventDate != null) 'eventDate': eventDate.toUtc().toIso8601String(),
        if (estimatedDurationHours != null) 'estimatedDurationHours': estimatedDurationHours,
      });
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Advance-booking: browse providers who are free for a specific slot ─
  /// GET /dispatch/providers/available — returns everyone free at [eventDate]
  /// with a portfolio card. Backend filters by [serviceKind] and applies any
  /// per-provider rejects the customer has already made on this job.
  Future<List<AvailableProviderModel>> listAvailableProviders({
    required String serviceKind,
    required DateTime eventDate,
    String? specialty,
    int? limit,
    int? offset,
  }) async {
    try {
      final res = await _client.get('/dispatch/providers/available', queryParameters: {
        'serviceKind': serviceKind,
        'eventDate': eventDate.toUtc().toIso8601String(),
        if (specialty != null) 'specialty': specialty,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => AvailableProviderModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }


  /// GET /dispatch/providers/:id/availability — a photographer/cinematographer/
  /// makeup_artist's booked event slots + self-marked days off in a date window.
  /// Free days are just the gaps — the caller renders a calendar.
  /// Returns {bookedSlots: [...], blockedDates: [...]}.
  Future<Map<String, dynamic>> getProviderAvailability(
    String providerId, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _client.get('/dispatch/providers/$providerId/availability', queryParameters: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      });
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : {'bookedSlots': [], 'blockedDates': []};
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Provider marks a day off — excluded from advance-booking browse/confirm.
  Future<void> blockDate(DateTime date) async {
    try {
      await _client.post('/dispatch/me/blocked-dates', data: {'date': _dateOnly(date)});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Provider undoes a self-marked day off.
  Future<void> unblockDate(DateTime date) async {
    try {
      await _client.delete('/dispatch/me/blocked-dates/${_dateOnly(date)}');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Lawyer consultation — customer confirm/cancel flow ────────────

  /// How many eligible lawyers are online right now for the given area+service.
  /// Runs the SAME eligibility rules as the broadcast (verified, role, daily cap),
  /// so the badge can never disagree with who actually gets notified.
  /// Returns null on any failure — the badge is a nice-to-have; hide it, never block.
  Future<int?> countOnlineLawyers({String? legalArea, String? legalService}) async {
    try {
      final res = await _client.get('/dispatch/lawyers/online-count', queryParameters: {
        if (legalArea != null) 'legalArea': legalArea,
        if (legalService != null) 'legalService': legalService,
      });
      final data = res.data;
      if (data is Map && data['count'] is num) return (data['count'] as num).toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// How many technicians of the picked specialization are online near the
  /// given coordinates. Mirrors the lawyer badge: null on any failure so the
  /// UI hides the badge instead of blocking the flow.
  Future<int?> countOnlineTechnicians({
    required String specialization,
    double? lat,
    double? lon,
  }) async {
    try {
      final res = await _client.get(
        '/dispatch/technicians/online-count-new',
        queryParameters: {
          'specialization': specialization,
          if (lat != null) 'lat': lat,
          if (lon != null) 'lon': lon,
        },
      );
      final data = res.data;
      if (data is Map && data['count'] is num) return (data['count'] as num).toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Matched candidate lawyer(s) for a job, each with the profile card the
  /// customer reviews before confirming (rating, cases-won, fee, role).
  Future<Map<String, dynamic>> getJobCandidates(String jobId) async {
    try {
      final res = await _client.get('/dispatch/jobs/$jobId/candidates');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Customer confirms the presented provider → locks the job.
  /// Customer locks in the chosen provider. For a lawyer VIDEO consultation the backend
  /// generates the Google Meet link here, so the returned job carries `meetLink`.
  Future<JobModel> confirmProvider(String jobId, String providerId) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/confirm-provider', data: {'providerId': providerId});
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Customer skips the presented provider → exclude + present the next one.
  Future<Map<String, dynamic>> rejectProvider(String jobId, String providerId, {String? reason}) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/reject-provider', data: {
        'providerId': providerId,
        if (reason != null) 'reason': reason,
      });
      return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Legal-assistant consultation escalates to an advocate (new advocate-only job).
  Future<Map<String, dynamic>> referToAdvocate(String jobId, {String? legalService}) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/refer-advocate', data: {
        if (legalService != null) 'legalService': legalService,
      });
      return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<JobModel>> listJobs({
    String? status,
    String? serviceKind,
    String? customerId,
    String? assignedProviderId,
  }) async {
    try {
      final res = await _client.get('/dispatch/jobs', queryParameters: {
        if (status != null) 'status': status,
        if (serviceKind != null) 'serviceKind': serviceKind,
        if (customerId != null) 'customerId': customerId,
        if (assignedProviderId != null) 'assignedProviderId': assignedProviderId,
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => JobModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<JobModel> getJob(String id) async {
    try {
      final res = await _client.get('/dispatch/jobs/$id');
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Customer confirms the accepted provider — reveals both parties' phone numbers in
  /// subsequent getJob() responses. Not available for lawyer jobs (Meet-only by design).
  /// On-demand jobs only — NOT the same as confirmProvider() above, which is the
  /// advance-booking provider-selection endpoint (different route, different purpose).
  Future<JobModel> revealJobContact(String jobId) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/reveal-contact');
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Provider: post my current location for an active job — this is what feeds
  /// the customer's live tracking map. providerId comes from the JWT server-side.
  Future<void> trackLocation(String jobId, double latitude, double longitude) async {
    try {
      await _client.post('/dispatch/jobs/$jobId/track', data: {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (_) {
      // Best-effort — a missed ping must never break the provider's job flow.
    }
  }

  Future<JobModel> updateJobStatus(String id, String status, {double? finalAmount}) async {
    try {
      final res = await _client.patch('/dispatch/jobs/$id/status', data: {
        'status': status,
        if (finalAmount != null) 'finalAmount': finalAmount,
      });
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Cancels a job. Returns the penalty outcome (card / commission-fee / temp-ban)
  /// so the caller can tell the provider exactly what happened.
  Future<CancelResult> cancelJob(String id) async {
    try {
      final res = await _client.post('/dispatch/jobs/$id/cancel');
      final data = res.data;
      return data is Map<String, dynamic>
          ? CancelResult.fromJson(data)
          : const CancelResult();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Reverse-geocode coordinates to a Bengali address (null if unresolvable).
  Future<String?> reverseGeocode(double lat, double lon) async {
    try {
      final res = await _client.get('/dispatch/geo/reverse',
          queryParameters: {'lat': lat, 'lon': lon});
      return (res.data as Map<String, dynamic>)['address'] as String?;
    } catch (_) {
      return null; // address is nice-to-have — never block the flow on it
    }
  }

  /// Provider's live broadcast job offers (open jobs where I have a pending assignment).
  Future<List<JobOffer>> getMyOffers() async {
    try {
      final res = await _client.get('/dispatch/me/offers');
      final list = res.data as List<dynamic>;
      return list
          .map((e) => JobOffer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Provider's dispatch standing — red cards, temp-ban, unpaid dues.
  Future<ProviderStanding> getMyStanding() async {
    try {
      final res = await _client.get('/dispatch/me/standing');
      return ProviderStanding.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Customer: cancelled jobs awaiting my "did the provider still do the work?" answer.
  Future<List<CancelReview>> getMyCancelReviews() async {
    try {
      final res = await _client.get('/dispatch/cancel-reviews/mine');
      final list = res.data as List<dynamic>;
      return list
          .map((e) => CancelReview.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Customer answers whether the provider still did the work off-app ('yes' charges the fee).
  Future<void> answerCancelReview(String jobId, bool didProviderWork) async {
    try {
      await _client.post('/dispatch/jobs/$jobId/cancel-review',
          data: {'didProviderWork': didProviderWork});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Job Lifecycle (OTP + Photos) ──────────────────────────────────

  /// Returns the dev-only OTP echo (only present when the backend has
  /// ALLOW_ACTOR_OVERRIDE=true — there's no real SMS provider in test envs,
  /// so this is how a tester sees the code without a second phone).
  Future<String?> requestStart(String jobId) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/request-start');
      final data = res.data;
      return data is Map ? data['devOtp'] as String? : null;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> confirmStart(String jobId, String otp) async {
    try {
      await _client.post('/dispatch/jobs/$jobId/confirm-start', data: {'otp': otp});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> uploadJobPhoto(String jobId, {
    required String photoType,
    required String photoUrl,
  }) async {
    try {
      await _client.post('/dispatch/jobs/$jobId/upload-photo', data: {
        'photoType': photoType,
        'photoUrl': photoUrl,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Same dev-only OTP echo as requestStart — see its doc comment.
  Future<String?> requestCompletion(String jobId) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/request-completion');
      final data = res.data;
      return data is Map ? data['devOtp'] as String? : null;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> confirmCompletion(String jobId, String otp) async {
    try {
      await _client.post('/dispatch/jobs/$jobId/confirm-completion', data: {'otp': otp});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> rateJob(String jobId, {required int rating, String? review}) async {
    try {
      await _client.post('/dispatch/jobs/$jobId/rate', data: {
        'rating': rating,
        if (review != null) 'review': review,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── CUSTOM-pricing quote flow ─────────────────────────────────────
  /// Provider submits an on-site quote after inspecting a CUSTOM-priced job.
  Future<JobModel> submitQuote(String jobId, {required double quotedAmount}) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/quote', data: {
        'quotedAmount': quotedAmount,
      });
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Customer approves or rejects the provider's quote. Rejecting cancels the
  /// job — only the visiting fee is owed.
  Future<JobModel> respondToQuote(String jobId, {required bool approved, String? rejectionReason}) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/quote/respond', data: {
        'approved': approved,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      });
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Provider task-pricing preference (FIXED / CUSTOM) ──────────────
  /// Platform-set prices per task category (fixedPrice + visitingFee).
  Future<List<Map<String, dynamic>>> getTaskCategoryRates() async {
    try {
      final res = await _client.get('/dispatch/task-category-rates',
          queryParameters: {'isActive': 'true', 'limit': 100, 'offset': 0});
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (list as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// My pricing-mode choices per task category.
  Future<List<Map<String, dynamic>>> getMyPricingPreferences() async {
    try {
      final res = await _client.get('/dispatch/provider/task-pricing-preference/me',
          queryParameters: {'limit': 100, 'offset': 0});
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (list as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Choose FIXED (platform rate) or CUSTOM (own on-site quote) for a category.
  Future<Map<String, dynamic>> setPricingPreference({
    required String taskCategory,
    required String mode, // 'FIXED' | 'CUSTOM'
  }) async {
    try {
      final res = await _client.patch('/dispatch/provider/task-pricing-preference', data: {
        'taskCategory': taskCategory,
        'mode': mode,
      });
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Lawyer consultation — opinion + case documents ────────────────
  /// Lawyer submits the written opinion, completing the consultation job.
  Future<JobModel> submitOpinion(String jobId, {
    required String opinionSummary,
    String? opinionAdvice,
    String? opinionNextSteps,
  }) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/opinion', data: {
        'opinionSummary': opinionSummary,
        if (opinionAdvice != null) 'opinionAdvice': opinionAdvice,
        if (opinionNextSteps != null) 'opinionNextSteps': opinionNextSteps,
      });
      return JobModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Customer uploads a case document (fileUrl) for a lawyer consultation.
  Future<Map<String, dynamic>> addConsultationDocument(String jobId, {
    required String fileUrl,
    String? docType,
  }) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/consultation-documents', data: {
        'fileUrl': fileUrl,
        if (docType != null) 'docType': docType,
      });
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<Map<String, dynamic>>> listConsultationDocuments(String jobId) async {
    try {
      final res = await _client.get('/dispatch/jobs/$jobId/consultation-documents',
          queryParameters: {'limit': 50, 'offset': 0});
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (list as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Assignments ───────────────────────────────────────────────────

  Future<AssignmentModel> assignJob(
    String jobId, {
    required String providerId,
    String? providerNameSnapshot,
    String? providerPhoneSnapshot,
    double? providerRatingSnapshot,
    double? distanceKm,
  }) async {
    try {
      final res = await _client.post('/dispatch/jobs/$jobId/assign', data: {
        'providerId': providerId,
        if (providerNameSnapshot != null) 'providerNameSnapshot': providerNameSnapshot,
        if (providerPhoneSnapshot != null) 'providerPhoneSnapshot': providerPhoneSnapshot,
        if (providerRatingSnapshot != null) 'providerRatingSnapshot': providerRatingSnapshot,
        if (distanceKm != null) 'distanceKm': distanceKm,
      });
      return AssignmentModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<AssignmentModel>> listAssignments(String jobId) async {
    try {
      final res = await _client.get('/dispatch/jobs/$jobId/assignments');
      final list = res.data as List<dynamic>;
      return list.map((e) => AssignmentModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Responds to a broadcast assignment. On accept of a lawyer video
  /// consultation the response carries the generated `meetLink`.
  Future<Map<String, dynamic>> respondToAssignment(
    String assignmentId, {
    required String response,
    required String jobId,
  }) async {
    try {
      final res = await _client.post('/dispatch/assignments/$assignmentId/respond', data: {
        'response': response,
        'jobId': jobId,
      });
      return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Live Sessions ─────────────────────────────────────────────────

  Future<void> startSession({
    required String providerId,
    required List<String> serviceKinds,
    // Optional: a lawyer works remotely, so going online must not depend on GPS.
    double? currentLatitude,
    double? currentLongitude,
    String? providerNameSnapshot,
    double? providerAvgRatingSnapshot,
    String? providerLevel,
    String? profileImageUrl,
    List<String>? legalAreas,
    List<String>? legalServices,
    String? legalRole,
    bool? verifiedSnapshot,
    double? consultationFee,
    // Technician specialization codes (e.g. ['AC','REFRIGERATOR']). Without
    // these an online technician has no specialization snapshot and receives
    // NO specialized jobs — matching silently drops them.
    List<String>? specializations,
  }) async {
    try {
      await _client.post('/dispatch/sessions/start', data: {
        'providerId': providerId,
        'serviceKinds': serviceKinds,
        // Backend contract is latitude/longitude (it also accepts the current* aliases).
        if (currentLatitude != null) 'latitude': currentLatitude,
        if (currentLongitude != null) 'longitude': currentLongitude,
        if (providerNameSnapshot != null) 'providerNameSnapshot': providerNameSnapshot,
        if (providerAvgRatingSnapshot != null)
          'providerAvgRatingSnapshot': providerAvgRatingSnapshot,
        if (providerLevel != null) 'providerLevel': providerLevel,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (legalAreas != null) 'legalAreas': legalAreas,
        if (legalServices != null) 'legalServices': legalServices,
        if (legalRole != null) 'legalRole': legalRole,
        if (verifiedSnapshot != null) 'verifiedSnapshot': verifiedSnapshot,
        if (consultationFee != null) 'consultationFee': consultationFee,
        if (specializations != null) 'specializations': specializations,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> endSession({required String providerId}) async {
    try {
      await _client.post('/dispatch/sessions/end', data: {'providerId': providerId});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<LiveSessionModel> getMySession() async {
    try {
      final res = await _client.get('/dispatch/sessions/me');
      return LiveSessionModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> updateSessionLocation({
    required double latitude,
    required double longitude,
    String? jobId,
  }) async {
    try {
      await _client.post('/dispatch/sessions/location', data: {
        'latitude': latitude,
        'longitude': longitude,
        if (jobId != null) 'jobId': jobId,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Location Tracking ─────────────────────────────────────────────

  Future<void> updateLocation(String jobId, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _client.post('/dispatch/tracking/$jobId/location', data: {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> getJobLocation(String jobId) async {
    try {
      final res = await _client.get('/dispatch/tracking/$jobId/location');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Provider Search ───────────────────────────────────────────────

  Future<List<NearbyProviderModel>> searchProviders({
    String? serviceKind,
    double? lat,
    double? lon,
    double? radiusKm,
  }) async {
    try {
      final res = await _client.get('/dispatch/providers/search', queryParameters: {
        if (serviceKind != null) 'serviceKind': serviceKind,
        if (lat != null) 'lat': lat.toString(),
        if (lon != null) 'lon': lon.toString(),
        if (radiusKm != null) 'radiusKm': radiusKm.toString(),
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => NearbyProviderModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Rate Cards ────────────────────────────────────────────────────

  Future<List<RateCardModel>> getRateCards({String? serviceKind}) async {
    try {
      final res = await _client.get('/dispatch/rate-cards', queryParameters: {
        if (serviceKind != null) 'serviceKind': serviceKind,
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => RateCardModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Task Runner ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTaskRunnerCategories() async {
    try {
      final res = await _client.get('/dispatch/task-runner/categories');
      return (res.data as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> createBabySittingTask(
      Map<String, dynamic> data) async {
    try {
      final res = await _client.post('/dispatch/task-runner/baby-sitting', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Scrap Collection ──────────────────────────────────────────────

  Future<ScrapRequestModel> createScrapRequest({
    required String address,
    required List<String> categories,
    double? estimatedWeightKg,
    String? customerName,
    String? customerPhone,
  }) async {
    try {
      final res = await _client.post('/dispatch/scrap', data: {
        'address': address,
        'categories': categories,
        if (estimatedWeightKg != null) 'estimatedWeightKg': estimatedWeightKg,
        if (customerName != null) 'customerName': customerName,
        if (customerPhone != null) 'customerPhone': customerPhone,
      });
      return ScrapRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Surge Pricing ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> estimateSurge(Map<String, dynamic> data) async {
    try {
      final res = await _client.post('/dispatch/surge/estimate', data: data);
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getActiveSurgeRules({String? serviceType}) async {
    try {
      final res = await _client.get('/dispatch/surge', queryParameters: {
        if (serviceType != null) 'serviceType': serviceType,
      });
      return (res.data as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
