import 'dart:convert';

String? decodeJwtSub(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = base64Url.normalize(parts[1]);
    final data = jsonDecode(utf8.decode(base64Url.decode(payload))) as Map<String, dynamic>;
    return data['sub'] as String?;
  } catch (_) {
    return null;
  }
}
