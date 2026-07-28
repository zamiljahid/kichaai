import '../core/network/api_client.dart';

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

class WalletModel {
  final String id;
  final String providerId;
  final double availableBalance;
  final double pendingBalance;
  final double lifetimeEarnings;
  final String currency;

  const WalletModel({
    required this.id,
    required this.providerId,
    required this.availableBalance,
    this.pendingBalance = 0,
    this.lifetimeEarnings = 0,
    this.currency = 'BDT',
  });

  /// Withdrawable balance — kept as `balance` since most of the UI already reads this name.
  double get balance => availableBalance;

  factory WalletModel.fromJson(Map<String, dynamic> json) => WalletModel(
        id: json['id'] as String? ?? '',
        providerId: json['providerId'] as String? ?? '',
        availableBalance: _asDouble(json['availableBalance']),
        pendingBalance: _asDouble(json['pendingBalance']),
        lifetimeEarnings: _asDouble(json['lifetimeEarnings']),
        currency: json['currencyCode'] as String? ?? 'BDT',
      );
}

class TransactionModel {
  final String id;
  final String walletId;
  final String transactionType;
  final double amount;
  final double? balanceAfter;
  final String? description;
  final String? sourceType;
  final String? sourceId;
  final DateTime createdAt;

  const TransactionModel({
    required this.id,
    required this.walletId,
    required this.transactionType,
    required this.amount,
    this.balanceAfter,
    this.description,
    this.sourceType,
    this.sourceId,
    required this.createdAt,
  });

  /// Money in vs money out — the backend has no separate credit/debit flag, only a
  /// transactionType enum (…_earning/adjustment_credit vs …_debit/commission_deduction).
  bool get isCredit =>
      !(transactionType.endsWith('_debit') || transactionType == 'commission_deduction');

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: json['id'] as String,
        walletId: json['walletId'] as String? ?? '',
        transactionType: json['transactionType'] as String? ?? '',
        amount: _asDouble(json['amount']),
        balanceAfter: json['balanceAfter'] != null ? _asDouble(json['balanceAfter']) : null,
        description: json['description'] as String?,
        sourceType: json['sourceType'] as String?,
        sourceId: json['sourceId'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class FinanceService {
  static final FinanceService instance = FinanceService._();
  FinanceService._();

  final _client = ApiClient.instance.dio;

  /// Always the logged-in provider's own wallet — /finance/wallet/:id is admin-only
  /// (that route previously 403'd for every regular provider looking up their own wallet).
  Future<WalletModel> getWallet() async {
    try {
      final res = await _client.get('/finance/wallet/me');
      return WalletModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<TransactionModel>> listTransactions({String? providerId}) async {
    try {
      final res = await _client.get('/finance/transactions', queryParameters: {
        if (providerId != null) 'providerId': providerId,
      });
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (list as List)
          .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<Map<String, dynamic>>> listPayouts({String? providerId}) async {
    try {
      final res = await _client.get('/finance/payouts', queryParameters: {
        if (providerId != null) 'providerId': providerId,
      });
      final data = res.data;
      final list = data is List ? data : (data['items'] ?? data['data'] ?? []);
      return (list as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> requestPayout({
    required String providerId,
    required double amount,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
  }) async {
    try {
      await _client.post('/finance/payouts', data: {
        'providerId': providerId,
        'amount': amount,
        'bankName': bankName,
        'bankAccountNumber': accountNumber,
        'accountHolderName': accountHolder,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
