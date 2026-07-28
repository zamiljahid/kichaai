// Prisma Decimal columns (price, originalPrice) serialize to JSON as STRINGS, not numbers —
// a direct `as num` cast throws for every real record (bit micro_learning_model.dart's price
// the same way; see project_token_refresh_race_bug memory). Parse defensively instead.
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

class CategoryModel {
  final String id;
  final String name;
  final String? nameBn;
  final String? description;
  final String? iconUrl;
  final String? parentId;
  final bool isActive;
  final int? sortOrder;

  const CategoryModel({
    required this.id,
    required this.name,
    this.nameBn,
    this.description,
    this.iconUrl,
    this.parentId,
    this.isActive = true,
    this.sortOrder,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as String,
        name: json['name'] as String,
        nameBn: json['nameBn'] as String?,
        description: json['description'] as String?,
        iconUrl: json['iconUrl'] as String?,
        parentId: json['parentId'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        sortOrder: json['sortOrder'] as int?,
      );

  String displayName(String lang) => lang == 'bn' && nameBn != null ? nameBn! : name;
}

class ServiceTypeModel {
  final String id;
  final String code;
  final String name;
  final String? nameBn;
  final String? description;
  final String? categoryId;
  final String? bookingModelId;
  final String? deliveryModeId;
  final bool isActive;
  final bool isComingSoon;
  final double? basePrice;
  final String? iconUrl;
  final List<String> commonIssues;

  const ServiceTypeModel({
    required this.id,
    required this.code,
    required this.name,
    this.nameBn,
    this.description,
    this.categoryId,
    this.bookingModelId,
    this.deliveryModeId,
    this.isActive = true,
    this.isComingSoon = false,
    this.basePrice,
    this.iconUrl,
    this.commonIssues = const [],
  });

  factory ServiceTypeModel.fromJson(Map<String, dynamic> json) => ServiceTypeModel(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        nameBn: json['nameBn'] as String?,
        description: json['description'] as String?,
        categoryId: json['categoryId'] as String?,
        bookingModelId: json['bookingModelId'] as String?,
        deliveryModeId: json['deliveryModeId'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        isComingSoon: json['isComingSoon'] as bool? ?? false,
        basePrice: _asDoubleOrNull(json['basePrice']),
        iconUrl: json['iconUrl'] as String?,
        commonIssues: (json['commonIssues'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  String displayName(String lang) => lang == 'bn' && nameBn != null ? nameBn! : name;
}

class BookingModelModel {
  final String id;
  final String name;
  final String? description;

  const BookingModelModel({
    required this.id,
    required this.name,
    this.description,
  });

  factory BookingModelModel.fromJson(Map<String, dynamic> json) => BookingModelModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}

class DeliveryModeModel {
  final String id;
  final String name;
  final String? description;

  const DeliveryModeModel({
    required this.id,
    required this.name,
    this.description,
  });

  factory DeliveryModeModel.fromJson(Map<String, dynamic> json) => DeliveryModeModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}

class PricingModelModel {
  final String id;
  final String name;
  final String? description;

  const PricingModelModel({
    required this.id,
    required this.name,
    this.description,
  });

  factory PricingModelModel.fromJson(Map<String, dynamic> json) => PricingModelModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}

class BundleModel {
  final String id;
  final String title;
  final String? titleBn;
  final String? description;
  final String serviceCode;
  final double price;
  final double? originalPrice;
  final bool isActive;
  final List<String> includedItems;

  const BundleModel({
    required this.id,
    required this.title,
    this.titleBn,
    this.description,
    required this.serviceCode,
    required this.price,
    this.originalPrice,
    this.isActive = true,
    this.includedItems = const [],
  });

  factory BundleModel.fromJson(Map<String, dynamic> json) => BundleModel(
        id: json['id'] as String,
        title: json['title'] as String,
        titleBn: json['titleBn'] as String?,
        description: json['description'] as String?,
        serviceCode: json['serviceCode'] as String,
        price: _asDouble(json['price']),
        originalPrice: _asDoubleOrNull(json['originalPrice']),
        isActive: json['isActive'] as bool? ?? true,
        includedItems: (json['includedItems'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  String displayTitle(String lang) => lang == 'bn' && titleBn != null ? titleBn! : title;

  double get discountPercent {
    if (originalPrice == null || originalPrice! <= price) return 0;
    return ((originalPrice! - price) / originalPrice! * 100).roundToDouble();
  }
}
