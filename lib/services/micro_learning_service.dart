import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../models/micro_learning_model.dart';

class MicroLearningService {
  static final MicroLearningService instance = MicroLearningService._();
  MicroLearningService._();

  final _client = ApiClient.instance.dio;

  /// The categories the backend actually files courses under. The screen used to carry its
  /// own hardcoded list (tech / arts / lifestyle) which never matched the stored values
  /// (Technology / Business / Design / Language), so every chip returned an empty list.
  Future<List<Map<String, String>>> listCategories() async {
    try {
      final res = await _client.get('/micro-learning/categories');
      return (res.data as List<dynamic>)
          .map((e) => (e as Map<String, dynamic>).map((k, v) => MapEntry(k, '$v')))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<CourseModel>> listCourses({int limit = 20, String? category, String? search}) async {
    try {
      final res = await _client.get('/micro-learning/courses', queryParameters: {
        'limit': limit.toString(),
        if (category != null) 'category': category,
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => CourseModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<CourseModel> getCourse(String id) async {
    try {
      final res = await _client.get('/micro-learning/courses/$id');
      return CourseModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Instructor-only: who's enrolled in MY course (backend enforces ownership via JWT).
  Future<List<Map<String, dynamic>>> listCourseEnrollments(String courseId) async {
    try {
      final res = await _client.get('/micro-learning/courses/$courseId/enrollments');
      final list = res.data as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // Lessons are embedded in the course response from GET /micro-learning/courses/:id
  Future<List<LessonModel>> getLessons(String courseId) async {
    final course = await getCourse(courseId);
    return course.lessons;
  }

  /// Starts enrollment. Free courses come back already enrolled (`enrollment` set,
  /// `gatewayPageUrl` null); paid courses come back with a real SSLCommerz checkout URL to
  /// send the customer to — call [confirmEnrollment] once they've paid.
  Future<EnrollmentInitiation> initiateEnrollment({required String courseId, String? couponCode}) async {
    try {
      final res = await _client.post('/micro-learning/enrollments/initiate',
          data: {'courseId': courseId, if (couponCode != null) 'couponCode': couponCode});
      return EnrollmentInitiation.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Only grants access once the backend has independently verified a completed payment —
  /// throws (via ApiClient.mapError) if the payment hasn't landed yet.
  Future<EnrollmentModel> confirmEnrollment({required String courseId}) async {
    try {
      final res = await _client.post('/micro-learning/enrollments/confirm', data: {'courseId': courseId});
      final data = res.data as Map<String, dynamic>;
      return EnrollmentModel.fromJson(data['enrollment'] as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<EnrollmentModel>> myEnrollments(String userId) async {
    try {
      final res = await _client.get('/micro-learning/enrollments', queryParameters: {
        'userId': userId,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => EnrollmentModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> markLessonComplete({
    required String enrollmentId,
    required String lessonId,
  }) async {
    try {
      await _client.post('/micro-learning/progress/complete', data: {
        'enrollmentId': enrollmentId,
        'lessonId': lessonId,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Instructor authoring ──────────────────────────────────────────

  Future<List<CourseModel>> listMyCourses(String providerId) async {
    try {
      final res = await _client.get('/micro-learning/courses/provider/$providerId');
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (list as List).map((e) => CourseModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<CourseModel> createCourse({
    required String providerId,
    required String providerName,
    required String title,
    required String description,
    required String category,
    required double price,
    double? discountPrice,
    String language = 'bn',
    // 'recorded' (default) or 'live_cohort' — recorded sells pre-made video lessons
    // immediately; live_cohort holds access until the provider runs a live session.
    String? type,
    int? minEnrollments,
  }) async {
    try {
      final res = await _client.post('/micro-learning/courses', data: {
        'providerId': providerId,
        'providerName': providerName,
        'title': title,
        'description': description,
        'category': category,
        'price': price,
        if (discountPrice != null) 'discountPrice': discountPrice,
        'language': language,
        if (type != null) 'type': type,
        if (minEnrollments != null) 'minEnrollments': minEnrollments,
      });
      return CourseModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Instructor: update course metadata (title/description/category/price/
  /// discountPrice/language/thumbnailUrl/status). Send only what changed.
  Future<CourseModel> updateCourse(String courseId, Map<String, dynamic> changes) async {
    try {
      final res = await _client.patch('/micro-learning/courses/$courseId', data: changes);
      return CourseModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<LessonModel> addLesson({
    required String courseId,
    required String title,
    String? description,
    String? videoUrl,
    String? rawVideoKey,
    int? durationMins,
    int? sortOrder,
    bool isFree = false,
  }) async {
    try {
      final res = await _client.post('/micro-learning/lessons', data: {
        'courseId': courseId,
        'title': title,
        if (description != null) 'description': description,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (rawVideoKey != null) 'rawVideoKey': rawVideoKey,
        if (durationMins != null) 'durationMins': durationMins,
        if (sortOrder != null) 'sortOrder': sortOrder,
        'isFree': isFree,
      });
      return LessonModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> updateLesson(String lessonId, Map<String, dynamic> changes) async {
    try {
      await _client.patch('/micro-learning/lessons/$lessonId', data: changes);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> deleteLesson(String lessonId) async {
    try {
      await _client.delete('/micro-learning/lessons/$lessonId');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> scheduleLiveSession(String courseId, {
    required String scheduledAt,
    required String meetingUrl,
  }) async {
    try {
      await _client.post('/micro-learning/courses/$courseId/live-session/schedule', data: {
        'scheduledAt': scheduledAt,
        'meetingUrl': meetingUrl,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> completeLiveSession(String courseId, {String? recordingUrl}) async {
    try {
      await _client.post('/micro-learning/courses/$courseId/live-session/complete', data: {
        if (recordingUrl != null) 'recordingUrl': recordingUrl,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Null if no live session exists yet (course hasn't reached minEnrollments and the
  /// provider hasn't requested one early either).
  Future<Map<String, dynamic>?> getLiveSession(String courseId) async {
    try {
      final res = await _client.get('/micro-learning/courses/$courseId/live-session');
      return res.data == null ? null : Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Provider's own discretion — opens the "schedule" step before minEnrollments is reached.
  /// live_cohort courses only (backend 403s otherwise).
  Future<void> requestEarlyLiveSession(String courseId) async {
    try {
      await _client.post('/micro-learning/courses/$courseId/live-session/request-early');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Protected video upload/playback ───────────────────────────────
  // Videos never touch our own backend as bytes: the provider uploads straight to our
  // bucket via a presigned PUT URL, and students only ever get a short-lived presigned
  // playback link — never the permanent underlying URL.

  /// Step 1 of uploading a lesson video — get a place to PUT the raw file.
  Future<Map<String, String>> requestVideoUploadUrl({
    required String courseId,
    required String filename,
    String? contentType,
  }) async {
    try {
      final res = await _client.post('/micro-learning/lessons/upload-url', data: {
        'courseId': courseId,
        'filename': filename,
        if (contentType != null) 'contentType': contentType,
      });
      final data = res.data as Map<String, dynamic>;
      return {'uploadUrl': data['uploadUrl'] as String, 'key': data['key'] as String};
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Step 2 — PUT the raw bytes straight to the bucket. Deliberately a bare Dio instance:
  /// this URL is a presigned S3 link, not our API, so no auth header / base URL belongs here.
  Future<void> uploadVideoBytes(String uploadUrl, Uint8List bytes, {String? contentType}) async {
    try {
      await Dio().put(
        uploadUrl,
        data: bytes,
        options: Options(headers: {
          if (contentType != null) 'Content-Type': contentType,
          Headers.contentLengthHeader: bytes.length,
        }),
      );
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// status: 'ready' (url set), 'processing' (watermarking in progress — retry shortly),
  /// 'failed', or 'none' (lesson has no video at all).
  Future<Map<String, dynamic>> getLessonPlayUrl(String lessonId) async {
    try {
      final res = await _client.get('/micro-learning/lessons/$lessonId/play-url');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
