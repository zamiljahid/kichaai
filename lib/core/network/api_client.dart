import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_exception.dart';

class ApiClient {
  static const _baseUrl = 'https://api-gateway-production-8025.up.railway.app/api/v1';
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _fullNameKey = 'full_name';
  static const _emailKey = 'user_email';
  static const _phoneKey = 'user_phone';
  static const _roleKey = 'user_role';
  static const _providerProfileIdKey = 'provider_profile_id';
  static const _onboardingSeenKey = 'onboarding_seen';

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;

  /// Tracks session state so app-wide chrome (e.g. the floating AI chat button)
  /// can show/hide itself without every screen re-checking SharedPreferences.
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);

  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));

    _dio.interceptors.add(_AuthInterceptor(_dio));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint('[API] $obj'),
      ));
    }
  }

  Dio get dio => _dio;

  // ── Token helpers ────────────────────────────────────────────────

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
    String? fullName,
    String? email,
    String? phone,
    String? role,
    String? providerProfileId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    if (userId != null) await prefs.setString(_userIdKey, userId);
    if (fullName != null) await prefs.setString(_fullNameKey, fullName);
    if (email != null) await prefs.setString(_emailKey, email);
    if (phone != null) await prefs.setString(_phoneKey, phone);
    if (role != null) await prefs.setString(_roleKey, role);
    // Explicitly remove when null so a stale provider session never bleeds into a customer login.
    if (providerProfileId != null && providerProfileId.isNotEmpty) {
      await prefs.setString(_providerProfileIdKey, providerProfileId);
    } else {
      await prefs.remove(_providerProfileIdKey);
    }
    isLoggedIn.value = true;
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Replace only the access token (e.g. after a role switch reissues the JWT),
  /// leaving refresh token, role and providerProfileId untouched.
  static Future<void> setAccessToken(String accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, accessToken);
  }

  /// Whether the intro carousel has been shown once. After that, a logged-out
  /// user goes straight to the login screen instead of re-watching the intro.
  static Future<bool> getOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingSeenKey) ?? false;
  }

  static Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  static Future<String?> getFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fullNameKey);
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  static Future<String?> getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  static Future<String?> getProviderProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_providerProfileIdKey);
  }

  static Future<void> updateProviderProfileId(String? providerProfileId) async {
    final prefs = await SharedPreferences.getInstance();
    if (providerProfileId != null && providerProfileId.isNotEmpty) {
      await prefs.setString(_providerProfileIdKey, providerProfileId);
    } else {
      await prefs.remove(_providerProfileIdKey);
    }
  }

  static Future<void> setAsProvider(String providerProfileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerProfileIdKey, providerProfileId);
    await prefs.setString(_roleKey, 'PROVIDER');
  }

  static Future<void> clearProviderCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_providerProfileIdKey);
    await prefs.remove('providerServiceType');
    await prefs.remove('providerServiceId');
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_fullNameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_providerProfileIdKey);
    await prefs.remove('providerServiceType');
    await prefs.remove('providerServiceId');
    isLoggedIn.value = false;
  }

  // ── Error mapper ─────────────────────────────────────────────────

  static AppException mapError(dynamic error) {
    if (error is AppException) return error;

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const AppException(
            message: 'Request timed out',
            messageBn: 'সার্ভার সাড়া দিচ্ছে না। দয়া করে পরে চেষ্টা করুন।',
            statusCode: 408,
          );
        case DioExceptionType.connectionError:
          return const AppException(
            message: 'No internet connection',
            messageBn: 'ইন্টারনেট সংযোগ নেই। দয়া করে আবার চেষ্টা করুন।',
            statusCode: 0,
          );
        case DioExceptionType.badResponse:
          return _mapHttpStatus(error.response?.statusCode, error.response?.data);
        default:
          return const AppException(
            message: 'Unexpected error',
            messageBn: 'একটি অপ্রত্যাশিত সমস্যা হয়েছে।',
          );
      }
    }

    return const AppException(
      message: 'Unknown error',
      messageBn: 'একটি অজানা সমস্যা হয়েছে।',
    );
  }

  static AppException _mapHttpStatus(int? code, dynamic data) {
    final serverMsg = data is Map ? (data['message'] ?? '') : '';
    switch (code) {
      case 400:
        return AppException(
          message: serverMsg.toString(),
          messageBn: serverMsg.isNotEmpty ? serverMsg.toString() : 'অনুরোধে সমস্যা আছে।',
          statusCode: 400,
        );
      case 401:
        // Not every 401 is an expired session. Signing in with the wrong password also returns
        // 401, and telling someone standing ON the login screen that their "session expired"
        // explains nothing and hides the one thing they need to know. Translate the causes the
        // backend actually distinguishes; fall back to the session message only for the token
        // failures, which is what it was always meant for.
        final auth401 = serverMsg.toString();
        if (auth401.contains('Invalid credentials')) {
          return const AppException(
            message: 'Wrong email/phone or password',
            messageBn: 'ইমেইল/ফোন নম্বর বা পাসওয়ার্ড ভুল।',
            statusCode: 401,
          );
        }
        if (auth401.contains('Account not found') || auth401.contains('User not found')) {
          return const AppException(
            message: 'No account found with these details',
            messageBn: 'এই ইমেইল বা ফোন নম্বরে কোনো অ্যাকাউন্ট নেই।',
            statusCode: 401,
          );
        }
        if (auth401.contains('Account suspended') || auth401.contains('Account not accessible')) {
          return const AppException(
            message: 'This account has been suspended',
            messageBn: 'আপনার অ্যাকাউন্টটি স্থগিত করা হয়েছে। সহায়তার জন্য যোগাযোগ করুন।',
            statusCode: 401,
          );
        }
        if (auth401.contains('Google token')) {
          return const AppException(
            message: 'Google sign-in failed — try again',
            messageBn: 'Google দিয়ে লগইন করা যায়নি। আবার চেষ্টা করুন।',
            statusCode: 401,
          );
        }
        return const AppException(
          message: 'Unauthorized',
          messageBn: 'সেশন মেয়াদ শেষ হয়েছে। আবার লগইন করুন।',
          statusCode: 401,
        );
      case 403:
        // Server messages here are often actionable (e.g. "NID verification required before
        // responding to requests") — a blanket "not allowed" would hide exactly the info the
        // user needs to unblock themselves.
        return AppException(
          message: serverMsg.toString().isNotEmpty ? serverMsg.toString() : 'Forbidden',
          messageBn: serverMsg.isNotEmpty ? serverMsg.toString() : 'আপনার এই কাজের অনুমতি নেই।',
          statusCode: 403,
        );
      case 404:
        return const AppException(
          message: 'Not found',
          messageBn: 'তথ্য পাওয়া যায়নি।',
          statusCode: 404,
        );
      case 409:
        return AppException(
          message: serverMsg.toString(),
          messageBn: serverMsg.isNotEmpty ? serverMsg.toString() : 'এই তথ্য ইতিমধ্যে বিদ্যমান।',
          statusCode: 409,
        );
      case 422:
        return AppException(
          message: serverMsg.toString(),
          messageBn: serverMsg.isNotEmpty ? serverMsg.toString() : 'তথ্য যাচাই ব্যর্থ হয়েছে।',
          statusCode: 422,
        );
      case 500:
      case 502:
      case 503:
        return const AppException(
          message: 'Server error',
          messageBn: 'সার্ভারে সমস্যা হয়েছে। দয়া করে পরে চেষ্টা করুন।',
          statusCode: 500,
        );
      default:
        return AppException(
          message: 'HTTP error $code',
          messageBn: 'একটি সমস্যা হয়েছে (কোড: $code)।',
          statusCode: code,
        );
    }
  }
}

