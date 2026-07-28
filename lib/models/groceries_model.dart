// Prisma Decimal fields serialize as JSON strings, not numbers — every price/
// quantity field below must go through this instead of a raw `as num` cast.
double _asDouble(dynamic v) => v is num ? v.toDouble() : double.parse(v.toString());
double _asDoubleOrZero(dynamic v) => v == null ? 0 : _asDouble(v);

class GroceryCategoryModel {
  final String id;
  final String name;
  final String? imageUrl;
  final bool isActive;

  const GroceryCategoryModel({
    required this.id,
    required this.name,
    this.imageUrl,
    this.isActive = true,
  });

  factory GroceryCategoryModel.fromJson(Map<String, dynamic> json) =>
      GroceryCategoryModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );
}

class GroceryHubModel {
  final String id;
  final String name;
  final String area;
  final String address;
  final double latitude;
  final double longitude;
  final double? distanceKm; // only present when the list was requested with lat/lon

  const GroceryHubModel({
    required this.id,
    required this.name,
    required this.area,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.distanceKm,
  });

  factory GroceryHubModel.fromJson(Map<String, dynamic> json) => GroceryHubModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        area: json['area'] as String? ?? '',
        address: json['address'] as String? ?? '',
        latitude: _asDoubleOrZero(json['latitude']),
        longitude: _asDoubleOrZero(json['longitude']),
        distanceKm: json['distanceKm'] == null ? null : _asDouble(json['distanceKm']),
      );
}

class GroceryProductModel {
  final String id;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? providerId;
  final String? providerName;
  final double price;
  final String unit;
  final double stock;
  final String? description;
  final String? imageUrl;
  final bool isActive;

  const GroceryProductModel({
    required this.id,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.providerId,
    this.providerName,
    required this.price,
    required this.unit,
    this.stock = 0,
    this.description,
    this.imageUrl,
    this.isActive = true,
  });

  factory GroceryProductModel.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return GroceryProductModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      categoryId: json['categoryId'] as String?,
      categoryName: category?['name'] as String?,
      providerId: json['providerId'] as String?,
      providerName: json['providerName'] as String?,
      // Backend field is `pricePerUnit` (Decimal → string).
      price: _asDoubleOrZero(json['pricePerUnit']),
      unit: json['unit'] as String? ?? 'pcs',
      // Backend field is `stockQuantity` (Decimal → string).
      stock: _asDoubleOrZero(json['stockQuantity']),
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      // Backend field is `isAvailable`, not `isActive`.
      isActive: json['isAvailable'] as bool? ?? true,
    );
  }

  bool get inStock => isActive && stock > 0;
}

class CartItemModel {
  final String id;
  final String productId;
  final String productName;
  final String? productImageUrl;
  final double unitPrice;
  final double quantity;
  final String unit;

  const CartItemModel({
    required this.id,
    required this.productId,
    required this.productName,
    this.productImageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.unit,
  });

  // Backend nests the full product under `product` — CartItem itself only
  // carries {id, productId, quantity}.
  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? const {};
    return CartItemModel(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? product['id'] as String? ?? '',
      productName: product['name'] as String? ?? '',
      productImageUrl: product['imageUrl'] as String?,
      unitPrice: _asDoubleOrZero(product['pricePerUnit']),
      quantity: _asDoubleOrZero(json['quantity']),
      unit: product['unit'] as String? ?? 'pcs',
    );
  }

  double get subtotal => unitPrice * quantity;
}

class GroceryCartModel {
  final String userId;
  final List<CartItemModel> items;

  const GroceryCartModel({required this.userId, required this.items});

  factory GroceryCartModel.fromJson(Map<String, dynamic> json) => GroceryCartModel(
        userId: json['userId'] as String? ?? '',
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => CartItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  double get totalAmount => items.fold(0, (sum, i) => sum + i.subtotal);
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity.round());
  bool get isEmpty => items.isEmpty;
}

class GroceryOrderItemModel {
  final String productId;
  final String productName;
  final double quantity;
  final String unit;
  final double pricePerUnit;
  final double totalPrice;

  const GroceryOrderItemModel({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.pricePerUnit,
    required this.totalPrice,
  });

  factory GroceryOrderItemModel.fromJson(Map<String, dynamic> json) =>
      GroceryOrderItemModel(
        productId: json['productId'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        quantity: _asDoubleOrZero(json['quantity']),
        unit: json['unit'] as String? ?? 'pcs',
        pricePerUnit: _asDoubleOrZero(json['pricePerUnit']),
        totalPrice: _asDoubleOrZero(json['totalPrice']),
      );
}

class GroceryOrderModel {
  final String id;
  final String orderNo;
  final String userId;
  final List<GroceryOrderItemModel> items;
  final double totalAmount;
  final double deliveryCharge;
  final String status;
  final String paymentMethod;
  final String deliveryAddress;
  final DateTime createdAt;

  const GroceryOrderModel({
    required this.id,
    required this.orderNo,
    required this.userId,
    required this.items,
    required this.totalAmount,
    required this.deliveryCharge,
    required this.status,
    required this.paymentMethod,
    required this.deliveryAddress,
    required this.createdAt,
  });

  factory GroceryOrderModel.fromJson(Map<String, dynamic> json) =>
      GroceryOrderModel(
        id: json['id'] as String? ?? '',
        orderNo: json['orderNo'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => GroceryOrderItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalAmount: _asDoubleOrZero(json['totalAmount']),
        deliveryCharge: _asDoubleOrZero(json['deliveryCharge']),
        status: json['status'] as String? ?? 'pending',
        paymentMethod: json['paymentMethod'] as String? ?? 'cash_on_delivery',
        deliveryAddress: json['deliveryAddress'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );

  String statusBn() {
    switch (status) {
      case 'pending':
        return 'অপেক্ষমান';
      case 'confirmed':
        return 'নিশ্চিত';
      case 'preparing':
        return 'প্রস্তুত করা হচ্ছে';
      case 'out_for_delivery':
        return 'ডেলিভারি চলছে';
      case 'delivered':
        return 'ডেলিভারি সম্পন্ন';
      case 'cancelled':
        return 'বাতিল';
      default:
        return status;
    }
  }

  bool get isActive =>
      status == 'pending' ||
      status == 'confirmed' ||
      status == 'preparing' ||
      status == 'out_for_delivery';
}
