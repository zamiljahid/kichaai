import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/network/api_client.dart';
import '../core/utils/app_strings.dart';
import '../services/auth_service.dart';
import '../theme/active_role_provider.dart';
import '../widgets/app_logo.dart';
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
Future<Widget> postLoginDestination() async => await shouldPickRole()
    ? const RoleSelectionScreen()
    : const MainNavigation();

/// Lets an account that can act as both a customer and a provider choose which
/// dashboard to open, straight after signing in.
///
/// The layout is ki_chai's role picker ported whole: a diagonally-clipped
/// gradient header carrying the wordmark and logo, a drifting particle field
/// over the whole canvas, two side-by-side role cards that animate in from
/// opposite edges, and a shimmering pill button that only materialises once a
/// role is picked. Card index 0 is Provider and 1 is Customer, matching the
/// original's left-to-right order.
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

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with TickerProviderStateMixin {
  /// Index 0 = provider, 1 = customer. Null until the user picks, which is what
  /// keeps the continue button hidden — ki_chai's picker opens with no default.
  int? _selectedIndex;
  bool _busy = false;

  late final AnimationController _entranceCtrl;
  late final AnimationController _particleCtrl;
  late final AnimationController _btnCtrl;
  late final Animation<double> _card0Fade;
  late final Animation<Offset> _card0Slide;
  late final Animation<double> _card1Fade;
  late final Animation<Offset> _card1Slide;
  late final Animation<double> _btnScale;
  late final Animation<double> _btnFade;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _btnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _card0Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
      ),
    );
    _card0Slide =
        Tween<Offset>(begin: const Offset(-0.35, 0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.45, 0.75, curve: Curves.easeOutCubic),
      ),
    );
    _card1Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.55, 0.85, curve: Curves.easeOut),
      ),
    );
    _card1Slide =
        Tween<Offset>(begin: const Offset(0.35, 0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.55, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _btnScale = Tween<double>(begin: 0.85, end: 1)
        .animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.elasticOut));
    _btnFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeIn));

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _particleCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  /// Flips the active role straight away so the whole screen previews the
  /// choice — blue for provider, purple for customer — exactly as ki_chai does.
  /// This is presentation state only; the server is not touched until Continue.
  void _selectRole(int index) {
    if (_busy) return;
    setState(() => _selectedIndex = index);
    context.read<ActiveRoleProvider>().setProviderMode(index == 0);
    _btnCtrl
      ..reset()
      ..forward();
  }

  Future<void> _continue() async {
    if (_busy || _selectedIndex == null) return;
    final toProvider = _selectedIndex == 0;
    setState(() => _busy = true);

    if (toProvider) {
      try {
        await AuthService.instance.switchRole('provider');
      } catch (e) {
        if (!mounted) return;
        // Undo the optimistic preview so the theme matches the real session.
        context.read<ActiveRoleProvider>().setProviderMode(false);
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
    final size = MediaQuery.sizeOf(context);
    final isBn = context.watch<LanguageNotifier>().isBengali;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _particleCtrl,
            builder: (_, __) => CustomPaint(
              size: size,
              painter: _ParticlePainter(_particleCtrl.value, colors),
            ),
          ),
          _buildHeader(size, colors),
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: size.height * 0.40,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
                child: Row(
                  children: [
                    Expanded(child: _buildWordmark(colors, isBn)),
                    const AppLogo(size: 120),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: size.height * 0.38),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 20),
                    child: Text(
                      isBn
                          ? 'শুরু করতে আপনার ভূমিকা বেছে নিন'
                          : 'Pick your role to get started',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // IntrinsicHeight so the two cards match height even when one
                  // role's checklist wraps to more lines than the other's.
                  // `stretch` alone cannot do it here: this Row sits inside a
                  // SingleChildScrollView, where the vertical extent is
                  // unbounded, and stretching into an unbounded axis asserts.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SlideTransition(
                            position: _card0Slide,
                            child: FadeTransition(
                              opacity: _card0Fade,
                              child: _RoleCard(
                                title: isBn ? 'প্রোভাইডার' : 'Provider',
                                description: isBn
                                    ? 'সেবা দিন\nএবং আয় করুন'
                                    : 'Offer services\nand earn',
                                icon: Icons.storefront_rounded,
                                isSelected: _selectedIndex == 0,
                                roleColor: colors.primary,
                                roleOnColor: colors.onPrimary,
                                roleContainerColor: colors.primaryContainer,
                                roleOnContainerColor: colors.onPrimaryContainer,
                                badge: isBn ? 'আয়' : 'Earn',
                                features: isBn
                                    ? const [
                                        'সেবা তালিকাভুক্ত করুন',
                                        'অর্ডার সামলান',
                                        'পেমেন্ট নিন'
                                      ]
                                    : const [
                                        'List services',
                                        'Manage orders',
                                        'Get paid'
                                      ],
                                onTap: () => _selectRole(0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SlideTransition(
                            position: _card1Slide,
                            child: FadeTransition(
                              opacity: _card1Fade,
                              child: _RoleCard(
                                title: isBn ? 'গ্রাহক' : 'Customer',
                                description: isBn
                                    ? 'সেবা খুঁজুন\nও বুক করুন'
                                    : 'Discover and\nbuy services',
                                icon: Icons.person_search_rounded,
                                isSelected: _selectedIndex == 1,
                                roleColor: colors.secondary,
                                roleOnColor: colors.onSecondary,
                                roleContainerColor: colors.secondaryContainer,
                                roleOnContainerColor:
                                    colors.onSecondaryContainer,
                                badge: isBn ? 'ঘুরে দেখুন' : 'Explore',
                                features: isBn
                                    ? const [
                                        'অফার দেখুন',
                                        'সহজ বুকিং',
                                        'অর্ডার ট্র্যাক'
                                      ]
                                    : const [
                                        'Browse offers',
                                        'Easy booking',
                                        'Track orders'
                                      ],
                                onTap: () => _selectRole(1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: _selectedIndex == null
                        ? const SizedBox(width: double.infinity)
                        : ScaleTransition(
                            scale: _btnScale,
                            child: FadeTransition(
                              opacity: _btnFade,
                              child: _ContinueButton(
                                label: _selectedIndex == 0
                                    ? (isBn
                                        ? 'প্রোভাইডার হিসেবে চালিয়ে যান'
                                        : 'Continue as Provider')
                                    : (isBn
                                        ? 'গ্রাহক হিসেবে চালিয়ে যান'
                                        : 'Continue as Customer'),
                                isPrimary: _selectedIndex == 0,
                                isLoading: _busy,
                                onTap: _continue,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordmark(ColorScheme colors, bool isBn) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          isBn ? 'কিচাই' : 'Ki\nChaai',
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 38,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  /// The diagonally-clipped gradient plate behind the wordmark, with two
  /// oversized rings bleeding off opposite corners.
  Widget _buildHeader(Size size, ColorScheme colors) {
    return ClipPath(
      clipper: _DiagonalClipper(),
      child: Container(
        width: double.infinity,
        height: size.height * 0.40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.inversePrimary, colors.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -40,
              child: _Ring(
                color: colors.primary.withValues(alpha: 0.15),
                size: 180,
                strokeWidth: 30,
              ),
            ),
            Positioned(
              bottom: 20,
              left: -30,
              child: _Ring(
                color: colors.primary.withValues(alpha: 0.08),
                size: 120,
                strokeWidth: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header decoration ────────────────────────────────────────────────────────

class _Ring extends StatelessWidget {
  const _Ring({
    required this.color,
    required this.size,
    required this.strokeWidth,
  });

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _RingPainter(color: color, strokeWidth: strokeWidth),
      );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - strokeWidth / 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// Slices 36px off the bottom-left corner so the header plate reads as a
/// diagonal band rather than a rectangle.
class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(0, size.height - 36)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width, 0)
    ..close();

  @override
  bool shouldReclip(_DiagonalClipper old) => false;
}

// ── Role card ────────────────────────────────────────────────────────────────

/// ki_chai's role card: badge, icon plate, title, blurb, a checklist of what the
/// role gets, and a radio row — fill, border and every plate animating between
/// the selected and unselected states over 300–350ms.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.roleColor,
    required this.roleOnColor,
    required this.roleContainerColor,
    required this.roleOnContainerColor,
    required this.badge,
    required this.features,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isSelected;
  final Color roleColor;
  final Color roleOnColor;
  final Color roleContainerColor;
  final Color roleOnContainerColor;
  final String badge;
  final List<String> features;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        splashColor: roleColor.withValues(alpha: 0.12),
        highlightColor: roleColor.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected
                ? roleContainerColor.withValues(alpha: 0.85)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isSelected ? roleColor : colors.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? roleColor.withValues(alpha: 0.22)
                    : colors.shadow.withValues(alpha: 0.10),
                blurRadius: isSelected ? 20 : 8,
                offset: Offset(0, isSelected ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? roleColor
                      : colors.outlineVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: isSelected
                        ? roleOnColor
                        : colors.onSurface.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isSelected
                      ? roleColor
                      : roleContainerColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? roleOnColor : roleOnContainerColor,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? roleOnContainerColor : colors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: isSelected
                      ? roleOnContainerColor.withValues(alpha: 0.75)
                      : colors.onSurface.withValues(alpha: 0.55),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: isSelected ? roleColor : colors.outline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? roleOnContainerColor.withValues(alpha: 0.85)
                                : colors.onSurface.withValues(alpha: 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    width: isSelected ? 22 : 20,
                    height: isSelected ? 22 : 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? roleColor : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? roleColor : colors.outline,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check_rounded,
                            size: 13, color: roleOnColor)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        color: isSelected ? roleColor : colors.outline,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      child: Text(
                        isSelected ? 'Selected' : 'Select',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Continue button ──────────────────────────────────────────────────────────

/// A pill whose fill is a highlight band sweeping left to right on a 2s loop.
class _ContinueButton extends StatefulWidget {
  const _ContinueButton({
    required this.label,
    required this.isPrimary,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final bool isPrimary;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseColor = widget.isPrimary ? colors.primary : colors.secondary;
    final onColor = widget.isPrimary ? colors.onPrimary : colors.onSecondary;

    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isLoading ? null : widget.onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              gradient: LinearGradient(
                begin: Alignment(-1.5 + 3 * _shimmerCtrl.value, 0),
                end: Alignment(0.5 + 3 * _shimmerCtrl.value, 0),
                colors: [
                  baseColor,
                  baseColor.withValues(alpha: 0.75),
                  baseColor,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: baseColor.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: widget.isLoading
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(onColor),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded,
                          color: onColor, size: 20),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Particle field ───────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.progress, this.colors);

  final double progress;
  final ColorScheme colors;

  static final _particles = List.generate(24, (i) {
    final rng = math.Random(i * 17 + 5);
    return _P(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      speed: 0.025 + rng.nextDouble() * 0.045,
      radius: 1.2 + rng.nextDouble() * 2.2,
      phase: rng.nextDouble(),
      opacity: 0.04 + rng.nextDouble() * 0.1,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress + p.phase) % 1.0;
      final y = (p.y - t * p.speed) % 1.0;
      final wobble = math.sin(t * math.pi * 2 + p.phase * 6) * 0.02;
      canvas.drawCircle(
        Offset((p.x + wobble) * size.width, y * size.height),
        p.radius,
        Paint()..color = colors.primary.withValues(alpha: p.opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.progress != progress || old.colors != colors;
}

class _P {
  const _P({
    required this.x,
    required this.y,
    required this.speed,
    required this.radius,
    required this.phase,
    required this.opacity,
  });

  final double x, y, speed, radius, phase, opacity;
}