// ── Auth interceptor ──────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  // Shared by ALL concurrent 401s, not just the first. Previously `_isRefreshing` (a bool
  // guard) made every 401 EXCEPT the first one skip straight to propagating the stale error
  // instead of waiting for the in-flight refresh — so a burst of parallel calls right after
  // token expiry (e.g. a screen that fires several loads in initState, or two screens loading
  // at once) had exactly one request survive and the rest fail with an unrecovered 401, even
  // though the session was perfectly valid and got refreshed a moment later for the next call.
  Future<String?>? _refreshFuture;

  _AuthInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await ApiClient.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Never try to "refresh the refresh" — an expired/invalid refresh token 401ing here would
    // otherwise recurse forever through this same handler.
    //
    // The same applies to every other auth entry point: their 401 means "those credentials are
    // wrong", not "your token went stale". Refreshing there burned a pointless round-trip on
    // each failed login and, worse, could wipe the stored tokens of whoever was already signed
    // in just because someone mistyped a password on the login screen.
    if (err.response?.statusCode != 401 || _isAuthEntryPoint(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    _refreshFuture ??= _refreshTokens();
    final newAccess = await _refreshFuture;
    _refreshFuture = null;

    if (newAccess == null) {
      handler.next(err);
      return;
    }

    try {
      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final retryResponse = await _dio.fetch(err.requestOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      handler.next(err);
    }
  }

  /// Paths where a 401 is a legitimate result rather than a signal to re-authenticate.
  static bool _isAuthEntryPoint(String path) =>
      path.contains('/auth/refresh') ||
      path.contains('/auth/login') ||
      path.contains('/auth/signup') ||
      path.contains('/auth/google') ||
      path.contains('/auth/verify-otp') ||
      path.contains('/auth/forgot-password') ||
      path.contains('/auth/reset-password');

  Future<String?> _refreshTokens() async {
    try {
      final refreshToken = await ApiClient.getRefreshToken();
      if (refreshToken == null) {
        await ApiClient.clearTokens();
        return null;
      }
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(headers: {'Authorization': null}),
      );
      final newAccess = response.data['accessToken'] as String?;
      final newRefresh = response.data['refreshToken'] as String?;
      if (newAccess == null || newRefresh == null) return null;
      await ApiClient.saveTokens(accessToken: newAccess, refreshToken: newRefresh);
      return newAccess;
    } catch (_) {
      await ApiClient.clearTokens();
      return null;
    }
  }
}
