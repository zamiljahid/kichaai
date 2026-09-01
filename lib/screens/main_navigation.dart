import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../theme/app_theme.dart';
import '../theme/active_role_provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/role_switch_toggle.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'service_selection_screen.dart';
import 'orders_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'provider_dashboard_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _hasProviderProfile = false;
  bool _switchingRole = false;

  /// Mirrors ActiveRoleProvider, which owns the flag so the app-level theme can
  /// follow the role (customer → purple, provider → blue).
  bool get _isProviderMode => context.read<ActiveRoleProvider>().isProvider;

  final List<Widget> _screens = const [
    HomeScreen(),
    ServiceSelectionScreen(),
    OrdersScreen(),
    MessagesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkProviderProfile();
  }

  Future<void> _checkProviderProfile() async {
    final cachedId = await ApiClient.getProviderProfileId();
    final role = await ApiClient.getRole();
    // Provider tab shows only when login() explicitly wrote both keys.
    // Avoids /auth/me returning providerProfileId for accounts that were
    // providers in a past session or on a different device.
    final isProvider =
        (cachedId != null && cachedId.isNotEmpty) && role == 'PROVIDER';
    debugPrint(
        '[Nav] providerProfileId=$cachedId role=$role → isProvider=$isProvider');
    if (mounted) setState(() => _hasProviderProfile = isProvider);
    if (isProvider) DispatchService.instance.syncOnlineStatus();
  }

  @override
  Widget build(BuildContext context) {
    final isBn = context.watch<LanguageNotifier>().isBengali;
    final isProviderMode = context.watch<ActiveRoleProvider>().isProvider;
    return Scaffold(
      extendBody: true,
      body: AnimatedBackground(
        child: Column(
          children: [
            _buildTopBar(isBn),
            Expanded(
              child: _buildBody(isProviderMode),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isProviderMode
          ? null
          : CustomBottomNav(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
            ),
    );
  }

  Widget _buildTopBar(bool isBn) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
        child: Row(
          children: [
            if (_hasProviderProfile) ...[
              _buildRoleToggle(isBn),
              const SizedBox(width: 10),
            ],
            const Spacer(),
            const NotificationBell(),
            const SizedBox(width: 8),
            _buildLangToggle(isBn),
          ],
        ),
      ),
    );
  }

  /// ki_chai's sliding role toggle, with the provider-side online dot kept as
  /// a corner badge — going online is a provider concept, and a provider
  /// browsing the customer view still needs to see their provider side is live
  /// without switching over.
  Widget _buildRoleToggle(bool isBn) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        RoleSwitchToggle(
          isProvider: context.watch<ActiveRoleProvider>().isProvider,
          enabled: !_switchingRole,
          onTap: _toggleRole,
          customerLabel: isBn ? 'গ্রাহক' : 'Customer',
          providerLabel: isBn ? 'প্রোভাইডার' : 'Provider',
        ),
        Positioned(
          top: -1,
          right: -1,
          child: ValueListenableBuilder<bool>(
            valueListenable: DispatchService.instance.isOnlineNotifier,
            builder: (context, isOnline, __) => isOnline
                ? Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(bool isProviderMode) {
    // Cross-fade + settle between the two dashboards, matching ki_chai's shell.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(isProviderMode ? 'provider' : 'customer'),
        child: isProviderMode
            ? const ProviderDashboardScreen()
            : IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
      ),
    );
  }

  void _toggleRole() => _switchMode(!_isProviderMode);

  Future<void> _switchMode(bool toProvider) async {
    if (_isProviderMode == toProvider || _switchingRole) return;
    final role = context.read<ActiveRoleProvider>();
    role.setProviderMode(toProvider); // optimistic
    setState(() => _switchingRole = true);
    try {
      await AuthService.instance
          .switchRole(toProvider ? 'provider' : 'customer');
    } catch (e) {
      if (mounted) {
        role.setProviderMode(!toProvider); // revert
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e.toString(), style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _switchingRole = false);
    }
  }

  Widget _buildLangToggle(bool isBn) {
    return GestureDetector(
      onTap: () => context.read<LanguageNotifier>().toggle(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              isBn ? 'EN' : 'বাং',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
