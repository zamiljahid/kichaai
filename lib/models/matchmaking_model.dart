double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class MatchProviderModel {
  final String id;
  final String name;
  final String? bio;
  final String? profileImageUrl;
  final double? rating;
  final int? totalReviews;
  final int? totalJobs;
  final String? level;
  final String? serviceKind;
  final bool nidVerified;
  final List<String> portfolioImages;

  const MatchProviderModel({
    required this.id,
    required this.name,
    this.bio,
    this.profileImageUrl,
    this.rating,
    this.totalReviews,
    this.totalJobs,
    this.level,
    this.serviceKind,
    this.nidVerified = false,
    this.portfolioImages = const [],
  });

  factory MatchProviderModel.fromJson(Map<String, dynamic> json) =>
      MatchProviderModel(
        id: json['id'] as String? ?? json['providerId'] as String? ?? '',
        name: json['name'] as String? ??
            json['fullName'] as String? ??
            json['providerName'] as String? ??
            '',
        bio: json['bio'] as String? ?? json['about'] as String?,
        profileImageUrl: json['profileImageUrl'] as String? ??
            json['profilePhoto'] as String?,
        rating: _asDoubleOrNull(json['rating'] ?? json['avgRating']),
        totalReviews: json['totalReviews'] as int? ?? json['reviewCount'] as int?,
        totalJobs: json['totalJobs'] as int? ?? json['jobsCompleted'] as int?,
        level: json['level'] as String?,
        serviceKind: json['serviceKind'] as String? ??
            json['kind'] as String?,
        nidVerified: json['nidVerified'] == true,
        portfolioImages: (json['portfolioImages'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

class MatchRequestModel {
  final String id;
  final String requestNo;
  final String customerId;
  final String? customerNameSnapshot;
  final String? customerPhoneSnapshot;
  final String requestType;
  final String serviceTypeId;
  final String title;
  final String description;
  final String? serviceAddressSnapshot;
  final double? serviceLatitude;
  final double? serviceLongitude;
  final double? budgetMin;
  final double? budgetMax;
  final DateTime? preferredStartDate;
  final int maxResponses;
  final int responseCount;
  final String status;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  // Raw per-type detail blobs — kept generic so display code can pull whichever
  // fields matter (studentClass/subjects for tutor, moveInDate for mess, etc.)
  // without a dedicated class per RequestType.
  final Map<String, dynamic>? tutorDetails;
  final Map<String, dynamic>? messDetails;
  final Map<String, dynamic>? petCareDetails;

  const MatchRequestModel({
    required this.id,
    required this.requestNo,
    required this.customerId,
    this.customerNameSnapshot,
    this.customerPhoneSnapshot,
    required this.requestType,
    required this.serviceTypeId,
    required this.title,
    required this.description,
    this.serviceAddressSnapshot,
    this.serviceLatitude,
    this.serviceLongitude,
    this.budgetMin,
    this.budgetMax,
    this.preferredStartDate,
    this.maxResponses = 10,
    this.responseCount = 0,
    required this.status,
    this.publishedAt,
    this.expiresAt,
    required this.createdAt,
    this.tutorDetails,
    this.messDetails,
    this.petCareDetails,
  });

  factory MatchRequestModel.fromJson(Map<String, dynamic> json) =>
      MatchRequestModel(
        id: json['id'] as String,
        requestNo: json['requestNo'] as String? ?? '',
        customerId: json['customerId'] as String? ?? '',
        customerNameSnapshot: json['customerNameSnapshot'] as String?,
        customerPhoneSnapshot: json['customerPhoneSnapshot'] as String?,
        requestType: json['requestType'] as String? ?? '',
        serviceTypeId: json['serviceTypeId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        serviceAddressSnapshot: json['serviceAddressSnapshot'] as String?,
        serviceLatitude: _asDoubleOrNull(json['serviceLatitude']),
        serviceLongitude: _asDoubleOrNull(json['serviceLongitude']),
        budgetMin: _asDoubleOrNull(json['budgetMin']),
        budgetMax: _asDoubleOrNull(json['budgetMax']),
        preferredStartDate: json['preferredStartDate'] != null
            ? DateTime.tryParse(json['preferredStartDate'] as String)
            : null,
        maxResponses: json['maxResponses'] as int? ?? 10,
        responseCount: json['responseCount'] as int? ?? 0,
        status: json['status'] as String? ?? 'draft',
        publishedAt: json['publishedAt'] != null ? DateTime.tryParse(json['publishedAt'] as String) : null,
        expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        tutorDetails: json['tutorDetails'] as Map<String, dynamic>?,
        messDetails: json['messDetails'] as Map<String, dynamic>?,
        petCareDetails: json['petCareDetails'] as Map<String, dynamic>?,
      );
}

class MatchResponseModel {
  final String id;
  final String requestId;
  final String providerId;
  final String? providerNameSnapshot;
  final double? providerAvgRatingSnapshot;
  final String? coverMessage;
  final double? quotedAmount;
  final String? quotedAmountType;
  final String status;
  final DateTime createdAt;

  const MatchResponseModel({
    required this.id,
    required this.requestId,
    required this.providerId,
    this.providerNameSnapshot,
    this.providerAvgRatingSnapshot,
    this.coverMessage,
    this.quotedAmount,
    this.quotedAmountType,
    required this.status,
    required this.createdAt,
  });

  factory MatchResponseModel.fromJson(Map<String, dynamic> json) =>
      MatchResponseModel(
        id: json['id'] as String,
        requestId: json['requestId'] as String? ?? '',
        providerId: json['providerId'] as String? ?? '',
        providerNameSnapshot: json['providerNameSnapshot'] as String?,
        providerAvgRatingSnapshot: _asDoubleOrNull(json['providerAvgRatingSnapshot']),
        coverMessage: json['coverMessage'] as String?,
        quotedAmount: _asDoubleOrNull(json['quotedAmount']),
        quotedAmountType: json['quotedAmountType'] as String?,
        status: json['status'] as String? ?? 'interested',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
