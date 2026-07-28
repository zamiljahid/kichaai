// Prisma Decimal columns (price, totalAmount) serialize to JSON as STRINGS, not numbers —
// a direct `as num` cast throws for every real record (see project_token_refresh_race_bug memory).
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

class ProviderServiceModel {
  final String id;
  final String serviceTypeId;
  final String providerId;
  final String? title;
  final String? titleBn;
  final String? description;
  final String status;
  final bool isActive;

  const ProviderServiceModel({
    required this.id,
    required this.serviceTypeId,
    required this.providerId,
    this.title,
    this.titleBn,
    this.description,
    required this.status,
    this.isActive = true,
  });

  factory ProviderServiceModel.fromJson(Map<String, dynamic> json) =>
      ProviderServiceModel(
        id: json['id'] as String,
        serviceTypeId: json['serviceTypeId'] as String,
        providerId: json['providerId'] as String,
        title: json['title'] as String?,
        titleBn: json['titleBn'] as String?,
        description: json['description'] as String?,
        status: json['status'] as String? ?? 'active',
        isActive: json['isActive'] as bool? ?? true,
      );
}

class OfferingModel {
  final String id;
  final String providerServiceId;
  final String title;
  final String? titleBn;
  final String? description;
  final double price;
  final int? durationMinutes;
  final String status;

  const OfferingModel({
    required this.id,
    required this.providerServiceId,
    required this.title,
    this.titleBn,
    this.description,
    required this.price,
    this.durationMinutes,
    required this.status,
  });

  factory OfferingModel.fromJson(Map<String, dynamic> json) => OfferingModel(
        id: json['id'] as String,
        providerServiceId: json['providerServiceId'] as String,
        title: json['title'] as String,
        titleBn: json['titleBn'] as String?,
        description: json['description'] as String?,
        price: _asDouble(json['price']),
        durationMinutes: json['durationMinutes'] as int?,
        status: json['status'] as String? ?? 'active',
      );

  String displayTitle(String lang) =>
      lang == 'bn' && titleBn != null ? titleBn! : title;
}

class BookingModel {
  final String id;
  final String offeringId;
  final String customerId;
  final String? providerId;
  final String status;
  final DateTime scheduledAt;
  final String? addressId;
  final String? notes;
  final double? totalAmount;
  final String? paymentStatus;
  final DateTime createdAt;

  // Snapshots for display without extra lookups
  final String? offeringTitle;
  final String? providerName;
  final String? customerName;

  const BookingModel({
    required this.id,
    required this.offeringId,
    required this.customerId,
    this.providerId,
    required this.status,
    required this.scheduledAt,
    this.addressId,
    this.notes,
    this.totalAmount,
    this.paymentStatus,
    required this.createdAt,
    this.offeringTitle,
    this.providerName,
    this.customerName,
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) => BookingModel(
        id: json['id'] as String,
        offeringId: json['offeringId'] as String,
        customerId: json['customerId'] as String,
        providerId: json['providerId'] as String?,
        status: json['status'] as String? ?? 'pending',
        scheduledAt: DateTime.parse(json['scheduledAt'] as String),
        addressId: json['addressId'] as String?,
        notes: json['notes'] as String?,
        totalAmount: _asDoubleOrNull(json['totalAmount']),
        paymentStatus: json['paymentStatus'] as String?,
        createdAt: DateTime.parse(
          json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        ),
        offeringTitle: json['offeringTitle'] as String?,
        providerName: json['providerName'] as String?,
        customerName: json['customerName'] as String?,
      );

  bool get isActive =>
      status == 'pending' || status == 'confirmed' || status == 'in_progress';

  bool get isCompleted => status == 'completed';

  bool get isCancelled => status == 'cancelled';

  String statusBn() {
    switch (status) {
      case 'pending':
        return 'অপেক্ষমান';
      case 'confirmed':
        return 'নিশ্চিত';
      case 'in_progress':
        return 'চলমান';
      case 'completed':
        return 'সম্পন্ন';
      case 'cancelled':
        return 'বাতিল';
      default:
        return status;
    }
  }
}

class ReviewModel {
  final String id;
  final String bookingId;
  final String offeringId;
  final String customerId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String? customerName;
  final String? customerImageUrl;

  const ReviewModel({
    required this.id,
    required this.bookingId,
    required this.offeringId,
    required this.customerId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.customerName,
    this.customerImageUrl,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) => ReviewModel(
        id: json['id'] as String,
        bookingId: json['bookingId'] as String,
        offeringId: json['offeringId'] as String,
        customerId: json['customerId'] as String,
        rating: json['rating'] as int,
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(
          json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        ),
        customerName: json['customerName'] as String?,
        customerImageUrl: json['customerImageUrl'] as String?,
      );
}
