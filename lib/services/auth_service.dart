import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../core/network/api_client.dart';
import '../models/user_model.dart';
import 'dispatch_service.dart';
import 'push_service.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final _client = ApiClient.instance.dio;

  // Both platforms use the SAME Web OAuth client audience — that's what our
  // backend's /auth/google verifies against. On mobile it goes via
  // serverClientId (SDK returns an id_token stamped with that audience).
  // On web the plugin rejects serverClientId — has to be passed as clientId.
  static const _webClientId =
      '635941830068-6vjp82j9h61ib92jt9o38uokooce16mn.apps.googleusercontent.com';
  static final _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? _webClientId : null,
    serverClientId: kIsWeb ? null : _webClientId,
    scopes: const ['email', 'profile'],
  );

  // ── Sign Up ───────────────────────────────────────────────────────

  /// Returns null when the server requires email verification before issuing tokens.
  Future<AuthResponse?> signup({
    required String fullName,
    required String email,
    required String password,
    String? phone,
    String role = 'user',
  }) async {
    try {
      final res = await _client.post('/auth/signup', data: {
        'fullName': fullName,
        'email': email,
        'password': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'role': role,
      });
      final data = res.data as Map<String, dynamic>;
      if (!data.containsKey('accessToken')) {
        return null; // email verification required
      }

      await ApiClient.clearProviderCache();

      final auth = AuthResponse.fromJson(data);
      final rawPpid = data['providerProfileId'] as String?;
      final providerProfileId = (rawPpid != null && rawPpid.isNotEmpty)
          ? rawPpid
          : auth.user.providerProfileId;

      await ApiClient.saveTokens(
        accessToken: auth.accessToken,
        refreshToken: auth.refreshToken,
        userId: auth.user.id,
        fullName: auth.user.fullName,
        email: auth.user.email,
        phone: auth.user.phone,
        role: (providerProfileId != null && providerProfileId.isNotEmpty)
            ? 'PROVIDER'
            : 'CUSTOMER',
        providerProfileId: providerProfileId,
      );
      await PushService.instance.registerCurrentToken();
      return auth;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Login ─────────────────────────────────────────────────────────

  Future<AuthResponse> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final res = await _client.post('/auth/login', data: {
        'identifier': identifier,
        'password': password,
      });
      final data = res.data as Map<String, dynamic>;

      // Wipe stale provider state from the previous session before saving new data.
      await ApiClient.clearProviderCache();

      final auth = AuthResponse.fromJson(data);

      // providerProfileId may be at the top level of the response (alongside
      // accessToken) rather than nested inside the user object.
      final rawPpid = data['providerProfileId'] as String?;
      final providerProfileId = (rawPpid != null && rawPpid.isNotEmpty)
          ? rawPpid
          : auth.user.providerProfileId;

      await ApiClient.saveTokens(
        accessToken: auth.accessToken,
        refreshToken: auth.refreshToken,
        userId: auth.user.id,
        fullName: auth.user.fullName,
        email: auth.user.email,
        phone: auth.user.phone,
        role: (providerProfileId != null && providerProfileId.isNotEmpty)
            ? 'PROVIDER'
            : 'CUSTOMER',
        providerProfileId: providerProfileId,
      );
      await PushService.instance.registerCurrentToken();
      return auth;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────
  /// Returns null when the user cancels the account picker.
  /// Backend creates the account on first sight — signup and login share this flow.
  /// Google users are always CUSTOMER (no providerProfileId in the response).
  Future<AuthResponse?> googleLogin() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null; // user cancelled picker

    final auth = await account.authentication;
    final idToken = auth.idToken;
    final accessToken = auth.accessToken;

    // On web, GIS often returns a null idToken but a valid accessToken. Backend
    // /auth/google accepts either shape and verifies the audience on its side.
    final Map<String, dynamic> body;
    if (idToken != null && idToken.isNotEmpty) {
      body = {'idToken': idToken};
    } else if (accessToken != null && accessToken.isNotEmpty) {
      body = {'accessToken': accessToken};
    } else {
      throw Exception('Google sign-in returned no usable token.');
    }

    try {
      final res = await _client.post('/auth/google', data: body);
      final data = res.data as Map<String, dynamic>;

      await ApiClient.clearProviderCache();
      final authResponse = AuthResponse.fromJson(data);

      await ApiClient.saveTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
        userId: authResponse.user.id,
        fullName: authResponse.user.fullName,
        email: authResponse.user.email,
        phone: authResponse.user.phone,
        role: 'CUSTOMER',
        providerProfileId: null,
      );
      await PushService.instance.registerCurrentToken();
      return authResponse;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Logout ────────────────────────────────────────────────────────

  Future<void> logout() async {
    DispatchService.instance.stopLocationTracking();
    try {
      await _client.post('/auth/logout');
    } catch (_) {
      // always clear local tokens even if the server call fails
    } finally {
      // Sign out of Google too — otherwise the next login skips the account
      // picker and silently re-uses the previous Google account.
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      // Must run before clearTokens — the DELETE call scopes to the JWT.
      await PushService.instance.deactivateCurrentToken();
      await ApiClient.clearTokens();
    }
  }

  // ── Forgot Password ───────────────────────────────────────────────

  Future<void> forgotPassword({required String identifier}) async {
    try {
      await _client.post('/auth/forgot-password', data: {'identifier': identifier});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Reset Password ────────────────────────────────────────────────

  Future<void> resetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    try {
      await _client.post('/auth/reset-password', data: {
        'identifier': identifier,
        'otp': otp,
        'newPassword': newPassword,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────

  Future<void> verifyOtp({
    required String targetValue,
    required String targetType,
    required String otpCode,
    required String purpose,
  }) async {
    try {
      await _client.post('/auth/verify-otp', data: {
        'targetValue': targetValue,
        'targetType': targetType,
        'otpCode': otpCode,
        'purpose': purpose,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────

  Future<void> resendOtp({
    required String targetValue,
    required String targetType,
    required String purpose,
  }) async {
    try {
      await _client.post('/auth/resend-otp', data: {
        'targetValue': targetValue,
        'targetType': targetType,
        'purpose': purpose,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Get Current User ──────────────────────────────────────────────

  Future<UserModel> getCurrentUser() async {
    try {
      final res = await _client.get('/auth/me');
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Raw /auth/me payload — exposes providerProfile.legalAreas and
  /// verificationStatus, which UserModel doesn't carry.
  Future<Map<String, dynamic>> getMeRaw() async {
    try {
      final res = await _client.get('/auth/me');
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Lawyer: update my practice areas after onboarding — consultation
  /// broadcasts route by these, so stale areas mean missed (or wrong) cases.
  /// Returns the persisted list (backend drops unknown codes).
  Future<List<String>> updateLegalAreas(List<String> legalAreas) async {
    try {
      final res = await _client.patch('/auth/provider-profile/legal-areas',
          data: {'legalAreas': legalAreas});
      final data = res.data;
      if (data is Map && data['legalAreas'] is List) {
        return (data['legalAreas'] as List).whereType<String>().toList();
      }
      return legalAreas;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Lawyer: update which specific services (bail, court representation,
  /// consultation…) I deliver — consultation broadcasts filter on these, so a
  /// service left unchecked here means matching jobs never reach me.
  Future<List<String>> updateLegalServices(List<String> legalServices) async {
    try {
      final res = await _client.patch('/auth/provider-profile/legal-services',
          data: {'legalServices': legalServices});
      final data = res.data;
      if (data is Map && data['legalServices'] is List) {
        return (data['legalServices'] as List).whereType<String>().toList();
      }
      return legalServices;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// caregiver/photographer/cinematographer/makeup_artist: set the provider's real
  /// gender so a customer's gender preference on these 4 services is an actual filter
  /// instead of decorative. Also gates going online for these kinds — see
  /// DispatchService.startSession / dispatch-service's startLiveSession.
  /// Returns the persisted value (backend rejects anything but male/female with a 400).
  Future<String> updateGender(String gender) async {
    try {
      final res = await _client.patch('/auth/provider-profile/gender',
          data: {'gender': gender});
      final data = res.data;
      if (data is Map && data['gender'] is String) {
        return data['gender'] as String;
      }
      return gender;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Free-text "what I'm especially good at" — shown on the customer-facing provider
  /// profile. Account-level, not per-service. Max 300 chars (trimmed server-side).
  Future<void> updateSpecialNote(String specialNote) async {
    try {
      await _client.patch('/auth/provider-profile/special-note', data: {'specialNote': specialNote});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// {hasPhoto, hasPhone, rulesAgreed} — all three gate going online (see
  /// DispatchService.startSession / dispatch-service's startLiveSession).
  Future<Map<String, bool>> getProviderProfileCompleteness() async {
    try {
      final res = await _client.get('/auth/provider-profile/completeness');
      final data = res.data as Map;
      return {
        'hasPhoto': data['hasPhoto'] as bool? ?? false,
        'hasPhone': data['hasPhone'] as bool? ?? false,
        'rulesAgreed': data['rulesAgreed'] as bool? ?? false,
      };
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  /// Gates going online alongside profile-photo/phone completeness — see
  /// DispatchService.startSession / dispatch-service's startLiveSession.
  Future<void> agreeToProviderRules() async {
    try {
      await _client.post('/auth/provider-profile/agree-rules');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Update Profile ────────────────────────────────────────────────

  Future<UserModel> updateProfile({String? fullName, String? phone}) async {
    try {
      final res = await _client.patch('/auth/me', data: {
        if (fullName != null) 'fullName': fullName,
        if (phone != null) 'phone': phone,
      });
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Change Password ───────────────────────────────────────────────

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _client.patch('/auth/me/password', data: {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      });
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Delete Account (Play Store / privacy compliance) ──────────────
  /// Soft-deletes + anonymizes the current account and revokes all sessions.
  /// Local tokens are always cleared afterward, even if the call fails.
  Future<void> deleteAccount() async {
    try {
      await _client.delete('/auth/me');
    } catch (e) {
      throw ApiClient.mapError(e); // keep the session so the user can retry
    }
    await ApiClient.clearTokens(); // only wipe local state once deletion succeeds
  }

  // ── Switch active role ────────────────────────────────────────────
  /// Reissues a scoped JWT with the new activeRole claim and stores it.
  /// Returns the active role ('customer' | 'provider'). Throws (403) if the
  /// account doesn't hold the target role yet — call becomeProvider first.
  Future<String> switchRole(String targetRole) async {
    try {
      final res = await _client.post('/auth/switch-role', data: {'targetRole': targetRole});
      final data = res.data as Map<String, dynamic>;
      final newToken = data['accessToken'] as String?;
      if (newToken != null && newToken.isNotEmpty) {
        await ApiClient.setAccessToken(newToken);
      }
      return data['activeRole'] as String? ?? targetRole;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Become Provider ───────────────────────────────────────────────

  Future<void> becomeProvider() async {
    try {
      await _client.post('/auth/me/become-provider');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Technician specializations (multi-select taxonomy) ────────────
  /// Save the technician's picked specialization codes. The backend drops any
  /// unknown code, so the returned list is the source of truth for what was
  /// actually persisted — reflect it back into the chips.
  Future<List<String>> saveTechnicianSpecializations(List<String> codes) async {
    try {
      final res = await _client.patch(
        '/auth/provider-profile/specializations-new',
        data: {'specializations': codes},
      );
      final data = res.data;
      final raw = data is Map ? data['specializations'] : null;
      if (raw is List) {
        return raw.whereType<String>().toList();
      }
      return codes;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Provider profile photo (selfie) ───────────────────────────────
  /// Uploads a base64-encoded image (no data-URI prefix). Returns the stored URL.
  /// Verification-context selfie shown to admins during application review — NOT the
  /// everyday account avatar (that's uploadProfilePhoto below, writes to GET /auth/me's
  /// avatarUrl and works for any logged-in user, customer or provider).
  Future<String?> uploadProviderProfilePhoto(String base64Image) async {
    try {
      final res = await _client.post('/auth/provider/profile-photo', data: {'image': base64Image});
      final data = res.data;
      return data is Map ? data['profilePhotoUrl'] as String? : null;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Account avatar (any logged-in user) ───────────────────────────
  /// Uploads a base64-encoded image (no data-URI prefix). Returns the stored URL.
  /// This is the general account picture — populates GET /auth/me's `avatarUrl`.
  Future<String?> uploadProfilePhoto(String base64Image) async {
    try {
      final res = await _client.post('/auth/me/profile-photo', data: {'image': base64Image});
      final data = res.data;
      return data is Map ? data['avatarUrl'] as String? : null;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Phone / Email Verification ────────────────────────────────────

  Future<void> startPhoneVerification() async {
    try {
      await _client.post('/auth/me/verify-phone');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> startEmailVerification() async {
    try {
      await _client.post('/auth/me/verify-email');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Addresses ─────────────────────────────────────────────────────

  Future<List<AddressModel>> listAddresses() async {
    try {
      final res = await _client.get('/auth/addresses');
      final list = res.data as List<dynamic>;
      return list.map((e) => AddressModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<AddressModel> createAddress({
    required String line1,
    String? label,
    String? line2,
    String? area,
    String? city,
    String? district,
    String? postalCode,
    // Powers the go-online location-mismatch nudge (dispatch-service's startLiveSession
    // compares a provider's live GPS against this address) — optional so a plain text
    // address without a captured pin still saves fine, just without that check.
    double? latitude,
    double? longitude,
    bool isDefault = false,
  }) async {
    try {
      final res = await _client.post('/auth/addresses', data: {
        'line1': line1,
        if (label != null) 'label': label,
        if (line2 != null) 'line2': line2,
        if (area != null) 'area': area,
        if (city != null) 'city': city,
        if (district != null) 'district': district,
        if (postalCode != null) 'postalCode': postalCode,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'isDefault': isDefault,
      });
      return AddressModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<AddressModel> updateAddress(
    String id, {
    String? label,
    String? line1,
    String? line2,
    String? area,
    String? city,
    String? district,
    String? postalCode,
    bool? isDefault,
  }) async {
    try {
      final res = await _client.patch('/auth/addresses/$id', data: {
        if (label != null) 'label': label,
        if (line1 != null) 'line1': line1,
        if (line2 != null) 'line2': line2,
        if (area != null) 'area': area,
        if (city != null) 'city': city,
        if (district != null) 'district': district,
        if (postalCode != null) 'postalCode': postalCode,
        if (isDefault != null) 'isDefault': isDefault,
      });
      return AddressModel.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> deleteAddress(String id) async {
    try {
      await _client.delete('/auth/addresses/$id');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> setDefaultAddress(String id) async {
    try {
      await _client.post('/auth/addresses/$id/set-default');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Subscription ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMySubscription() async {
    try {
      final res = await _client.get('/auth/subscriptions/me');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> subscribeToPlan(String plan) async {
    try {
      await _client.post('/auth/subscriptions', data: {'plan': plan});
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  Future<void> cancelSubscription() async {
    try {
      await _client.post('/auth/subscriptions/cancel');
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Tier ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMyTier() async {
    try {
      final res = await _client.get('/auth/tiers/me');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiClient.mapError(e);
    }
  }

  // ── Session check ─────────────────────────────────────────────────

  Future<bool> isLoggedIn() async {
    final token = await ApiClient.getAccessToken();
    return token != null;
  }
}
