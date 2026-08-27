import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../services/dispatch_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/custom_bottom_nav.dart';
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
  bool _isProviderMode = false;
  bool _switchingRole = false;

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
    return Scaffold(
      extendBody: true,
      body: AnimatedBackground(
        child: Column(
          children: [
            _buildTopBar(isBn),
            Expanded(
              child: _isProviderMode
                  ? const ProviderDashboardScreen()
                  : IndexedStack(
                      index: _currentIndex,
                      children: _screens,
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isProviderMode
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
              Expanded(child: _buildModeTogglePill()),
              const SizedBox(width: 10),
            ] else
              const Spacer(),
            const NotificationBell(),
            const SizedBox(width: 8),
            _buildLangToggle(isBn),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTogglePill() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          _modeTab('গ্রাহক', isProvider: false),
          _modeTab('প্রোভাইডার', isProvider: true),
        ],
      ),
    );
  }

  Future<void> _switchMode(bool toProvider) async {
    if (_isProviderMode == toProvider || _switchingRole) return;
    setState(() {
      _isProviderMode = toProvider;
      _switchingRole = true;
    }); // optimistic
    try {
      await AuthService.instance
          .switchRole(toProvider ? 'provider' : 'customer');
    } catch (e) {
      if (mounted) {
        setState(() => _isProviderMode = !toProvider); // revert
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

  Widget _modeTab(String label, {required bool isProvider}) {
    final isSelected = _isProviderMode == isProvider;
    // Only the প্রোভাইডার tab ever needs the online dot — going online is a provider-side
    // concept. Lets a provider browsing the customer tab see at a glance that their provider
    // side is still live, without switching over.
    final showOnlineDot = isProvider;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(isProvider),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.blueGradient : null,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showOnlineDot)
                  ValueListenableBuilder<bool>(
                    valueListenable: DispatchService.instance.isOnlineNotifier,
                    builder: (_, isOnline, __) => isOnline
                        ? Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4ADE80),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
