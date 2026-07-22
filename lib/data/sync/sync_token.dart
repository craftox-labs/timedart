import 'dart:convert';

/// Decode (WITHOUT verifying — trial only) the `sub` claim of a JWT.
///
/// The personal `org_id` for the trial is the sync token's subject: the same
/// value the `upload-data` Edge Function derives server-side, and the value the
/// PowerSync sync rules scope each bucket to (`org_id = auth.user_id()`).
/// Deriving the client-side seed `org_id` from the very same token guarantees
/// the seeded rows match the scope they'll sync under. Returns null if the token
/// is empty/malformed or carries no non-empty `sub`.
String? tokenSubject(String jwt) {
  final parts = jwt.split('.');
  if (parts.length < 2) return null;
  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    switch (payload.length % 4) {
      case 2:
        payload += '==';
      case 3:
        payload += '=';
    }
    final claims = jsonDecode(utf8.decode(base64.decode(payload)));
    final sub = claims is Map ? claims['sub'] : null;
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}
