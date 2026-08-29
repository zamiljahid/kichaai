import 'package:flutter/material.dart';
import '../core/network/api_client.dart';
import '../models/catalog_model.dart';

class CatalogService {
  static final CatalogService instance = CatalogService._();
  CatalogService._();

  final _client = ApiClient.instance.dio;

  // ── Categories ────────────────────────────────────────────────────

  Future<List<CategoryModel>> getCategories({
    String? parentId,
    bool? onlyActive,
  }) async {
    try {
      final res = await _client.get('/catalog/categories', queryParameters: {
        if (parentId != null) 'parentId': parentId,
        if (onlyActive != null) 'onlyActive': onlyActive.toString(),
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => CategoryModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<CategoryModel> getCategory(String id) async {
    try {
      final res = await _client.get('/catalog/categories/$id');
      return CategoryModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Service Types ─────────────────────────────────────────────────

  Future<List<ServiceTypeModel>> getServiceTypes({
    String? categoryId,
    String? bookingModelId,
    String? deliveryModeId,
  }) async {
    try {
      final res = await _client.get('/catalog/service-types', queryParameters: {
        if (categoryId != null) 'categoryId': categoryId,
        if (bookingModelId != null) 'bookingModelId': bookingModelId,
        if (deliveryModeId != null) 'deliveryModeId': deliveryModeId,
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => ServiceTypeModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<ServiceTypeModel> getServiceType(String id) async {
    try {
      final res = await _client.get('/catalog/service-types/$id');
      return ServiceTypeModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Booking / Delivery / Pricing Models ───────────────────────────

  Future<List<BookingModelModel>> getBookingModels() async {
    try {
      final res = await _client.get('/catalog/booking-models');
      final list = res.data as List<dynamic>;
      return list.map((e) => BookingModelModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<DeliveryModeModel>> getDeliveryModes() async {
    try {
      final res = await _client.get('/catalog/delivery-modes');
      final list = res.data as List<dynamic>;
      return list.map((e) => DeliveryModeModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<PricingModelModel>> getPricingModels() async {
    try {
      final res = await _client.get('/catalog/pricing-models');
      final list = res.data as List<dynamic>;
      return list.map((e) => PricingModelModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Bundles ───────────────────────────────────────────────────────

  Future<List<BundleModel>> getBundles({
    String? serviceCode,
    double? maxPrice,
  }) async {
    try {
      final res = await _client.get('/catalog/bundles', queryParameters: {
        if (serviceCode != null) 'serviceCode': serviceCode,
        if (maxPrice != null) 'maxPrice': maxPrice.toString(),
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => BundleModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<BundleModel>> getMyBundles() async {
    try {
      final res = await _client.get('/catalog/bundles/me');
      final list = res.data as List<dynamic>;
      return list.map((e) => BundleModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Providers package several services together at a discount. The endpoint has always
  /// existed; nothing in the app ever called it, so no bundle could be created from the app.
  Future<BundleModel> createBundle({
    required String bundleName,
    required String description,
    required List<String> servicesIncluded,
    required double originalPrice,
    required double bundlePrice,
  }) async {
    try {
      final discount = originalPrice > 0
          ? (((originalPrice - bundlePrice) / originalPrice) * 100).round()
          : 0;
      final res = await _client.post('/catalog/bundles', data: {
        'bundleName': bundleName,
        'description': description,
        'servicesIncluded': servicesIncluded,
        'originalPrice': originalPrice,
        'bundlePrice': bundlePrice,
        'discountPercent': discount,
      });
      return BundleModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> deleteBundle(String id) async {
    try {
      await _client.delete('/catalog/bundles/$id');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Technician specializations taxonomy (public) ──────────────────
  /// The two-level technician taxonomy: 5 groups × 36 types. Backend is the
  /// single source of truth for codes, Bengali labels and Material icon names —
  /// never hard-code these in the app.
  Future<TechnicianSpecializationTaxonomy> getTechnicianSpecializationsNew() async {
    try {
      final res = await _client.get('/catalog/technician-specializations-new');
      return TechnicianSpecializationTaxonomy.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Photographer / cinematographer equipment taxonomy (public) ────
  /// Categories × items for the EQUIPMENT onboarding card. Backend flags
  /// per category: `multiSelect` (LENS only today) and `cinematographerOnly`
  /// (GIMBAL only today — filter out for photographer applicants).
  Future<EquipmentTaxonomy> getEquipmentTaxonomy() async {
    try {
      final res = await _client.get('/catalog/equipment-taxonomy-new');
      return EquipmentTaxonomy.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}

// ── Technician specialization taxonomy models ─────────────────────

class TechnicianSpecGroup {
  final String code;
  final String bn;
  final String en;
  final String icon; // Material icon name, resolved via technicianSpecIcon()

  const TechnicianSpecGroup({
    required this.code,
    required this.bn,
    required this.en,
    required this.icon,
  });

  factory TechnicianSpecGroup.fromJson(Map<String, dynamic> j) => TechnicianSpecGroup(
        code: j['code'] as String,
        bn: (j['bn'] ?? j['en'] ?? j['code']).toString(),
        en: (j['en'] ?? '').toString(),
        icon: (j['icon'] ?? 'build').toString(),
      );
}

class TechnicianSpecType {
  final String code;
  final String bn;
  final String en;

  const TechnicianSpecType({
    required this.code,
    required this.bn,
    required this.en,
  });

  factory TechnicianSpecType.fromJson(Map<String, dynamic> j) => TechnicianSpecType(
        code: j['code'] as String,
        bn: (j['bn'] ?? j['en'] ?? j['code']).toString(),
        en: (j['en'] ?? '').toString(),
      );
}

class TechnicianSpecTreeNode {
  final TechnicianSpecGroup group;
  final List<TechnicianSpecType> types;

  const TechnicianSpecTreeNode({required this.group, required this.types});

  factory TechnicianSpecTreeNode.fromJson(Map<String, dynamic> j) => TechnicianSpecTreeNode(
        group: TechnicianSpecGroup.fromJson(j),
        types: ((j['types'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TechnicianSpecType.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class TechnicianSpecializationTaxonomy {
  final List<TechnicianSpecGroup> groups;
  final List<TechnicianSpecTreeNode> tree;

  const TechnicianSpecializationTaxonomy({required this.groups, required this.tree});

  factory TechnicianSpecializationTaxonomy.fromJson(Map<String, dynamic> j) =>
      TechnicianSpecializationTaxonomy(
        groups: ((j['groups'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TechnicianSpecGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        tree: ((j['tree'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TechnicianSpecTreeNode.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  /// Type codes belonging to a group — used to translate a set of ticked
  /// specializations back into the (group, type) tuples for display.
  Set<String> typeCodesForGroup(String groupCode) {
    for (final n in tree) {
      if (n.group.code == groupCode) {
        return n.types.map((t) => t.code).toSet();
      }
    }
    return const {};
  }

  /// Look up the Bengali label for a type code, wherever it lives.
  String? typeLabelBn(String typeCode) {
    for (final n in tree) {
      for (final t in n.types) {
        if (t.code == typeCode) return t.bn;
      }
    }
    return null;
  }

  /// Same lookup, language-aware.
  String? typeLabel(String typeCode, bool isBn) {
    for (final n in tree) {
      for (final t in n.types) {
        if (t.code == typeCode) return isBn ? t.bn : t.en;
      }
    }
    return null;
  }
}

// ── Equipment taxonomy models ─────────────────────────────────────
// Codes ending in `_OTHER` unlock a free-text field for that category.
// Codes ending in `_NONE` are "user has none" (only present on optional
// categories like DRONE/GIMBAL) — kept in the serialized output as "নেই"
// so the reviewer sees an explicit answer.

class EquipmentItem {
  final String code;
  final String bn;
  final String en;

  const EquipmentItem({required this.code, required this.bn, required this.en});

  factory EquipmentItem.fromJson(Map<String, dynamic> j) => EquipmentItem(
        code: j['code'] as String,
        bn: (j['bn'] ?? j['en'] ?? j['code']).toString(),
        en: (j['en'] ?? '').toString(),
      );
}

class EquipmentCategory {
  final String code;
  final String bn;
  final String en;
  final bool multiSelect;
  final bool cinematographerOnly;
  final List<EquipmentItem> items;

  const EquipmentCategory({
    required this.code,
    required this.bn,
    required this.en,
    required this.multiSelect,
    required this.cinematographerOnly,
    required this.items,
  });

  factory EquipmentCategory.fromJson(Map<String, dynamic> j) => EquipmentCategory(
        code: j['code'] as String,
        bn: (j['bn'] ?? j['en'] ?? j['code']).toString(),
        en: (j['en'] ?? '').toString(),
        multiSelect: j['multiSelect'] as bool? ?? false,
        cinematographerOnly: j['cinematographerOnly'] as bool? ?? false,
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => EquipmentItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class EquipmentTaxonomy {
  /// The nested `tree` view — categories with their items. Ignore the flat
  /// `categories` view from the response; we always want items alongside.
  final List<EquipmentCategory> tree;

  const EquipmentTaxonomy({required this.tree});

  factory EquipmentTaxonomy.fromJson(Map<String, dynamic> j) => EquipmentTaxonomy(
        tree: ((j['tree'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => EquipmentCategory.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Maps a Material icon name (as returned by the taxonomy) to the actual
/// IconData constant. Falls back to a generic wrench when the backend adds
/// an icon we haven't shipped yet.
IconData technicianSpecIcon(String name) {
  switch (name) {
    case 'directions_car':
      return Icons.directions_car_rounded;
    case 'two_wheeler':
    case 'motorcycle':
      return Icons.two_wheeler_rounded;
    case 'local_shipping':
      return Icons.local_shipping_rounded;
    case 'pedal_bike':
    case 'bike':
      return Icons.pedal_bike_rounded;
    case 'ac_unit':
      return Icons.ac_unit_rounded;
    case 'kitchen':
      return Icons.kitchen_rounded;
    case 'local_laundry_service':
      return Icons.local_laundry_service_rounded;
    case 'microwave':
      return Icons.microwave_rounded;
    case 'tv':
      return Icons.tv_rounded;
    case 'router':
      return Icons.router_rounded;
    case 'electrical_services':
      return Icons.electrical_services_rounded;
    case 'plumbing':
      return Icons.plumbing_rounded;
    case 'carpenter':
      return Icons.carpenter_rounded;
    case 'format_paint':
      return Icons.format_paint_rounded;
    case 'construction':
      return Icons.construction_rounded;
    case 'roofing':
      return Icons.roofing_rounded;
    case 'home_repair_service':
      return Icons.home_repair_service_rounded;
    case 'phone_iphone':
      return Icons.phone_iphone_rounded;
    case 'computer':
    case 'laptop_mac':
      return Icons.computer_rounded;
    case 'print':
      return Icons.print_rounded;
    case 'camera_alt':
      return Icons.camera_alt_rounded;
    case 'watch':
      return Icons.watch_rounded;
    case 'settings':
      return Icons.settings_rounded;
    case 'devices_other':
      return Icons.devices_other_rounded;
    case 'agriculture':
      return Icons.agriculture_rounded;
    case 'grass':
      return Icons.grass_rounded;
    case 'water_drop':
      return Icons.water_drop_rounded;
    case 'lock':
      return Icons.lock_rounded;
    case 'cleaning_services':
      return Icons.cleaning_services_rounded;
    case 'cell_tower':
      return Icons.cell_tower_rounded;
    case 'factory':
      return Icons.factory_rounded;
    default:
      return Icons.build_rounded;
  }
}
