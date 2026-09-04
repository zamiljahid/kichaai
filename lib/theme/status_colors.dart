import 'package:flutter/material.dart';

/// Status colours, deliberately outside the themed [ColorScheme].
///
/// These encode meaning, not brand: "pending" must stay amber and
/// "informational" must stay blue whichever seed the active role selects.
/// Routing them through the scheme would let two different statuses render in
/// the same hue after a theme switch, which is worse than a slight palette
/// mismatch.
///
/// Failure/destructive states are the exception — those use
/// `Theme.of(context).colorScheme.error`, which is a real semantic role.
class StatusColors {
  const StatusColors._();

  /// Pending / awaiting action.
  static const Color amber = Color(0xFFB27107);

  /// Informational.
  static const Color blue = Color(0xFF2563EB);

  /// Online / success.
  static const Color green = Color(0xFF22C55E);
}
