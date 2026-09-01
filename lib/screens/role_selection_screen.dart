import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../theme/active_role_provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_button.dart';
import 'main_navigation.dart';

/// True when the signed-in account can act as BOTH customer and provider, and
/// so has a choice worth making.
///
/// Deliberately the same test `MainNavigation._checkProviderProfile` uses to
/// decide whether to show the role toggle at all: both keys must have been
/// written by login. A customer-only account, a fresh registration and a Google
/// sign-in (always CUSTOMER) all return false.
Future<bool> shouldPickRole() async {
  final providerProfileId = await ApiClient.getProviderProfileId();
  final role = await ApiClient.getRole();
  return providerProfileId != null &&
      providerProfileId.isNotEmpty &&
      role == 'PROVIDER';
}

/// Where to go once credentials are accepted: the picker for a dual-role
/// account, otherwise straight into the app as before.
Future<Widget> postLoginDestination() async =>
    await shouldPickRole() ? const RoleSelectionScreen() : const MainNavigation();

/// Lets an account that can act as both a customer and a provider choose which
/// dashboard to open, straight after signing in. Ported from ki_chai, which
/// shows the same picker as part of its sign-in flow.
///
/// Only reached when the account actually holds both roles — see
/// [shouldPickRole]. A customer-only account never sees it and goes straight
/// into [MainNavigation], exactly as before.
///
/// The choice is applied through the same path the in-app toggle already uses:
/// picking Provider calls `AuthService.switchRole('provider')`, the identical
/// call `MainNavigation._switchMode` makes. Picking Customer makes no server
/// call, because that is already the state a fresh login lands in. No new auth
/// behaviour is introduced here.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  /// Index 0 = customer, 1 = provider. Defaults to customer, which is the role
  /// the session is already in.
  int _selected = 0;
  bool _busy = false;

  Future<void> _continue() async {
    if (_busy) return;
    final toProvider = _selected == 1;
    setState(() => _busy = true);

    if (toProvider) {
      try {
        await AuthService.instance.switchRole('provider');
      } catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        final colors = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString(),
              style: TextStyle(color: colors.onInverseSurface)),
          backgroundColor: colors.error,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }
    if (!mounted) return;

    context.read<ActiveRoleProvider>().setProviderMode(toProvider);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isBn = context.watch<LanguageNotifier>().isBengali;

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                _header(colors, isBn),
                const SizedBox(height: 28),
                Text(
                  isBn
                      ? 'শুরু করতে আপনার ভূমিকা বেছে নিন'
                      : 'Pick your role to get started',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _RoleCard(
                          title: isBn ? 'গ্রাহক' : 'Customer',
                          description: isBn
                              ? 'সেবা খুঁজুন ও বুক করুন'
                              : 'Find and book services',
                          icon: Icons.person_rounded,
                          isSelected: _selected == 0,
                          onTap: () => setState(() => _selected = 0),
                        )
                            .animate()
                            .fadeIn(duration: 320.ms)
                            .slideX(begin: -0.12),
                        const SizedBox(height: 14),
                        _RoleCard(
                          title: isBn ? 'প্রোভাইডার' : 'Provider',
                          description: isBn
                              ? 'সেবা দিন এবং আয় করুন'
                              : 'Offer services and earn',
                          icon: Icons.storefront_rounded,
                          isSelected: _selected == 1,
                          onTap: () => setState(() => _selected = 1),
                        )
                            .animate(delay: 90.ms)
                            .fadeIn(duration: 320.ms)
                            .slideX(begin: 0.12),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24, top: 8),
                  child: GlassButton(
                    label: isBn ? 'চালিয়ে যান' : 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    isLoading: _busy,
                    onPressed: _continue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme colors, bool isBn) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isBn ? 'স্বাগতম' : 'Welcome to',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'কিচাই',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: colors.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.7),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 420.ms).slideY(begin: -0.15);
  }
}

/// ki_chai's role card: the fill, border, badge and icon plate all animate
/// between the selected and unselected states over 350ms easeOutCubic.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: colors.primary.withValues(alpha: 0.12),
        highlightColor: colors.primary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primaryContainer.withValues(alpha: 0.85)
                : colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? colors.primary : colors.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.22)
                    : colors.shadow.withValues(alpha: 0.06),
                blurRadius: isSelected ? 20 : 8,
                offset: Offset(0, isSelected ? 6 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.primary
                      : colors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? colors.onPrimary
                      : colors.onPrimaryContainer,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedScale(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                scale: isSelected ? 1 : 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  color: colors.primary,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
