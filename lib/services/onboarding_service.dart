import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

class OnboardingService {
  static final OnboardingService instance = OnboardingService._();
  OnboardingService._();

  final _client = ApiClient.instance.dio;

  // ── Service discovery ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getServiceTypes() async {
    try {
      final res = await _client.get('/onboarding/service-types');
      return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> bulkApply(List<String> serviceTypeIds) async {
    try {
      await _client.post('/onboarding/applications/bulk', data: {
        'serviceTypeIds': serviceTypeIds,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getMyServices() async {
    try {
      final userId = await ApiClient.getUserId();
      final res = await _client.get(
        '/onboarding/my-services',
        options: Options(headers: {'x-user-id': userId}),
      );
      return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitProviderProfile({
    required String serviceType,
    required List<String> skills,
    required int experienceYears,
    required String bio,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': serviceType,
        'skills': skills,
        'experienceYears': experienceYears,
        'bio': bio,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitCaregiverProfile({
    required String certificateUrl,
    required String certificateType,
    required int experienceYears,
    required List<String> specializations,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'caregiver',
        'certificateUrl': certificateUrl,
        'certificateType': certificateType,
        'experienceYears': experienceYears,
        'specializations': specializations,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitLawyerProfile({
    required String barCertificateUrl,
    required String barEnrollmentNumber,
    required List<String> caseAreas,
    required List<String> courtJurisdiction,
    required int experienceYears,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'lawyer',
        'barCertificateUrl': barCertificateUrl,
        'barEnrollmentNumber': barEnrollmentNumber,
        'caseAreas': caseAreas,
        'courtJurisdiction': courtJurisdiction,
        'experienceYears': experienceYears,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Legal provider (advocate / legal assistant) — two-tier flow ───
  /// Roles, areas & services (with tier eligibility). Pass [role] to get only
  /// the services that role may offer.
  Future<Map<String, dynamic>> getLegalOptions({String? role}) async {
    try {
      final res = await _client.get(
        '/legal/options',
        queryParameters: (role != null && role.isNotEmpty) ? {'role': role} : null,
      );
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitLegalProfile({
    required String legalRole, // advocate | legal_assistant
    required List<String> caseAreas,
    required List<String> servicesOffered,
    required List<String> consultationModes,
    required int experienceYears,
    double? proposedFee,
    int? casesWon,
    String? barCertificateUrl,
    String? barEnrollmentNumber,
    List<String>? courtJurisdiction,
    String? llbUniversity,
    String? llbStatus,
  }) async {
    try {
      await _client.post('/onboarding/legal-profile', data: {
        'legalRole': legalRole,
        'caseAreas': caseAreas,
        'servicesOffered': servicesOffered,
        'consultationModes': consultationModes,
        'experienceYears': experienceYears,
        if (proposedFee != null) 'proposedFee': proposedFee,
        if (casesWon != null) 'casesWon': casesWon,
        if (barCertificateUrl != null) 'barCertificateUrl': barCertificateUrl,
        if (barEnrollmentNumber != null) 'barEnrollmentNumber': barEnrollmentNumber,
        if (courtJurisdiction != null) 'courtJurisdiction': courtJurisdiction,
        if (llbUniversity != null) 'llbUniversity': llbUniversity,
        if (llbStatus != null) 'llbStatus': llbStatus,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitPhotographyProfile({
    required String sampleDriveUrl,
    required String cameraBrand,
    required String cameraModel,
    required String cameraBodyPhotoUrl,
    required String achievements,
    required List<Map<String, String>> lenses,
    required List<String> equipment,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'photographer',
        'sampleDriveUrl': sampleDriveUrl,
        'cameraBrand': cameraBrand,
        'cameraModel': cameraModel,
        'cameraBodyPhotoUrl': cameraBodyPhotoUrl,
        'achievements': achievements,
        'lenses': lenses,
        'equipment': equipment,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitCinemaProfile({
    required String sampleDriveUrl,
    required String reelUrl,
    required String cameraBrand,
    required String cameraModel,
    required String cameraBodyPhotoUrl,
    required String droneModel,
    required String gimbalModel,
    required List<String> shootingStyles,
    required List<String> editingSoftware,
    required List<Map<String, String>> lenses,
    required List<String> equipment,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'cinematographer',
        'sampleDriveUrl': sampleDriveUrl,
        'reelUrl': reelUrl,
        'cameraBrand': cameraBrand,
        'cameraModel': cameraModel,
        'cameraBodyPhotoUrl': cameraBodyPhotoUrl,
        'droneModel': droneModel,
        'gimbalModel': gimbalModel,
        'shootingStyles': shootingStyles,
        'editingSoftware': editingSoftware,
        'lenses': lenses,
        'equipment': equipment,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitTutorProfile({
    required List<String> subjectsTaught,
    required List<String> teachingLevels,
    required String universityIdUrl,
    required List<String> certificatesUrls,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'tutor',
        'subjectsTaught': subjectsTaught,
        'teachingLevels': teachingLevels,
        'universityIdUrl': universityIdUrl,
        'certificatesUrls': certificatesUrls,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitInstructorProfile({
    required List<String> expertiseTopics,
    required String universityIdUrl,
    required List<String> certificatesUrls,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'instructor',
        'expertiseTopics': expertiseTopics,
        'universityIdUrl': universityIdUrl,
        'certificatesUrls': certificatesUrls,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitPortfolioImages({required List<String> images}) async {
    try {
      await _client.post('/onboarding/portfolio', data: {'images': images});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitPetCareProfile({
    required List<String> petTypes,
    required int experienceYears,
    required String bio,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'pet_care',
        'petTypes': petTypes,
        'experienceYears': experienceYears,
        'bio': bio,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitMessOwnerProfile({
    String? universityIdUrl,
    String? jobIdUrl,
  }) async {
    try {
      await _client.post('/onboarding/provider-profile', data: {
        'serviceType': 'mess_owner',
        if (universityIdUrl != null) 'universityIdUrl': universityIdUrl,
        if (jobIdUrl != null) 'jobIdUrl': jobIdUrl,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitNidVerification({
    required String nidFrontUrl,
    required String nidBackUrl,
  }) async {
    try {
      await _client.post('/onboarding/nid', data: {
        'nidFrontUrl': nidFrontUrl,
        'nidBackUrl': nidBackUrl,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Document requirements flow ────────────────────────────────────
  /// Backend response: List<{documentTypeId, documentType: {code, name, ...}}>.
  /// `code` drives the UI (NID → image picker, PORTFOLIO → images-or-link).
  Future<List<Map<String, dynamic>>> getServiceTypeRequirements(String serviceTypeId) async {
    try {
      final res = await _client.get('/onboarding/service-type-requirements/$serviceTypeId');
      return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Uploads a base64-encoded file (no data-URI prefix). Returns the stored fileUrl.
  Future<String> uploadFile({
    required String fileBase64,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      final res = await _client.post('/onboarding/uploads', data: {
        'fileBase64': fileBase64,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      return (res.data as Map)['fileUrl'] as String;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Portfolio (photography/cinema) ──────────────────────────────────
  // POST /onboarding/portfolio needs an already-uploaded imageUrl (via
  // uploadFile above) + serviceType — it never accepted imageBase64 despite
  // what its docs used to say, so every call built on the old contract just
  // failed with a missing-field error from onboarding-service.

  Future<List<Map<String, dynamic>>> listPortfolioImages({String? serviceType}) async {
    try {
      final userId = await ApiClient.getUserId();
      final res = await _client.get('/onboarding/portfolio',
          queryParameters: {if (serviceType != null) 'serviceType': serviceType},
          options: Options(headers: {'x-user-id': userId}));
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (list as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<Map<String, dynamic>> uploadPortfolioImage({
    required String imageUrl,
    required String serviceType,
    String? caption,
  }) async {
    try {
      final userId = await ApiClient.getUserId();
      final res = await _client.post('/onboarding/portfolio',
          data: {'imageUrl': imageUrl, 'serviceType': serviceType, if (caption != null && caption.isNotEmpty) 'caption': caption},
          options: Options(headers: {'x-user-id': userId}));
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> setCoverPortfolioImage(String imageId) async {
    try {
      final userId = await ApiClient.getUserId();
      await _client.put('/onboarding/portfolio/$imageId/cover', options: Options(headers: {'x-user-id': userId}));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> deletePortfolioImage(String imageId) async {
    try {
      final userId = await ApiClient.getUserId();
      await _client.delete('/onboarding/portfolio/$imageId', options: Options(headers: {'x-user-id': userId}));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Registers a document record against a documentType; returns the new document id.
  Future<String> uploadDocument({
    required String providerId,
    required String documentTypeId,
    required String fileUrl,
    String? originalFileName,
    String? mimeType,
  }) async {
    try {
      final res = await _client.post('/onboarding/documents', data: {
        'providerId': providerId,
        'documentTypeId': documentTypeId,
        'fileUrl': fileUrl,
        if (originalFileName != null) 'originalFileName': originalFileName,
        if (mimeType != null) 'mimeType': mimeType,
      });
      return (res.data as Map)['id'] as String;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Creates the application shell (before documents are attached / submit).
  Future<String> createApplication({
    required String providerId,
    required String serviceTypeId,
    required String serviceTypeNameSnapshot,
  }) async {
    try {
      final res = await _client.post('/onboarding/applications', data: {
        'providerId': providerId,
        'serviceTypeId': serviceTypeId,
        'serviceTypeNameSnapshot': serviceTypeNameSnapshot,
      });
      return (res.data as Map)['id'] as String;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> attachDocument(String applicationId, String documentId) async {
    try {
      await _client.post('/onboarding/applications/$applicationId/documents', data: {
        'documentId': documentId,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> submitApplication(String applicationId) async {
    try {
      await _client.post('/onboarding/applications/$applicationId/submit');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
