// The API serializes Prisma Decimal fields as JSON strings (e.g. "23.793"),
// so numeric fields must accept both num and String.
double _asDouble(dynamic v) => v is num ? v.toDouble() : double.parse(v.toString());
double? _asDoubleOrNull(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));

class JobModel {
  final String id;
  final String customerId;
  final String serviceTypeId;
  final String serviceKind;
  final String title;
  final String status;
  final double pickupLatitude;
  final double pickupLongitude;
  final String? pickupAddressSnapshot;
  final String? customerNameSnapshot;
  final String? customerPhoneSnapshot;
  final String? description;
  final String? urgencyLevel;
  final double? estimatedAmount;
  final double? finalAmount;
  final String? preferredProviderId;
  final String? assignedProviderId;
  final String? providerNameSnapshot;
  final String? providerPhoneSnapshot;
  final String? taskCategory;   // technician-type jobs only
  final String? pricingMode;    // FIXED | CUSTOM
  final double? quotedAmount;   // set once provider submits a CUSTOM quote
  final DateTime? quoteApprovedAt;
  final DateTime? assignedAt;   // when the provider accepted (start of the 15-min cancel grace)
  final DateTime? confirmedAt;  // when the customer OTP-confirmed start (job engaged)
  final DateTime? providerConfirmedAt; // when the customer confirmed the accepted provider (reveals phone numbers)
  final bool exactLocationHidden; // true → address is coarse + pin fuzzed (pre-accept / not owner)
  final String? meetLink;       // lawyer video consultations — Google Meet link
  final String? startPhotoUrl;  // provider's photo proof — with a photo the commission is 15%, without 20%
  final String? endPhotoUrl;
  final int? notifiedProviderCount; // createJob response only — how many providers the broadcast reached
  final DateTime? eventDate;    // advance-booking jobs — scheduled start time
  final int? estimatedDurationHours; // advance-booking jobs — planned duration
  /// Provider location breadcrumbs, newest first. Backend guarantees this is
  /// empty until the provider is assigned AND has started sharing location.
  final List<LocationTrackModel> locationTracks;
  final DateTime createdAt;

