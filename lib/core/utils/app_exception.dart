class AppException implements Exception {
  final String message;
  final String messageBn;
  final int? statusCode;

  const AppException({
    required this.message,
    required this.messageBn,
    this.statusCode,
  });

  @override
  String toString() => messageBn;
}
