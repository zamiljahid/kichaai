class AppException implements Exception {
  final String message;
  final String messageBn;
  final int? statusCode;

  const AppException({
    required this.message,
    required this.messageBn,
    this.statusCode,
  });

  /// Picks the right variant for the current language toggle — server-derived
  /// messages (4xx bodies) are the same text in both fields, so this is a
  /// no-op for those and only matters for the static app-level fallbacks.
  String localized(bool isBn) => isBn ? messageBn : message;

  @override
  String toString() => messageBn;
}
