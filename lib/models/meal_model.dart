// "Meal Group" (মিল গ্রুপ), not "Mess" — মেস already means the shared-housing
// rental/listing search feature elsewhere in the app; this is unrelated
// (roommates splitting daily meals + grocery cost).

class MealGroup {
  final String id;
  final String name;
  final String inviteCode;
  final String createdByUserId;
  final DateTime createdAt;
  final String? myRole; // 'manager' | 'member' — only present on listMyGroups()

  MealGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdByUserId,
    required this.createdAt,
    this.myRole,
  });

  bool get isManager => myRole == 'manager';

  factory MealGroup.fromJson(Map<String, dynamic> json) => MealGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        inviteCode: json['inviteCode'] as String,
        createdByUserId: json['createdByUserId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        myRole: json['myRole'] as String?,
      );
}

class MealGroupMember {
  final String id;
  final String groupId;
  final String userId;
  final String? nameSnapshot;
  final String role; // 'manager' | 'member'
  final DateTime joinedAt;
  final bool isActive;

  MealGroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    this.nameSnapshot,
    required this.role,
    required this.joinedAt,
    required this.isActive,
  });

  String get displayName =>
      (nameSnapshot != null && nameSnapshot!.trim().isNotEmpty) ? nameSnapshot! : 'সদস্য';

  bool get isManager => role == 'manager';

  factory MealGroupMember.fromJson(Map<String, dynamic> json) => MealGroupMember(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        userId: json['userId'] as String,
        nameSnapshot: json['nameSnapshot'] as String?,
        role: json['role'] as String,
        joinedAt: DateTime.parse(json['joinedAt'] as String),
        isActive: json['isActive'] as bool? ?? true,
      );
}

class DailyMealEntry {
  final String id;
  final String groupId;
  final String userId;
  final DateTime date;
  final bool ateBreakfast;
  final bool ateLunch;
  final bool ateDinner;

  DailyMealEntry({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.date,
    this.ateBreakfast = false,
    required this.ateLunch,
    required this.ateDinner,
  });

  int get mealCount => (ateBreakfast ? 1 : 0) + (ateLunch ? 1 : 0) + (ateDinner ? 1 : 0);

  factory DailyMealEntry.fromJson(Map<String, dynamic> json) => DailyMealEntry(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        userId: json['userId'] as String,
        date: DateTime.parse(json['date'] as String),
        ateBreakfast: json['ateBreakfast'] as bool? ?? false,
        ateLunch: json['ateLunch'] as bool? ?? false,
        ateDinner: json['ateDinner'] as bool? ?? false,
      );
}

class MealDeposit {
  final String id;
  final String groupId;
  final String userId;
  final double amount;
  final String? note;
  final DateTime date;
  final DateTime createdAt;

  MealDeposit({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.amount,
    this.note,
    required this.date,
    required this.createdAt,
  });

  factory MealDeposit.fromJson(Map<String, dynamic> json) => MealDeposit(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        userId: json['userId'] as String,
        amount: double.parse(json['amount'].toString()),
        note: json['note'] as String?,
        date: DateTime.parse(json['date'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class GroceryExpense {
  final String id;
  final String groupId;
  final String addedByUserId;
  final double amount;
  final String? description;
  final DateTime date;
  final DateTime createdAt;

  GroceryExpense({
    required this.id,
    required this.groupId,
    required this.addedByUserId,
    required this.amount,
    this.description,
    required this.date,
    required this.createdAt,
  });

  factory GroceryExpense.fromJson(Map<String, dynamic> json) => GroceryExpense(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        addedByUserId: json['addedByUserId'] as String,
        amount: double.parse(json['amount'].toString()),
        description: json['description'] as String?,
        date: DateTime.parse(json['date'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class MemberBalance {
  final String userId;
  final String name;
  final String role; // 'manager' | 'member'
  final int mealCount;
  final double paid; // total contributed: grocery purchases + deposits
  final double deposited; // deposits only, a breakdown of `paid`
  final double owed;
  final double balance; // positive = owed money back, negative = owes the group

  MemberBalance({
    required this.userId,
    required this.name,
    required this.role,
    required this.mealCount,
    required this.paid,
    required this.deposited,
    required this.owed,
    required this.balance,
  });

  factory MemberBalance.fromJson(Map<String, dynamic> json) => MemberBalance(
        userId: json['userId'] as String,
        name: (json['nameSnapshot'] as String?)?.trim().isNotEmpty == true
            ? json['nameSnapshot'] as String
            : 'সদস্য',
        role: json['role'] as String? ?? 'member',
        mealCount: (json['meals'] as num?)?.toInt() ?? 0,
        paid: double.parse((json['paid'] ?? 0).toString()),
        deposited: double.parse((json['deposited'] ?? 0).toString()),
        owed: double.parse((json['owed'] ?? 0).toString()),
        balance: double.parse((json['balance'] ?? 0).toString()),
      );
}

class MonthlySummary {
  final int totalMeals;
  final double totalSpend;
  final double totalDeposits;
  final double perMealRate;
  final List<MemberBalance> members;

  MonthlySummary({
    required this.totalMeals,
    required this.totalSpend,
    required this.totalDeposits,
    required this.perMealRate,
    required this.members,
  });

  factory MonthlySummary.fromJson(Map<String, dynamic> json) => MonthlySummary(
        totalMeals: (json['totalMeals'] as num?)?.toInt() ?? 0,
        totalSpend: double.parse((json['totalSpend'] ?? 0).toString()),
        totalDeposits: double.parse((json['totalDeposits'] ?? 0).toString()),
        perMealRate: double.parse((json['perMealRate'] ?? 0).toString()),
        members: (json['members'] as List<dynamic>? ?? [])
            .map((m) => MemberBalance.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}
