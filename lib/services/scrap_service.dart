import '../core/network/api_client.dart';

// Backend never sends a Bengali label for scrapType — this is the full enum
// (verified against dispatch-service's Swagger examples). Keep in sync if the
// backend ever adds a type.
const scrapTypeLabelsBn = {
  'iron': 'লোহা',
  'steel': 'স্টিল',
  'aluminum': 'অ্যালুমিনিয়াম',
  'copper': 'তামা',
  'brass': 'পিতল',
  'paper': 'কাগজ',
  'cardboard': 'কার্ডবোর্ড',
  'plastic': 'প্লাস্টিক',
  'glass': 'কাচ',
  'electronic': 'ইলেকট্রনিক',
  'metal': 'ধাতু (অন্যান্য)',
};

String scrapTypeLabelBn(String code) => scrapTypeLabelsBn[code] ?? code;

double _asDouble(dynamic v) => v is num ? v.toDouble() : double.parse(v.toString());
double? _asDoubleOrNull(dynamic v) => v == null ? null : _asDouble(v);

class ScrapRateModel {
  final String scrapType;
  final double ratePerKg;

  const ScrapRateModel({required this.scrapType, required this.ratePerKg});

  factory ScrapRateModel.fromJson(Map<String, dynamic> json) => ScrapRateModel(
        scrapType: json['scrapType'] as String? ?? '',
        ratePerKg: _asDouble(json['ratePerKg'] ?? 0),
      );

  String get labelBn => scrapTypeLabelBn(scrapType);
}

class ScrapRequestModel {
  final String id;
  final List<String> scrapTypes;
  final double estimatedWeightKg;
  final String pickupAddress;
  final DateTime preferredDate;
  final String status; // PENDING | SCHEDULED | COLLECTED | CANCELLED
  final String? adminNote;
  final double? actualWeightKg;
  final double? amountPaidToUser;
  final DateTime createdAt;

  const ScrapRequestModel({
    required this.id,
    required this.scrapTypes,
    required this.estimatedWeightKg,
    required this.pickupAddress,
    required this.preferredDate,
    required this.status,
    this.adminNote,
    this.actualWeightKg,
    this.amountPaidToUser,
    required this.createdAt,
  });

  factory ScrapRequestModel.fromJson(Map<String, dynamic> json) => ScrapRequestModel(
        id: json['id'] as String? ?? '',
        scrapTypes: (json['scrapTypes'] as List<dynamic>?)?.whereType<String>().toList() ?? const [],
        estimatedWeightKg: _asDouble(json['estimatedWeightKg'] ?? 0),
        pickupAddress: json['pickupAddress'] as String? ?? '',
        preferredDate: DateTime.tryParse(json['preferredDate']?.toString() ?? '') ?? DateTime.now(),
        status: json['status'] as String? ?? 'PENDING',
        adminNote: json['adminNote'] as String?,
        actualWeightKg: _asDoubleOrNull(json['actualWeightKg']),
        amountPaidToUser: _asDoubleOrNull(json['amountPaidToUser']),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );

  String get scrapTypesLabelBn => scrapTypes.map(scrapTypeLabelBn).join(', ');
}

class ScrapService {
  static final ScrapService instance = ScrapService._();
  ScrapService._();

  final _client = ApiClient.instance.dio;

  /// Public, no auth — today's per-kg rate for each scrap type.
  Future<List<ScrapRateModel>> getRatesToday() async {
    try {
      final res = await _client.get('/dispatch/scrap-rates/today');
      final list = res.data as List<dynamic>;
      return list.map((e) => ScrapRateModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Server enforces a 10kg minimum — the request 400s below that.
  Future<ScrapRequestModel> createRequest({
    required String userId,
    required List<String> scrapTypes,
    required double estimatedWeightKg,
    required String pickupAddress,
    required DateTime preferredDate,
  }) async {
    try {
      final res = await _client.post('/dispatch/scrap', data: {
        'userId': userId,
        'scrapTypes': scrapTypes,
        'estimatedWeightKg': estimatedWeightKg,
        'pickupAddress': pickupAddress,
        'preferredDate': preferredDate.toIso8601String(),
      });
      return ScrapRequestModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<ScrapRequestModel>> getMyRequests({int limit = 20, int offset = 0}) async {
    try {
      final res = await _client.get('/dispatch/scrap/mine', queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
      });
      final list = res.data as List<dynamic>;
      return list.map((e) => ScrapRequestModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }
}
