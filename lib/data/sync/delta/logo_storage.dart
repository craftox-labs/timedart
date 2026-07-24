import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/sync/delta/supabase_init.dart';

// Delta-sync (#320) — logo replication over Supabase Storage. The profile logo
// is a BLOB that can't ride a text/int delta row, so the bytes live in a private
// Storage bucket (`logos`) keyed by org, and the profile row carries only the
// object [logoObjectPath]. The local BLOB stays source-of-truth; Storage is the
// shared replica (fetch-on-miss on other devices).

/// The Storage bucket name (create it in the Supabase dashboard — see
/// supabase/schema/delta-sync-branding.sql).
const String kLogoBucket = 'logos';

/// The deterministic object path for a logo: `<orgId>/<profileId>-<hash>.<ext>`.
///
/// - The **first segment is the org** — Storage RLS gates every op on membership
///   of that folder (`storage.foldername(name)[1]`).
/// - The path embeds a content **hash of the bytes**, so swapping the logo
///   yields a NEW path → the row's `logo_path` changes → other devices see it
///   change and re-download (cache-busting without a version column).
/// - Upload is idempotent: identical bytes → identical path → a no-op upsert.
///
/// Pure (no I/O) so a device can recompute the expected path for its LOCAL bytes
/// and compare it to a pulled `logo_path` to decide whether its copy is stale.
String logoObjectPath(
  String orgId,
  String profileId,
  Uint8List bytes,
  String? mime,
) {
  final hash = _fnv1a64Hex(bytes);
  return '$orgId/$profileId-$hash.${_extForMime(mime)}';
}

String _extForMime(String? mime) {
  switch (mime) {
    case 'image/png':
      return 'png';
    case 'image/jpeg':
    case 'image/jpg':
      return 'jpg';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    default:
      return 'bin';
  }
}

/// FNV-1a 64-bit over the bytes, as exactly 16 lowercase hex chars.
/// Deterministic and content-addressed — good enough for cache-busting (not a
/// security hash). The multiply relies on native two's-complement 64-bit
/// wraparound (the app's synced platforms are all 64-bit native); the result is
/// emitted UNSIGNED via two 32-bit halves so a negative accumulator can't leak a
/// leading '-' into the object path.
String _fnv1a64Hex(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final b in bytes) {
    hash ^= b;
    hash = hash * prime; // wraps at 64 bits on native
  }
  final hi = (hash >> 32) & 0xFFFFFFFF;
  final lo = hash & 0xFFFFFFFF;
  return hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');
}

/// Thin wrapper over the `logos` bucket. Injectable [client] for tests.
class LogoStorage {
  LogoStorage({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// Upload [bytes] to [path] (idempotent upsert). Returns [path].
  Future<String> upload(String path, Uint8List bytes, String? mime) async {
    await _client.storage.from(kLogoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: mime ?? 'application/octet-stream',
          ),
        );
    return path;
  }

  /// Download the bytes at [path].
  Future<Uint8List> download(String path) =>
      _client.storage.from(kLogoBucket).download(path);
}
