import 'package:google_maps_flutter/google_maps_flutter.dart';

int? _asInt(dynamic v) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v.split('.').first) : null);

double? _asDouble(dynamic v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

/// One listing from /auth/properties/* — either a MESS (a seat in a shared
/// mess, `rent` is per seat) or a HOUSE_RENT (whole flat, `rent` is the whole
/// unit). `messName` is the title for both kinds (field name is historical).
class PropertyListing {
  final String id;
  final String listingType; // MESS | HOUSE_RENT
  final String messName;
  final String address;
  final double? latitude;
  final double? longitude;
  final int? rent;
  // MESS
  final int? totalSeats;
  final String? genderPreference; // male | female | any
  final String? smokingPreference; // smoker | non_smoker | any
  final String? occupationPreference; // student | job_holder | any
  // HOUSE_RENT
  final int? bedrooms;
  final int? bathrooms;
  final int? sizeSqft;
  final int? floor;
  final String? tenantType; // family | bachelor | any
  // shared
  final List<String> photosUrls;
  final String? rules;
  final bool isActive;
  final double? distanceKm;
  final String? ownerUserId;
  final String? ownerName;
  final String? ownerPhone;

  const PropertyListing({
    required this.id,
    required this.listingType,
    required this.messName,
    required this.address,
    this.latitude,
    this.longitude,
    this.rent,
    this.totalSeats,
    this.genderPreference,
    this.smokingPreference,
    this.occupationPreference,
    this.bedrooms,
    this.bathrooms,
    this.sizeSqft,
    this.floor,
    this.tenantType,
    this.photosUrls = const [],
    this.rules,
    this.isActive = true,
    this.distanceKm,
    this.ownerUserId,
    this.ownerName,
    this.ownerPhone,
  });

  bool get isMess => listingType != 'HOUSE_RENT';

  LatLng? get latLng =>
      (latitude != null && longitude != null) ? LatLng(latitude!, longitude!) : null;

  factory PropertyListing.fromJson(Map<String, dynamic> json) {
    // Legacy agent-posted rows nest the contact under agent.provider.user.
    final legacyUser =
        ((json['agent'] as Map?)?['provider'] as Map?)?['user'] as Map?;
    String? pref(String key) {
      final v = json[key]?.toString();
      return (v == null || v.isEmpty) ? null : v;
    }

    return PropertyListing(
      id: json['id']?.toString() ?? '',
      listingType: json['listingType']?.toString() ?? 'MESS',
      messName: json['messName']?.toString() ?? json['mess_name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      rent: _asInt(json['rent']),
      totalSeats: _asInt(json['totalSeats'] ?? json['total_seats']),
      genderPreference: pref('genderPreference'),
      smokingPreference: pref('smokingPreference'),
      occupationPreference: pref('occupationPreference'),
      bedrooms: _asInt(json['bedrooms']),
      bathrooms: _asInt(json['bathrooms']),
      sizeSqft: _asInt(json['sizeSqft']),
      floor: _asInt(json['floor']),
      tenantType: pref('tenantType'),
      photosUrls: ((json['photosUrls'] ?? json['photos_urls']) as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      rules: json['rules']?.toString(),
      isActive: json['isActive'] is bool ? json['isActive'] as bool : true,
      distanceKm: _asDouble(json['distanceKm']),
      // Only set for owner-posted listings — legacy agent-posted ones have no ownerUserId
      // (contact resolves via agent.provider.user instead), so visit-requests aren't offered
      // for those.
      ownerUserId: json['ownerUserId']?.toString(),
      ownerName: json['ownerName']?.toString() ?? legacyUser?['fullName']?.toString(),
      ownerPhone: json['ownerPhone']?.toString() ?? legacyUser?['phone']?.toString(),
    );
  }
}

/// "৳5,000" — thousands-separated taka amount.
String takaFmt(int amount) {
  final s = amount.toString();
  final buf = StringBuffer('৳');
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final left = s.length - 1 - i;
    if (left > 0 && left % 3 == 0) buf.write(',');
  }
  return buf.toString();
}
