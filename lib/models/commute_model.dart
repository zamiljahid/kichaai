double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class CommuteOfferModel {
  final String id;
  final String driverId;
  final String? driverNameSnapshot;
  final String originArea;
  final String? destinationArea;
  final List<String> daysOfWeek;
  final String windowStart;
  final String windowEnd;
  final String vehicleType;
  final int seatsAvailable;
  final double costShareAmount;

  const CommuteOfferModel({
    required this.id, required this.driverId, this.driverNameSnapshot, required this.originArea,
    this.destinationArea, required this.daysOfWeek, required this.windowStart, required this.windowEnd,
    required this.vehicleType, required this.seatsAvailable, required this.costShareAmount,
  });

  factory CommuteOfferModel.fromJson(Map<String, dynamic> json) => CommuteOfferModel(
        id: json['id'] as String,
        driverId: json['driverId'] as String? ?? '',
        driverNameSnapshot: json['driverNameSnapshot'] as String?,
        originArea: json['originArea'] as String? ?? '',
        destinationArea: json['destinationArea'] as String?,
        daysOfWeek: (json['daysOfWeek'] as List?)?.map((e) => e.toString()).toList() ?? [],
        windowStart: json['windowStart'] as String? ?? '',
        windowEnd: json['windowEnd'] as String? ?? '',
        vehicleType: json['vehicleType'] as String? ?? '',
        seatsAvailable: json['seatsAvailable'] as int? ?? 0,
        costShareAmount: _asDoubleOrNull(json['costShareAmount']) ?? 0,
      );
}

class CommutePairingModel {
  final String id;
  final String offerId;
  final String driverId;
  final String passengerId;
  final String status;
  final String paymentCycle;

  const CommutePairingModel({
    required this.id, required this.offerId, required this.driverId, required this.passengerId,
    required this.status, required this.paymentCycle,
  });

  factory CommutePairingModel.fromJson(Map<String, dynamic> json) => CommutePairingModel(
        id: json['id'] as String,
        offerId: json['offerId'] as String? ?? '',
        driverId: json['driverId'] as String? ?? '',
        passengerId: json['passengerId'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        paymentCycle: json['paymentCycle'] as String? ?? 'monthly',
      );
}

class OneOffCommutePostModel {
  final String id;
  final String postedByUserId;
  final String? postedByNameSnapshot;
  final String postedByRole;
  final String originArea;
  final String? destinationArea;
  final DateTime tripDateTime;
  final int seatsOrNeed;
  final double? costShareAmount;
  final String status;

  const OneOffCommutePostModel({
    required this.id, required this.postedByUserId, this.postedByNameSnapshot, required this.postedByRole,
    required this.originArea, this.destinationArea, required this.tripDateTime, required this.seatsOrNeed,
    this.costShareAmount, required this.status,
  });

  factory OneOffCommutePostModel.fromJson(Map<String, dynamic> json) => OneOffCommutePostModel(
        id: json['id'] as String,
        postedByUserId: json['postedByUserId'] as String? ?? '',
        postedByNameSnapshot: json['postedByNameSnapshot'] as String?,
        postedByRole: json['postedByRole'] as String? ?? 'driver',
        originArea: json['originArea'] as String? ?? '',
        destinationArea: json['destinationArea'] as String?,
        tripDateTime: DateTime.tryParse(json['tripDateTime'] as String? ?? '') ?? DateTime.now(),
        seatsOrNeed: json['seatsOrNeed'] as int? ?? 1,
        costShareAmount: _asDoubleOrNull(json['costShareAmount']),
        status: json['status'] as String? ?? 'posted',
      );
}
