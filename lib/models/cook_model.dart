double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class CookAvailabilityModel {
  final String id;
  final int? dayOfWeek;
  final String startTime;
  final String endTime;
  final DateTime? specificDate;
  final bool isBlackout;
  final int maxConcurrentOrders;

  const CookAvailabilityModel({
    required this.id, this.dayOfWeek, required this.startTime, required this.endTime,
    this.specificDate, this.isBlackout = false, this.maxConcurrentOrders = 1,
  });

  factory CookAvailabilityModel.fromJson(Map<String, dynamic> json) => CookAvailabilityModel(
        id: json['id'] as String,
        dayOfWeek: json['dayOfWeek'] as int?,
        startTime: json['startTime'] as String? ?? '',
        endTime: json['endTime'] as String? ?? '',
        specificDate: json['specificDate'] != null ? DateTime.tryParse(json['specificDate'] as String) : null,
        isBlackout: json['isBlackout'] as bool? ?? false,
        maxConcurrentOrders: json['maxConcurrentOrders'] as int? ?? 1,
      );
}

class CookRequestModel {
  final String id;
  final String requestNo;
  final String customerId;
  final String dishName;
  final String quantity;
  final String? notes;
  final String pickupArea;
  final DateTime windowDate;
  final String windowStart;
  final String windowEnd;
  final double? budgetAmount;
  final String status;
  final String? confirmedResponseId;
  final double? paymentAmount;
  final String paymentStatus;
  final DateTime createdAt;
  final double? providerLatitude;
  final double? providerLongitude;
  final DateTime? providerLocationUpdatedAt;
  final String? customerPhoneSnapshot;
  // Only present when the backend embeds them (e.g. GET /cook/requests/:id) — lets the
  // customer's detail sheet find the finalized provider's own confirmation (name+phone)
  // without a second request once the request has moved past 'posted'.
  final List<CookConfirmationModel> confirmations;

  const CookRequestModel({
    required this.id, required this.requestNo, required this.customerId, required this.dishName,
    required this.quantity, this.notes, required this.pickupArea, required this.windowDate,
    required this.windowStart, required this.windowEnd, this.budgetAmount, required this.status,
    this.confirmedResponseId, this.paymentAmount, required this.paymentStatus, required this.createdAt,
    this.providerLatitude, this.providerLongitude, this.providerLocationUpdatedAt,
    this.customerPhoneSnapshot, this.confirmations = const [],
  });

  factory CookRequestModel.fromJson(Map<String, dynamic> json) => CookRequestModel(
        id: json['id'] as String,
        requestNo: json['requestNo'] as String? ?? '',
        customerId: json['customerId'] as String? ?? '',
        dishName: json['dishName'] as String? ?? '',
        quantity: json['quantity'] as String? ?? '',
        notes: json['notes'] as String?,
        pickupArea: json['pickupArea'] as String? ?? '',
        windowDate: DateTime.tryParse(json['windowDate'] as String? ?? '') ?? DateTime.now(),
        windowStart: json['windowStart'] as String? ?? '',
        windowEnd: json['windowEnd'] as String? ?? '',
        budgetAmount: _asDoubleOrNull(json['budgetAmount']),
        status: json['status'] as String? ?? 'posted',
        confirmedResponseId: json['confirmedResponseId'] as String?,
        paymentAmount: _asDoubleOrNull(json['paymentAmount']),
        paymentStatus: json['paymentStatus'] as String? ?? 'pending',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        providerLatitude: _asDoubleOrNull(json['providerLatitude']),
        providerLongitude: _asDoubleOrNull(json['providerLongitude']),
        providerLocationUpdatedAt: json['providerLocationUpdatedAt'] != null ? DateTime.tryParse(json['providerLocationUpdatedAt'] as String) : null,
        customerPhoneSnapshot: json['customerPhoneSnapshot'] as String?,
        confirmations: (json['confirmations'] as List<dynamic>?)
                ?.map((e) => CookConfirmationModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class CookConfirmationModel {
  final String id;
  final String requestId;
  final String providerId;
  final String? providerNameSnapshot;
  final double? providerAvgRatingSnapshot;
  final double? quotedAmount;
  final String status;
  final String? providerPhoneSnapshot;

  const CookConfirmationModel({
    required this.id, required this.requestId, required this.providerId, this.providerNameSnapshot,
    this.providerAvgRatingSnapshot, this.quotedAmount, required this.status, this.providerPhoneSnapshot,
  });

  factory CookConfirmationModel.fromJson(Map<String, dynamic> json) => CookConfirmationModel(
        id: json['id'] as String,
        requestId: json['requestId'] as String? ?? '',
        providerId: json['providerId'] as String? ?? '',
        providerNameSnapshot: json['providerNameSnapshot'] as String?,
        providerAvgRatingSnapshot: _asDoubleOrNull(json['providerAvgRatingSnapshot']),
        quotedAmount: _asDoubleOrNull(json['quotedAmount']),
        status: json['status'] as String? ?? 'confirmed',
        providerPhoneSnapshot: json['providerPhoneSnapshot'] as String?,
      );
}
