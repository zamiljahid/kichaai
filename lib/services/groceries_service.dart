import '../core/network/api_client.dart';
import '../models/groceries_model.dart';

class GroceriesService {
  static final GroceriesService instance = GroceriesService._();
  GroceriesService._();

  final _client = ApiClient.instance.dio;

  // ── Hubs ──────────────────────────────────────────────────────────
  // Every order is filled through exactly one admin-run hub — pass the
  // customer's location to get nearest-first results with distanceKm attached.

  Future<List<GroceryHubModel>> listHubs({double? lat, double? lon}) async {
    try {
      final res = await _client.get('/groceries/hubs', queryParameters: {
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => GroceryHubModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Categories ────────────────────────────────────────────────────

  Future<List<GroceryCategoryModel>> getCategories() async {
    try {
      final res = await _client.get('/groceries/categories');
      final list = res.data as List<dynamic>;
      return list
          .map((e) => GroceryCategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Products ──────────────────────────────────────────────────────

  Future<List<GroceryProductModel>> listProducts({
    String? categoryId,
    String? providerId,
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      // NOTE: the backend accepts a `search` query param but silently ignores
      // it (no name-filter implemented server-side) — don't send it, it would
      // just mislead callers into thinking search narrowed the results.
      final res = await _client.get('/groceries/products', queryParameters: {
        if (categoryId != null) 'categoryId': categoryId,
        if (providerId != null) 'providerId': providerId,
        'offset': offset.toString(),
        'limit': limit.toString(),
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => GroceryProductModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<GroceryProductModel> getProduct(String id) async {
    try {
      final res = await _client.get('/groceries/products/$id');
      return GroceryProductModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Cart ──────────────────────────────────────────────────────────
  // The server cart is the single source of truth — every add/remove call
  // hits the API immediately rather than staging changes in local state,
  // so the UI never drifts from what checkout() will actually see.

  Future<GroceryCartModel> getCart(String userId) async {
    try {
      final res = await _client.get('/groceries/cart/$userId');
      return GroceryCartModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Increments the item's quantity by [quantity] (creates it at [quantity]
  /// if not already in the cart) — this is an ADD, not a set.
  Future<GroceryCartModel> addToCart({
    required String userId,
    required String productId,
    int quantity = 1,
  }) async {
    try {
      await _client.post('/groceries/cart', data: {
        'userId': userId,
        'productId': productId,
        'quantity': quantity,
      });
      // Backend returns the single upserted CartItem, not the whole cart —
      // refetch so the UI has authoritative totals.
      return getCart(userId);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Sets the item's quantity to exactly [quantity] — 0 removes it.
  Future<GroceryCartModel> setCartItemQuantity({
    required String userId,
    required String productId,
    required int quantity,
  }) async {
    try {
      await _client.patch('/groceries/cart/item', data: {
        'userId': userId,
        'productId': productId,
        'quantity': quantity,
      });
      return getCart(userId);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> clearCart(String userId) async {
    try {
      await _client.post('/groceries/cart/$userId/clear');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Orders ────────────────────────────────────────────────────────

  /// Checks out whatever is currently in the SERVER cart for [userId] — the
  /// call carries no line items, so add-to-cart must have already happened.
  /// [deliveryAddress] is required only when [fulfillmentMethod] is 'delivery'
  /// — for 'pickup' the customer collects at [hubId] themselves.
  Future<GroceryOrderModel> checkout({
    required String userId,
    required String hubId,
    required String fulfillmentMethod, // pickup | delivery
    required String paymentMethod, // wallet | cash_on_delivery | bkash | nagad
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? notes,
  }) async {
    try {
      final res = await _client.post('/groceries/orders/checkout', data: {
        'userId': userId,
        'hubId': hubId,
        'fulfillmentMethod': fulfillmentMethod,
        'paymentMethod': paymentMethod,
        if (deliveryAddress != null && deliveryAddress.isNotEmpty) 'deliveryAddress': deliveryAddress,
        if (deliveryLatitude != null) 'deliveryLatitude': deliveryLatitude,
        if (deliveryLongitude != null) 'deliveryLongitude': deliveryLongitude,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });
      return GroceryOrderModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<GroceryOrderModel> getOrder(String id) async {
    try {
      final res = await _client.get('/groceries/orders/$id');
      return GroceryOrderModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<GroceryOrderModel>> listOrders({
    required String userId,
    String? status,
  }) async {
    try {
      final res = await _client.get('/groceries/orders', queryParameters: {
        'userId': userId,
        if (status != null) 'status': status,
      });
      final list = res.data as List<dynamic>;
      return list
          .map((e) => GroceryOrderModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
