import 'package:flutter/material.dart';

enum UserRole { customer, provider }

/// Which dashboard the user is currently *looking at*, lifted out of
/// `MainNavigation`'s local state so `MaterialApp.theme` can be derived from it.
///
/// This is presentation state only. It deliberately does NOT persist anything
/// and does NOT decide whether the account may act as a provider — that stays
/// with `AuthService.switchRole()` and the `role` / `providerProfileId` keys
/// `ApiClient` already owns. `MainNavigation` still calls those exactly as
/// before and only mirrors the resulting view mode here.
class ActiveRoleProvider with ChangeNotifier {
  UserRole _activeRole = UserRole.customer;

  UserRole get activeRole => _activeRole;
  bool get isCustomer => _activeRole == UserRole.customer;
  bool get isProvider => _activeRole == UserRole.provider;

  /// Mirrors the view mode. No-op when unchanged so an optimistic set followed
  /// by a revert doesn't emit two identical notifications.
  void setRole(UserRole role) {
    if (_activeRole == role) return;
    _activeRole = role;
    notifyListeners();
  }

  void setProviderMode(bool isProvider) =>
      setRole(isProvider ? UserRole.provider : UserRole.customer);

  /// Role-based accent color. The overall app theme already switches with the
  /// role (blue for provider, purple for customer), so the accent simply
  /// follows the active theme's primary color.
  Color getThemeColor(ColorScheme baseColors) => baseColors.primary;

  Color getThemeColorLight(ColorScheme baseColors) =>
      baseColors.primaryContainer;
}
