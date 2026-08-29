// Prisma Decimal columns (price, discountPrice) serialize as STRINGS over JSON, not numbers —
// `(json['price'] as num?)` threw for every single course, which is why the courses screen
// always showed a generic error despite the API call itself succeeding.
double _asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

class CourseModel {
  final String id;
  final String title;
  final String? description;
  final String? providerName;
  final String? providerId;
  final String? coverImageUrl;
  final double price;
  final double? discountPrice;
  final double? rating;
  final int? reviewCount;
  final int? totalLessons;
  final int? totalDurationMins;
  final String? category;
  final String? level;
  final String? deliveryMode;
  final int? enrollmentCount;
  final String status;
  final String? rejectionReason;
  final List<LessonModel> lessons;

  const CourseModel({
    required this.id,
    required this.title,
    this.description,
    this.providerName,
    this.providerId,
    this.coverImageUrl,
    required this.price,
    this.discountPrice,
    this.rating,
    this.reviewCount,
    this.totalLessons,
    this.totalDurationMins,
    this.category,
    this.level,
    this.deliveryMode,
    this.enrollmentCount,
    this.status = 'active',
    this.rejectionReason,
    this.lessons = const [],
  });

  factory CourseModel.fromJson(Map<String, dynamic> json) => CourseModel(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        providerName: json['providerName'] as String?,
        providerId: json['providerId'] as String?,
        // Backend field is thumbnailUrl, not coverImageUrl — was always null.
        coverImageUrl: json['thumbnailUrl'] as String?,
        price: _asDouble(json['price']),
        discountPrice: _asDoubleOrNull(json['discountPrice']),
        // Backend field is avgRating, not rating — was always null (no stars ever showed).
        rating: _asDoubleOrNull(json['avgRating']),
        // Backend has no separate review count — reuse enrollment count as the closest signal
        // rather than a field that never existed.
        reviewCount: (json['totalEnrollments'] as num?)?.toInt(),
        totalLessons: json['totalLessons'] as int?,
        totalDurationMins: json['totalDurationMins'] as int?,
        category: json['category'] as String?,
        // Backend has no "level" field on courses (that's a technician-taxonomy concept) — leave
        // unmapped; the type/deliveryMode field below carries the real distinction (recorded/live).
        level: null,
        // Backend field is "type" (recorded/live), not deliveryMode — was always null.
        deliveryMode: json['type'] as String?,
        enrollmentCount: (json['totalEnrollments'] as num?)?.toInt(),
        status: json['status'] as String? ?? 'active',
        rejectionReason: json['rejectionReason'] as String?,
        lessons: (json['lessons'] as List<dynamic>?)
                ?.map((e) => LessonModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class LessonModel {
  final String id;
  final String courseId;
  final String title;
  final String? videoUrl;
  final int? durationMinutes;
  final bool isFree;
  final int sortOrder;
  final String? description;
  // none = no video yet; uploaded/processing = watermarking in progress (not playable
  // yet); ready = playable; failed = falls back to the un-watermarked upload.
  final String videoProcessingStatus;

  const LessonModel({
    required this.id,
    required this.courseId,
    required this.title,
    this.videoUrl,
    this.durationMinutes,
    this.isFree = false,
    this.sortOrder = 0,
    this.description,
    this.videoProcessingStatus = 'none',
  });

  factory LessonModel.fromJson(Map<String, dynamic> json) => LessonModel(
        id: json['id'] as String,
        courseId: json['courseId'] as String? ?? '',
        title: json['title'] as String,
        videoUrl: json['videoUrl'] as String?,
        // Backend field is durationMins, not durationMinutes — was always null, so every
        // lesson duration silently showed as blank everywhere it was displayed.
        durationMinutes: json['durationMins'] as int? ?? json['durationMinutes'] as int?,
        isFree: json['isFree'] as bool? ?? false,
        sortOrder: json['sortOrder'] as int? ?? json['order'] as int? ?? 0,
        description: json['description'] as String?,
        videoProcessingStatus: json['videoProcessingStatus'] as String? ?? 'none',
      );
}

class EnrollmentModel {
  final String id;
  final String courseId;
  final String userId;
  final String status;
  final DateTime enrolledAt;
  final List<String> completedLessonIds;

  const EnrollmentModel({
    required this.id,
    required this.courseId,
    required this.userId,
    required this.status,
    required this.enrolledAt,
    this.completedLessonIds = const [],
  });

  factory EnrollmentModel.fromJson(Map<String, dynamic> json) =>
      EnrollmentModel(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        userId: json['userId'] as String,
        status: json['status'] as String? ?? 'active',
        enrolledAt: DateTime.parse(
          json['enrolledAt'] as String? ??
              json['createdAt'] as String? ??
              DateTime.now().toIso8601String(),
        ),
        completedLessonIds:
            (json['completedLessonIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
                [],
      );
}

/// Response from POST /micro-learning/enrollments/initiate — either the course was free and
/// [enrollment] is already set, or it's paid and [gatewayPageUrl] is where the customer pays.
class EnrollmentInitiation {
  final bool requiresPayment;
  final EnrollmentModel? enrollment;
  final String? gatewayPageUrl;
  final double? amount;

  const EnrollmentInitiation({
    required this.requiresPayment,
    this.enrollment,
    this.gatewayPageUrl,
    this.amount,
  });

  factory EnrollmentInitiation.fromJson(Map<String, dynamic> json) {
    final requiresPayment = json['requiresPayment'] as bool? ?? false;
    if (!requiresPayment) {
      final enrollmentJson = json['enrollment'] as Map<String, dynamic>?;
      return EnrollmentInitiation(
        requiresPayment: false,
        enrollment: enrollmentJson != null ? EnrollmentModel.fromJson(enrollmentJson) : null,
      );
    }
    final txn = json['transaction'] as Map<String, dynamic>? ?? {};
    return EnrollmentInitiation(
      requiresPayment: true,
      gatewayPageUrl: txn['gatewayPageUrl'] as String?,
      amount: double.tryParse('${txn['amount']}'),
    );
  }
}
