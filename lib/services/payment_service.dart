import '../core/network/api_client.dart';

class PaymentTransaction {
  final String id;
  final String orderId;
  final String orderType;
  final double amount;
  final String status; // pending | processing | completed | failed | refunded
  final String? gatewayPageUrl;

  const PaymentTransaction({
    required this.id,
    required this.orderId,
    required this.orderType,
    required this.amount,
    required this.status,
    this.gatewayPageUrl,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) => PaymentTransaction(
        id: json['id'] as String? ?? '',
        orderId: json['orderId'] as String? ?? '',
        orderType: json['orderType'] as String? ?? '',
        amount: double.tryParse('${json['amount']}') ?? 0,
        status: json['status'] as String? ?? 'pending',
        gatewayPageUrl: json['gatewayPageUrl'] as String?,
      );

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isSettled => isCompleted || isFailed || status == 'refunded';
}

class PaymentService {
  static final PaymentService instance = PaymentService._();
  PaymentService._();

  final _client = ApiClient.instance.dio;

  /// Creates a transaction row and, for gateway=sslcommerz, starts a real gateway session —
  /// the returned gatewayPageUrl is where the customer actually pays. Null gatewayPageUrl
  /// means either a non-gateway payment method (wallet/cash) or the gateway call failed.
  Future<PaymentTransaction> initiateTransaction({
    required String orderId,
    required String orderType,
    required double amount,
    String gateway = 'sslcommerz',
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? customerAddress,
  }) async {
    try {
      final userId = await ApiClient.getUserId();
      final name = customerName ?? await ApiClient.getFullName();
      final email = customerEmail ?? await ApiClient.getEmail();
      final phone = customerPhone ?? await ApiClient.getPhone();
      final res = await _client.post('/payment/transactions', data: {
        'orderId': orderId,
        'orderType': orderType,
        'customerId': userId,
        'amount': amount,
        'gateway': gateway,
        if (name != null) 'customerName': name,
        if (email != null) 'customerEmail': email,
        if (phone != null) 'customerPhone': phone,
        if (customerAddress != null) 'customerAddress': customerAddress,
      });
      return PaymentTransaction.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<PaymentTransaction?> getTransactionByOrderId(String orderId) async {
    try {
      final res = await _client.get('/payment/transactions/by-order/$orderId');
      if (res.data == null) return null;
      return PaymentTransaction.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
