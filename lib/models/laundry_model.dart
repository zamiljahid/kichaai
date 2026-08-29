double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class LaundryRateCardModel {
  final String serviceKind;
  final String pricingUnit;
  final double pricePerUnit;

  const LaundryRateCardModel({required this.serviceKind, required this.pricingUnit, required this.pricePerUnit});

  factory LaundryRateCardModel.fromJson(Map<String, dynamic> json) => LaundryRateCardModel(
        serviceKind: json['serviceKind'] as String? ?? '',
        pricingUnit: json['pricingUnit'] as String? ?? '',
        pricePerUnit: _asDoubleOrNull(json['pricePerUnit']) ?? 0,
      );
}

class LaundryHubModel {
  final String id;
  final String name;
  final String address;
  final int dailyCapacity;

  const LaundryHubModel({required this.id, required this.name, required this.address, this.dailyCapacity = 50});

  factory LaundryHubModel.fromJson(Map<String, dynamic> json) => LaundryHubModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        dailyCapacity: json['dailyCapacity'] as int? ?? 50,
      );
}

class LaundryBookingModel {
  final String id;
  final String bookingNo;
  final String hubId;
  final String serviceKind;
  final String pricingUnit;
  final double estimatedLoad;
  final double? actualLoad;
  final double estimatedAmount;
  final double? finalAmount;
  final String pickupAddress;
  final DateTime pickupSlotStart;
  final DateTime pickupSlotEnd;
  final String paymentTiming;
  final String paymentStatus;
  final String status;
  final DateTime createdAt;
  final String? customerPhoneSnapshot;
  final String? assignedStaffPhoneSnapshot;

  const LaundryBookingModel({
    required this.id,
    required this.bookingNo,
    required this.hubId,
    required this.serviceKind,
    required this.pricingUnit,
    required this.estimatedLoad,
    this.actualLoad,
    required this.estimatedAmount,
    this.finalAmount,
    required this.pickupAddress,
    required this.pickupSlotStart,
    required this.pickupSlotEnd,
    required this.paymentTiming,
    required this.paymentStatus,
    required this.status,
    required this.createdAt,
    this.customerPhoneSnapshot,
    this.assignedStaffPhoneSnapshot,
  });

  double get displayAmount => finalAmount ?? estimatedAmount;

  factory LaundryBookingModel.fromJson(Map<String, dynamic> json) => LaundryBookingModel(
        id: json['id'] as String,
        bookingNo: json['bookingNo'] as String? ?? '',
        hubId: json['hubId'] as String? ?? '',
        serviceKind: json['serviceKind'] as String? ?? '',
        pricingUnit: json['pricingUnit'] as String? ?? '',
        estimatedLoad: _asDoubleOrNull(json['estimatedLoad']) ?? 0,
        actualLoad: _asDoubleOrNull(json['actualLoad']),
        estimatedAmount: _asDoubleOrNull(json['estimatedAmount']) ?? 0,
        finalAmount: _asDoubleOrNull(json['finalAmount']),
        pickupAddress: json['pickupAddress'] as String? ?? '',
        pickupSlotStart: DateTime.tryParse(json['pickupSlotStart'] as String? ?? '') ?? DateTime.now(),
        pickupSlotEnd: DateTime.tryParse(json['pickupSlotEnd'] as String? ?? '') ?? DateTime.now(),
        paymentTiming: json['paymentTiming'] as String? ?? 'pay_at_booking',
        paymentStatus: json['paymentStatus'] as String? ?? 'pending',
        status: json['status'] as String? ?? 'booked',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        customerPhoneSnapshot: json['customerPhoneSnapshot'] as String?,
        assignedStaffPhoneSnapshot: json['assignedStaffPhoneSnapshot'] as String?,
      );
}