  const JobModel({
    required this.id,
    required this.customerId,
    required this.serviceTypeId,
    required this.serviceKind,
    required this.title,
    required this.status,
    required this.pickupLatitude,
    required this.pickupLongitude,
    this.pickupAddressSnapshot,
    this.customerNameSnapshot,
    this.customerPhoneSnapshot,
    this.description,
    this.urgencyLevel,
    this.estimatedAmount,
    this.finalAmount,
    this.preferredProviderId,
    this.assignedProviderId,
    this.providerNameSnapshot,
    this.providerPhoneSnapshot,
    this.taskCategory,
    this.pricingMode,
    this.quotedAmount,
    this.quoteApprovedAt,
    this.assignedAt,
    this.confirmedAt,
    this.providerConfirmedAt,
    this.exactLocationHidden = false,
    this.meetLink,
    this.startPhotoUrl,
    this.endPhotoUrl,
    this.notifiedProviderCount,
    this.eventDate,
    this.estimatedDurationHours,
    this.locationTracks = const [],
    required this.createdAt,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        serviceTypeId: json['serviceTypeId'] as String,
        serviceKind: json['serviceKind'] as String,
        title: json['title'] as String,
        status: json['status'] as String? ?? 'searching',
        pickupLatitude: _asDouble(json['pickupLatitude']),
        pickupLongitude: _asDouble(json['pickupLongitude']),
        pickupAddressSnapshot: json['pickupAddressSnapshot'] as String?,
        customerNameSnapshot: json['customerNameSnapshot'] as String?,
        customerPhoneSnapshot: json['customerPhoneSnapshot'] as String?,
        description: json['description'] as String?,
        urgencyLevel: json['urgencyLevel'] as String?,
        estimatedAmount: _asDoubleOrNull(json['estimatedAmount']),
        finalAmount: _asDoubleOrNull(json['finalAmount']),
        preferredProviderId: json['preferredProviderId'] as String?,
        assignedProviderId: json['assignedProviderId'] as String?,
        // Dispatch job rows use the assignedProvider* names; assignment
        // payloads use the bare names — accept both.
        providerNameSnapshot: (json['providerNameSnapshot'] ??
            json['assignedProviderNameSnapshot']) as String?,
        providerPhoneSnapshot: (json['providerPhoneSnapshot'] ??
            json['assignedProviderPhoneSnapshot']) as String?,
        taskCategory: json['taskCategory'] as String?,
        pricingMode: json['pricingMode'] as String?,
        quotedAmount: _asDoubleOrNull(json['quotedAmount']),
        quoteApprovedAt: json['quoteApprovedAt'] != null
            ? DateTime.tryParse(json['quoteApprovedAt'] as String)
            : null,
        assignedAt: json['assignedAt'] != null
            ? DateTime.tryParse(json['assignedAt'] as String)
            : null,
        confirmedAt: json['confirmedAt'] != null
            ? DateTime.tryParse(json['confirmedAt'] as String)
            : null,
        providerConfirmedAt: json['providerConfirmedAt'] != null
            ? DateTime.tryParse(json['providerConfirmedAt'] as String)
            : null,
        exactLocationHidden: json['exactLocationHidden'] == true,
        meetLink: json['meetLink'] as String?,
        startPhotoUrl: json['startPhotoUrl'] as String?,
        endPhotoUrl: json['endPhotoUrl'] as String?,
        notifiedProviderCount: (json['notifiedProviderCount'] as num?)?.toInt(),
        eventDate: json['eventDate'] != null
            ? DateTime.tryParse(json['eventDate'] as String)
            : null,
        estimatedDurationHours: (json['estimatedDurationHours'] as num?)?.toInt(),
        locationTracks: ((json['locationTracks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => LocationTrackModel.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        createdAt: DateTime.parse(
          json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        ),
      );

  /// CUSTOM-pricing job where the provider still needs to submit a quote.
  bool get awaitingProviderQuote => pricingMode == 'CUSTOM' && quotedAmount == null;

  /// CUSTOM quote submitted, waiting for the customer to approve/reject.
  bool get awaitingQuoteApproval =>
      pricingMode == 'CUSTOM' && quotedAmount != null && quoteApprovedAt == null;

  String statusBn() {
    switch (status) {
      case 'searching':
        return 'খোঁজা হচ্ছে';
      case 'assigned':
        return 'নির্ধারিত';
      case 'accepted':
        return 'গৃহীত';
      case 'arriving':
        return 'আসছে';
      case 'in_progress':
        return 'চলমান';
      case 'completed':
        return 'সম্পন্ন';
      case 'cancelled':
        return 'বাতিল';
      case 'expired':
        return 'মেয়াদ শেষ';
      default:
        return status;
    }
  }

  bool get isActive =>
      status == 'searching' ||
      status == 'assigned' ||
      status == 'accepted' ||
      status == 'arriving' ||
      status == 'in_progress';

  // ── Provider cancellation policy (must mirror the backend) ──────────────────
  // Free-cancel window (minutes) after accepting, before the "committed" penalty applies.
  static const int cancelGraceMinutes = 15;

  /// Customer has OTP-confirmed the start → the provider clearly engaged the customer.
  bool get startConfirmed => confirmedAt != null;

  /// Customer has confirmed the accepted provider — phone numbers are now visible on both
  /// sides (before this, chat is the only channel). Never applies to lawyer jobs.
  bool get providerConfirmed => providerConfirmedAt != null;

  /// Still inside the free-cancel grace window after accepting.
  bool get inCancelGrace {
    if (assignedAt == null) return true; // not yet assigned → nothing to penalise
    return DateTime.now().difference(assignedAt!).inMinutes < cancelGraceMinutes;
  }

  /// Whole minutes left in the free-cancel window (0 once it has expired).
  int get cancelGraceMinutesLeft {
    if (assignedAt == null) return cancelGraceMinutes;
    final left = cancelGraceMinutes -
        DateTime.now().difference(assignedAt!).inMinutes;
    return left < 0 ? 0 : left;
  }

  /// What cancelling now costs the provider:
  ///  - 'free'  : inside grace, no penalty
  ///  - 'card'  : committed, 1 red card
  ///  - 'fee'   : committed AND start confirmed → red card + commission debt
  String get cancelPenaltyKind {
    if (inCancelGrace) return 'free';
    return startConfirmed ? 'fee' : 'card';
  }
}

class AssignmentModel {
  final String id;
  final String jobId;
  final String providerId;
  final String? providerNameSnapshot;
  final String? providerPhoneSnapshot;
  final double? providerRatingSnapshot;
  final double? distanceKm;
  final String status;

  const AssignmentModel({
    required this.id,
    required this.jobId,
    required this.providerId,
    this.providerNameSnapshot,
    this.providerPhoneSnapshot,
    this.providerRatingSnapshot,
    this.distanceKm,
    required this.status,
  });

  factory AssignmentModel.fromJson(Map<String, dynamic> json) => AssignmentModel(
        id: json['id'] as String,
        // API field is `dispatchJobId`; `response` carries pending/accepted/rejected.
        jobId: (json['jobId'] ?? json['dispatchJobId']) as String? ?? '',
        providerId: json['providerId'] as String,
        providerNameSnapshot: json['providerNameSnapshot'] as String?,
        providerPhoneSnapshot: json['providerPhoneSnapshot'] as String?,
        providerRatingSnapshot: _asDoubleOrNull(
            json['providerRatingSnapshot'] ?? json['ratingSnapshot']),
        distanceKm: _asDoubleOrNull(json['distanceKm']),
        status: (json['status'] ?? json['response']) as String? ?? 'pending',
      );
}

class LiveSessionModel {
  final String id;
  final String providerId;
  final List<String> serviceKinds;
  final double latitude;
  final double longitude;
  final String? providerNameSnapshot;
  final double? providerAvgRatingSnapshot;
  final String? providerLevel;
  final String? profileImageUrl;
  final bool isActive;

  const LiveSessionModel({
    required this.id,
    required this.providerId,
    required this.serviceKinds,
    required this.latitude,
    required this.longitude,
    this.providerNameSnapshot,
    this.providerAvgRatingSnapshot,
    this.providerLevel,
    this.profileImageUrl,
    this.isActive = true,
  });

  factory LiveSessionModel.fromJson(Map<String, dynamic> json) => LiveSessionModel(
        id: json['id'] as String,
        providerId: json['providerId'] as String,
        serviceKinds: (json['serviceKinds'] as List<dynamic>)
            .map((e) => e is Map ? (e['serviceKind'] as String? ?? '') : e as String)
            .where((s) => s.isNotEmpty)
            .toList(),
        // /dispatch/sessions/me sends currentLatitude/currentLongitude (Decimal → string);
        // plain latitude/longitude never existed in that payload, so parsing used to throw
        // on the null and getMySession() failed for every caller since the model was written.
        latitude: _asDoubleOrNull(json['latitude'] ?? json['currentLatitude']) ?? 0,
        longitude: _asDoubleOrNull(json['longitude'] ?? json['currentLongitude']) ?? 0,
        providerNameSnapshot: json['providerNameSnapshot'] as String?,
        providerAvgRatingSnapshot:
            _asDoubleOrNull(json['providerAvgRatingSnapshot']),
        providerLevel: json['providerLevel'] as String?,
        profileImageUrl: json['profileImageUrl'] as String?,
        // Backend field is isOnline (ProviderLiveSession) — `isActive` never existed in the
        // response, so this always defaulted to true and an offline session read as active.
        isActive: json['isOnline'] as bool? ?? json['isActive'] as bool? ?? true,
      );
}

class NearbyProviderModel {
  final String id;
  final String name;
  final String? phone;
  final double? rating;
  final double? distanceKm;
  final double latitude;
  final double longitude;
  final String? profileImageUrl;
  final String? level;
  final List<String> serviceKinds;

  const NearbyProviderModel({
    required this.id,
    required this.name,
    this.phone,
    this.rating,
    this.distanceKm,
    required this.latitude,
    required this.longitude,
    this.profileImageUrl,
    this.level,
    this.serviceKinds = const [],
  });

  factory NearbyProviderModel.fromJson(Map<String, dynamic> json) =>
      NearbyProviderModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['providerNameSnapshot'] as String? ?? '',
        phone: json['phone'] as String?,
        rating: _asDoubleOrNull(json['rating']),
        distanceKm: _asDoubleOrNull(json['distanceKm']),
        latitude: _asDouble(json['latitude']),
        longitude: _asDouble(json['longitude']),
        profileImageUrl: json['profileImageUrl'] as String?,
        level: json['level'] as String?,
        serviceKinds: (json['serviceKinds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

class ScrapRequestModel {
  final String id;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String? address;
  final String status;
  final double? estimatedWeightKg;
  final List<String> categories;
  final DateTime? scheduledAt;
  final DateTime createdAt;

  const ScrapRequestModel({
    required this.id,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    this.address,
    required this.status,
    this.estimatedWeightKg,
    this.categories = const [],
    this.scheduledAt,
    required this.createdAt,
  });

  factory ScrapRequestModel.fromJson(Map<String, dynamic> json) =>
      ScrapRequestModel(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String?,
        customerPhone: json['customerPhone'] as String?,
        address: json['address'] as String?,
        status: json['status'] as String? ?? 'pending',
        estimatedWeightKg: _asDoubleOrNull(json['estimatedWeightKg']),
        categories: (json['categories'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        scheduledAt: json['scheduledAt'] != null
            ? DateTime.parse(json['scheduledAt'] as String)
            : null,
        createdAt: DateTime.parse(
          json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        ),
      );
}

class RateCardModel {
  final String id;
  final String serviceKind;
  final String serviceTypeId;
  final String rateName;
  final double baseCharge;
  final double? perHourRate;
  final double? perKmRate;
  final double? emergencyMultiplier;
  final bool isActive;

  const RateCardModel({
    required this.id,
    required this.serviceKind,
    required this.serviceTypeId,
    required this.rateName,
    required this.baseCharge,
    this.perHourRate,
    this.perKmRate,
    this.emergencyMultiplier,
    this.isActive = true,
  });

  factory RateCardModel.fromJson(Map<String, dynamic> json) => RateCardModel(
        id: json['id'] as String,
        serviceKind: json['serviceKind'] as String,
        serviceTypeId: json['serviceTypeId'] as String,
        rateName: json['rateName'] as String,
        baseCharge: _asDouble(json['baseCharge']),
        perHourRate: _asDoubleOrNull(json['perHourRate']),
        perKmRate: _asDoubleOrNull(json['perKmRate']),
        emergencyMultiplier: _asDoubleOrNull(json['emergencyMultiplier']),
        isActive: json['isActive'] as bool? ?? true,
      );
}

/// Outcome of a provider cancelling a job — mirrors the backend `cancelPenalty` block.
class CancelResult {
  final bool cardGiven;
  final bool feeCharged;
  final double? feeAmount;
  final bool suspended;      // 3rd card → temp ban triggered
  final DateTime? bannedUntil;
  final int? redFlags;

  const CancelResult({
    this.cardGiven = false,
    this.feeCharged = false,
    this.feeAmount,
    this.suspended = false,
    this.bannedUntil,
    this.redFlags,
  });

  bool get hadPenalty => cardGiven || feeCharged;

  factory CancelResult.fromJson(Map<String, dynamic> json) {
    final cp = json['cancelPenalty'];
    if (cp is! Map) return const CancelResult();
    return CancelResult(
      cardGiven: cp['cardGiven'] == true,
      feeCharged: cp['feeCharged'] == true,
      feeAmount: _asDoubleOrNull(cp['feeAmount']),
      suspended: cp['suspended'] == true,
      bannedUntil: cp['bannedUntil'] != null
          ? DateTime.tryParse(cp['bannedUntil'] as String)
          : null,
      redFlags: cp['redFlags'] as int?,
    );
  }
}

/// Provider's dispatch standing — red cards, temp-ban countdown, unpaid dues.
class ProviderStanding {
  final int redFlags;
  final int cardsUntilBan;
  final bool isBanned;
  final bool tempBanned;
  final DateTime? bannedUntil;
  final bool canReceiveJobs;
  final double unpaidDuesTotal;
  final int unpaidDuesCount;
  final bool duesBlockingNewJobs;
  final String level;
  final int totalCompleted;
  final int weeklyCompleted;
  final double? dispatchAvgRating;

  const ProviderStanding({
    this.redFlags = 0,
    this.cardsUntilBan = 3,
    this.isBanned = false,
    this.tempBanned = false,
    this.bannedUntil,
    this.canReceiveJobs = true,
    this.unpaidDuesTotal = 0,
    this.unpaidDuesCount = 0,
    this.duesBlockingNewJobs = false,
    this.level = 'BRONZE',
    this.totalCompleted = 0,
    this.weeklyCompleted = 0,
    this.dispatchAvgRating,
  });

  factory ProviderStanding.fromJson(Map<String, dynamic> json) => ProviderStanding(
        redFlags: json['redFlags'] as int? ?? 0,
        cardsUntilBan: json['cardsUntilBan'] as int? ?? 3,
        isBanned: json['isBanned'] == true,
        tempBanned: json['tempBanned'] == true,
        bannedUntil: json['bannedUntil'] != null
            ? DateTime.tryParse(json['bannedUntil'] as String)
            : null,
        canReceiveJobs: json['canReceiveJobs'] != false,
        unpaidDuesTotal: _asDoubleOrNull(json['unpaidDuesTotal']) ?? 0,
        unpaidDuesCount: json['unpaidDuesCount'] as int? ?? 0,
        duesBlockingNewJobs: json['duesBlockingNewJobs'] == true,
        level: json['level'] as String? ?? 'BRONZE',
        totalCompleted: json['totalCompleted'] as int? ?? 0,
        weeklyCompleted: json['weeklyCompleted'] as int? ?? 0,
        dispatchAvgRating: _asDoubleOrNull(json['dispatchAvgRating']),
      );

  /// Nothing to warn about — clean standing.
  bool get isClean =>
      redFlags == 0 && !isBanned && !tempBanned && unpaidDuesCount == 0;
}

/// Bengali labels for the platform's technician task categories (backend enum values).
const kTaskCategoryLabelsBn = <String, String>{
  'AC_SERVICE': 'এসি সার্ভিস',
  'REFRIGERATOR_REPAIR': 'ফ্রিজ মেরামত',
  'WASHING_MACHINE_REPAIR': 'ওয়াশিং মেশিন',
  'PLUMBING': 'প্লাম্বিং',
  'ELECTRICAL': 'ইলেকট্রিক',
  'PAINTING': 'রং করা',
  'CARPENTRY': 'কার্পেন্ট্রি',
  'TILES_WORK': 'টাইলস',
  'COMPUTER_REPAIR': 'কম্পিউটার',
  'MOBILE_REPAIR': 'মোবাইল',
  'TV_REPAIR': 'টিভি',
  'GENERAL_HANDYMAN': 'হ্যান্ডিম্যান',
  'CLEANING': 'ক্লিনিং',
  'PEST_CONTROL': 'পেস্ট কন্ট্রোল',
  'BABY_SITTING_SHORT': 'বেবি সিটিং',
  'CAR_REPAIR': 'গাড়ি মেরামত',
  'MOTORCYCLE_REPAIR': 'মোটরসাইকেল মেরামত',
};

/// Which task categories make sense for a given technician specialization —
/// the কাজের ধরন chips are filtered by this so a car owner never sees
/// "বেবি সিটিং" as a job type for their broken car. Unmapped (industrial/B2B)
/// specializations fall back to GENERAL_HANDYMAN so the job still carries a
/// platform price (no taskCategory = no price and ৳0 commission).
const kSpecializationTaskCategories = <String, List<String>>{
  // বাসাবাড়ি ও ইলেকট্রিক
  'ELECTRICIAN': ['ELECTRICAL', 'GENERAL_HANDYMAN'],
  'GENERATOR': ['ELECTRICAL'],
  'IPS_UPS': ['ELECTRICAL'],
  'SOLAR': ['ELECTRICAL'],
  'REFRIGERATOR': ['REFRIGERATOR_REPAIR'],
  'AC': ['AC_SERVICE'],
  'WASHING_MACHINE': ['WASHING_MACHINE_REPAIR'],
  'TV': ['TV_REPAIR'],
  // গাড়ি ও যানবাহন
  'CAR_MECHANIC': ['CAR_REPAIR'],
  'MOTORCYCLE': ['MOTORCYCLE_REPAIR'],
  'DIESEL_ENGINE': ['CAR_REPAIR'],
  'CNG_LPG': ['CAR_REPAIR'],
  'HYBRID_CAR': ['CAR_REPAIR'],
  'EV_CAR': ['CAR_REPAIR'],
  'HEAVY_VEHICLE': ['CAR_REPAIR'],
  // কম্পিউটার ও আইটি
  'COMPUTER_HARDWARE': ['COMPUTER_REPAIR'],
  'NETWORK': ['COMPUTER_REPAIR'],
  'CCTV': ['COMPUTER_REPAIR', 'ELECTRICAL'],
  'PRINTER': ['COMPUTER_REPAIR'],
  'LAPTOP_DESKTOP_REPAIR': ['COMPUTER_REPAIR'],
  'FIBER_OPTIC': ['COMPUTER_REPAIR'],
  'DATA_COMMUNICATION': ['COMPUTER_REPAIR'],
  'SERVER': ['COMPUTER_REPAIR'],
  // টেলিকম
  'MOBILE_PHONE': ['MOBILE_REPAIR'],
  'ISP_NETWORK': ['COMPUTER_REPAIR'],
};

/// Categories relevant to [specializationCode]; falls back to GENERAL_HANDYMAN.
List<String> taskCategoriesForSpecialization(String? specializationCode) {
  if (specializationCode == null) return const [];
  return kSpecializationTaskCategories[specializationCode] ?? const ['GENERAL_HANDYMAN'];
}

/// Group-level filter — applies as soon as the customer picks a GROUP tile,
/// before any specific type: গাড়ি ও যানবাহন immediately shows only vehicle
/// job types, বাসাবাড়ি shows only household ones. Picking a type narrows further.
const kSpecGroupTaskCategories = <String, List<String>>{
  'HOME_ELECTRICAL': [
    'AC_SERVICE', 'REFRIGERATOR_REPAIR', 'WASHING_MACHINE_REPAIR', 'PLUMBING',
    'ELECTRICAL', 'PAINTING', 'CARPENTRY', 'TILES_WORK', 'TV_REPAIR',
    'GENERAL_HANDYMAN', 'CLEANING', 'PEST_CONTROL', 'BABY_SITTING_SHORT',
  ],
  'AUTOMOTIVE': ['CAR_REPAIR', 'MOTORCYCLE_REPAIR'],
  'IT_COMPUTER': ['COMPUTER_REPAIR', 'ELECTRICAL'],
  'TELECOM': ['MOBILE_REPAIR', 'COMPUTER_REPAIR'],
  'INDUSTRIAL': ['ELECTRICAL', 'GENERAL_HANDYMAN'],
};

List<String> taskCategoriesForSpecGroup(String? groupCode) {
  if (groupCode == null) return const [];
  return kSpecGroupTaskCategories[groupCode] ?? const ['GENERAL_HANDYMAN'];
}

/// A platform-set price for a technician task category (admin controls these).
/// Sending `taskCategory` on createJob makes the backend resolve `estimatedAmount` from this.
class TaskCategoryRate {
  final String taskCategory;
  final double fixedPrice;
  final double visitingFee;
  final bool isActive;

  const TaskCategoryRate({
    required this.taskCategory,
    required this.fixedPrice,
    required this.visitingFee,
    this.isActive = true,
  });

  factory TaskCategoryRate.fromJson(Map<String, dynamic> json) => TaskCategoryRate(
        taskCategory: json['taskCategory'] as String,
        fixedPrice: _asDouble(json['fixedPrice']),
        visitingFee: _asDouble(json['visitingFee']),
        isActive: json['isActive'] != false,
      );

  String get labelBn => kTaskCategoryLabelsBn[taskCategory] ?? taskCategory;
}

/// A live broadcast offer to a provider — an open job + the assignment id to respond to.
class JobOffer {
  final JobModel job;
  final String assignmentId;
  final double? distanceKm;

  const JobOffer({required this.job, required this.assignmentId, this.distanceKm});

  factory JobOffer.fromJson(Map<String, dynamic> json) => JobOffer(
        job: JobModel.fromJson(json['job'] as Map<String, dynamic>),
        assignmentId: json['assignmentId'] as String,
        distanceKm: _asDoubleOrNull(json['distanceKm']),
      );
}

/// A cancelled job awaiting the customer's "did the provider still do the work?" answer.
class CancelReview {
  final String jobId;
  final String title;
  final String? providerName;
  final double? amount;
  final DateTime? askedAt;

  const CancelReview({
    required this.jobId,
    required this.title,
    this.providerName,
    this.amount,
    this.askedAt,
  });

  factory CancelReview.fromJson(Map<String, dynamic> json) => CancelReview(
        jobId: json['id'] as String,
        title: json['title'] as String? ?? 'কাজ',
        providerName: json['assignedProviderNameSnapshot'] as String?,
        amount: _asDoubleOrNull(json['finalAmount'] ?? json['estimatedAmount']),
        askedAt: json['cancelReviewAskedAt'] != null
            ? DateTime.tryParse(json['cancelReviewAskedAt'] as String)
            : null,
      );
}

// ── Provider live-location breadcrumb ─────────────────────────────

class LocationTrackModel {
  final String id;
  final String providerId;
  final double latitude;
  final double longitude;
  final DateTime? recordedAt;

  const LocationTrackModel({
    required this.id,
    required this.providerId,
    required this.latitude,
    required this.longitude,
    this.recordedAt,
  });

  factory LocationTrackModel.fromJson(Map<String, dynamic> json) => LocationTrackModel(
        id: json['id'] as String? ?? '',
        providerId: json['providerId'] as String? ?? '',
        latitude: _asDouble(json['latitude']),
        longitude: _asDouble(json['longitude']),
        recordedAt: json['recordedAt'] != null
            ? DateTime.tryParse(json['recordedAt'] as String)
            : null,
      );
}

// ── Advance-booking browse card ───────────────────────────────────

class AvailableProviderModel {
  final String providerId;
  final String name;
  final double? rating;
  final String? level;
  final String? profileImageUrl;
  final List<String> portfolio;
  final List<String> specialties;
  final bool verified;

  const AvailableProviderModel({
    required this.providerId,
    required this.name,
    this.rating,
    this.level,
    this.profileImageUrl,
    this.portfolio = const [],
    this.specialties = const [],
    this.verified = false,
  });

  factory AvailableProviderModel.fromJson(Map<String, dynamic> json) => AvailableProviderModel(
        providerId: json['providerId'] as String,
        name: (json['name'] ?? '?').toString(),
        rating: _asDoubleOrNull(json['rating']),
        level: json['level'] as String?,
        profileImageUrl: json['profileImageUrl'] as String?,
        portfolio: ((json['portfolio'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        specialties: ((json['specialties'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        verified: json['verified'] as bool? ?? false,
      );
}
