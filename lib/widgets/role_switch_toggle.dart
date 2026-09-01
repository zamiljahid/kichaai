import 'package:flutter/material.dart';

/// Animated role-switch toggle. Ported from ki_chai.
///
/// The white thumb carries the current role initial (`C` for customer, `P`
/// for provider) and slides left → right when the role changes, while the
/// label cross-fades between the two role names.
///
/// One adaptation from the original: ki_chai renders this inside a
/// primary-coloured app bar, so its track is `white @ 18%` and it relies on the
/// app bar behind it for contrast. This app has no app bar here — the toggle
/// sits on the light canvas — so the track paints `colors.primary` itself. The
/// white thumb / white label relationship is unchanged; only what supplies the
/// coloured field moved from the app bar into the pill.
class RoleSwitchToggle extends StatelessWidget {
  const RoleSwitchToggle({
    super.key,
    required this.isProvider,
    required this.onTap,
    required this.customerLabel,
    required this.providerLabel,
    this.customerInitial = 'C',
    this.providerInitial = 'P',
    this.enabled = true,
  });

  final bool isProvider;
  final VoidCallback onTap;

  /// Supplied by the caller so the labels stay inside the app's existing
  /// bn/en string layer rather than being hardcoded here.
  final String customerLabel;
  final String providerLabel;
  final String customerInitial;
  final String providerInitial;

  /// False while a switch is in flight, so a second tap can't race the first.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const duration = Duration(milliseconds: 320);
    const curve = Curves.easeOutCubic;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        height: 34,
        width: 138,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: enabled ? 1.0 : 0.6),
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Label sits on the opposite side of the thumb.
            AnimatedAlign(
              duration: duration,
              curve: curve,
              alignment:
                  isProvider ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AnimatedSwitcher(
                  duration: duration,
                  child: Text(
                    isProvider ? providerLabel : customerLabel,
                    key: ValueKey(isProvider),
                    style: TextStyle(
                      color: colors.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            // Sliding thumb with the role initial.
            AnimatedAlign(
              duration: duration,
              curve: curve,
              alignment:
                  isProvider ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: colors.onPrimary,
                  child: AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Text(
                      isProvider ? providerInitial : customerInitial,
                      key: ValueKey(isProvider),
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
