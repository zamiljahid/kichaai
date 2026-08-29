class UserModel {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;

  /// Every role the account holds. `role` is the currently active one; a user can be both
  /// a customer and a provider, so a check like "can this account provide services" must
  /// look here, not at `role` alone.
  final List<String> roles;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final String? profileImageUrl;
  final String? tier;
  final String? providerProfileId;

  const UserModel({
    required this.id,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    this.roles = const [],
    this.isEmailVerified = false,
    this.isPhoneVerified = false,
    this.profileImageUrl,
    this.tier,
    this.providerProfileId,
  });

  // GET /auth/me sends activeRole/roles, avatarUrl and *VerifiedAt timestamps. This used to
  // read 'role', 'profileImageUrl' and boolean is*Verified keys, none of which the API has
  // ever returned — so role fell back to 'user' for everyone (hiding every provider tool on
  // the profile screen), the avatar never rendered, and the "Verified" badge never appeared
  // even for a verified account. Old key names are still accepted second so any other caller
  // constructing a UserModel from a differently-shaped payload keeps working.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<String> rolesOf(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    final roles = rolesOf(json['roles']);
    final role = (json['activeRole'] as String?) ??
        (json['role'] as String?) ??
        (roles.contains('provider') ? 'provider' : null) ??
        'user';

    bool verified(String tsKey, String boolKey) =>
        json[tsKey] != null || (json[boolKey] as bool? ?? false);

    return UserModel(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: (json['isAdmin'] as bool? ?? false) ? 'admin' : role,
      roles: roles,
      isEmailVerified: verified('emailVerifiedAt', 'isEmailVerified'),
      isPhoneVerified: verified('phoneVerifiedAt', 'isPhoneVerified'),
      profileImageUrl:
          (json['avatarUrl'] as String?) ?? (json['profileImageUrl'] as String?),
      tier: json['tier'] as String?,
      providerProfileId: json['providerProfileId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'role': role,
        'roles': roles,
        'isEmailVerified': isEmailVerified,
        'isPhoneVerified': isPhoneVerified,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (tier != null) 'tier': tier,
      };

  UserModel copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? profileImageUrl,
    String? tier,
  }) =>
      UserModel(
        id: id,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role,
        roles: roles,
        isEmailVerified: isEmailVerified,
        isPhoneVerified: isPhoneVerified,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
        tier: tier ?? this.tier,
      );
}

class AddressModel {
  final String id;
  final String? label;
  final String line1;
  final String? line2;
  final String? area;
  final String? city;
  final String? district;
  final String? postalCode;
  final bool isDefault;

  const AddressModel({
    required this.id,
    this.label,
    required this.line1,
    this.line2,
    this.area,
    this.city,
    this.district,
    this.postalCode,
    this.isDefault = false,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) => AddressModel(
        id: json['id'] as String,
        label: json['label'] as String?,
        line1: json['line1'] as String,
        line2: json['line2'] as String?,
        area: json['area'] as String?,
        city: json['city'] as String?,
        district: json['district'] as String?,
        postalCode: json['postalCode'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  String get displayText {
    final parts = [line1, if (line2 != null) line2, if (area != null) area, if (city != null) city];
    return parts.join(', ');
  }
}

class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final UserModel user;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      );
}
