import '../core/network/api_client.dart';
import '../models/meal_model.dart';

/// "Meal Group" (মিল গ্রুপ) — roommates' daily meal + grocery cost tracker.
/// Deliberately not named "Mess" — see meal_model.dart's header comment.
class MealService {
  static final MealService instance = MealService._();
  MealService._();

  final _client = ApiClient.instance.dio;

  Future<MealGroup> createGroup({required String name, String? nameSnapshot}) async {
    try {
      final res = await _client.post('/meal/groups', data: {
        'name': name,
        if (nameSnapshot != null) 'nameSnapshot': nameSnapshot,
      });
      return MealGroup.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Returns (group, alreadyMember).
  Future<(MealGroup, bool)> joinGroup({required String inviteCode, String? nameSnapshot}) async {
    try {
      final res = await _client.post('/meal/join', data: {
        'inviteCode': inviteCode,
        if (nameSnapshot != null) 'nameSnapshot': nameSnapshot,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return (
        MealGroup.fromJson(Map<String, dynamic>.from(data['group'] as Map)),
        data['alreadyMember'] as bool? ?? false,
      );
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<MealGroup>> listMyGroups() async {
    try {
      final res = await _client.get('/meal/groups');
      return (res.data as List<dynamic>)
          .map((g) => MealGroup.fromJson(Map<String, dynamic>.from(g as Map)))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<MealGroup> getGroup(String groupId) async {
    try {
      final res = await _client.get('/meal/groups/$groupId');
      return MealGroup.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<MealGroupMember>> listMembers(String groupId) async {
    try {
      final res = await _client.get('/meal/groups/$groupId/members');
      return (res.data as List<dynamic>)
          .map((m) => MealGroupMember.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> leaveGroup(String groupId) async {
    try {
      await _client.delete('/meal/groups/$groupId/members/me');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<DailyMealEntry> logDailyMeal({
    required String groupId,
    required DateTime date,
    bool? ateBreakfast,
    bool? ateLunch,
    bool? ateDinner,
    String? targetUserId,
  }) async {
    try {
      final res = await _client.post('/meal/groups/$groupId/meals', data: {
        'date': _dateOnly(date),
        if (ateBreakfast != null) 'ateBreakfast': ateBreakfast,
        if (ateLunch != null) 'ateLunch': ateLunch,
        if (ateDinner != null) 'ateDinner': ateDinner,
        if (targetUserId != null) 'targetUserId': targetUserId,
      });
      return DailyMealEntry.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<DailyMealEntry>> listMealEntries({required String groupId, required String month}) async {
    try {
      final res = await _client.get('/meal/groups/$groupId/meals', queryParameters: {'month': month});
      return (res.data as List<dynamic>)
          .map((e) => DailyMealEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<GroceryExpense> addGroceryExpense({
    required String groupId,
    required double amount,
    String? description,
    required DateTime date,
    String? targetUserId,
  }) async {
    try {
      final res = await _client.post('/meal/groups/$groupId/expenses', data: {
        'amount': amount,
        if (description != null && description.isNotEmpty) 'description': description,
        'date': _dateOnly(date),
        if (targetUserId != null) 'targetUserId': targetUserId,
      });
      return GroceryExpense.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<GroceryExpense>> listGroceryExpenses({required String groupId, required String month}) async {
    try {
      final res = await _client.get('/meal/groups/$groupId/expenses', queryParameters: {'month': month});
      return (res.data as List<dynamic>)
          .map((e) => GroceryExpense.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<MonthlySummary> getMonthlySummary({required String groupId, required String month}) async {
    try {
      final res = await _client.get('/meal/groups/$groupId/summary', queryParameters: {'month': month});
      return MonthlySummary.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Money handed over for the shared grocery fund — distinct from an actual purchase
  /// (addGroceryExpense). Both count toward a member's contribution in the monthly split.
  Future<MealDeposit> addDeposit({
    required String groupId,
    required double amount,
    String? note,
    required DateTime date,
    String? targetUserId,
  }) async {
    try {
      final res = await _client.post('/meal/groups/$groupId/deposits', data: {
        'amount': amount,
        if (note != null && note.isNotEmpty) 'note': note,
        'date': _dateOnly(date),
        if (targetUserId != null) 'targetUserId': targetUserId,
      });
      return MealDeposit.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<List<MealDeposit>> listDeposits({required String groupId, required String month}) async {
    try {
      final res = await _client.get('/meal/groups/$groupId/deposits', queryParameters: {'month': month});
      return (res.data as List<dynamic>)
          .map((d) => MealDeposit.fromJson(Map<String, dynamic>.from(d as Map)))
          .toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
