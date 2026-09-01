import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Maps a catalog service `kind` to its ki_chai Lottie animation.
///
/// The keys are the app's existing `_ServiceItem.kind` / `_Service.serviceKind`
/// values — no new identifier was introduced, and nothing about how a kind is
/// resolved, dispatched or matched against the catalog changed. Two entries
/// differ from their asset name for the same reason the catalog code overrides
/// exist (`tutor` is `home_tutor`, `grocery` is `groceries_hub`).
///
/// Kinds with no animation (helping_hand, laundry, cook, commute) simply return
/// null and the caller keeps its existing image or icon.
const Map<String, String> _kServiceAnimations = {
  'technician': 'technician',
  'task_runner': 'task_runner',
  'caregiver': 'caregiver',
  'lawyer': 'lawyer',
  'photographer': 'photographer',
  'cinematographer': 'cinematographer',
  'makeup_artist': 'makeup_artist',
  'tutor': 'home_tutor',
  'pet_care': 'pet_care',
  'mess_finder': 'mess_finder',
  'scrap_collection': 'scrap_collection',
  'skill_share': 'skill_share',
  'micro_learning': 'micro_learning',
  'grocery': 'groceries_hub',
};

String? serviceAnimationAsset(String? kind) {
  if (kind == null) return null;
  final name = _kServiceAnimations[kind];
  return name == null ? null : 'assets/animations/$name.json';
}

/// ki_chai's service tile artwork: the animation on a soft circular primary
/// wash. Falls back to [fallback] for kinds that have no animation yet.
class ServiceAnimation extends StatelessWidget {
  const ServiceAnimation({
    super.key,
    required this.kind,
    required this.fallback,
    this.size = 44,
  });

  final String? kind;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = serviceAnimationAsset(kind);
    if (asset == null) return fallback;

    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: Lottie.asset(
        asset,
        fit: BoxFit.contain,
        // A still frame is a reasonable degraded state; a missing/!corrupt asset
        // must not take the whole grid down.
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
