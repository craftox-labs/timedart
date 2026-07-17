import 'dart:convert';

import 'package:http/http.dart' as http;

/// The release tag this build was produced from, injected by CI at build time
/// (`flutter build … --dart-define=RELEASE_TAG=v0.9.0-beta.8`). Empty for local
/// and development builds, which the checker treats as [DevBuild].
const String kReleaseTag = String.fromEnvironment('RELEASE_TAG');

/// A published release, as read from the GitHub Releases API.
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.name,
    required this.notes,
    required this.url,
  });

  /// The git tag, e.g. `v0.9.0-beta.8`.
  final String tag;

  /// The release title (falls back to the tag when unnamed).
  final String name;

  /// The release body — GitHub-flavoured markdown.
  final String notes;

  /// The release page (`html_url`) to open in a browser.
  final String url;
}

/// The result of an update check. A sealed hierarchy so the UI switches over it
/// exhaustively.
sealed class UpdateStatus {
  const UpdateStatus();
}

/// The running build is the latest published release.
class UpToDate extends UpdateStatus {
  const UpToDate();
}

/// A newer release than the running build is available.
class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable(this.release);
  final AppRelease release;
}

/// A local/dev build with no baked-in [kReleaseTag]; [latest] is the newest
/// published release for reference (never framed as an "update").
class DevBuild extends UpdateStatus {
  const DevBuild(this.latest);
  final AppRelease? latest;
}

/// The check could not complete (offline, rate-limited, bad response, …).
class CheckFailed extends UpdateStatus {
  const CheckFailed(this.reason);
  final String reason;
}

/// Checks GitHub Releases for a newer build. Pure of any UI; the HTTP client is
/// injectable so the logic is unit-testable with a mock.
class UpdateChecker {
  UpdateChecker({
    http.Client? client,
    this.currentTag = kReleaseTag,
    this.repo = 'craftox-labs/timedart',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String currentTag;
  final String repo;

  Future<UpdateStatus> check() async {
    try {
      final res = await _client
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return CheckFailed('GitHub returned HTTP ${res.statusCode}');
      }
      final release = parseRelease(res.body);
      if (currentTag.isEmpty) return DevBuild(release);
      return isNewerTag(release.tag, currentTag)
          ? UpdateAvailable(release)
          : const UpToDate();
    } catch (e) {
      return CheckFailed('$e');
    }
  }
}

/// Parse a GitHub "latest release" JSON payload into an [AppRelease].
AppRelease parseRelease(String jsonBody) {
  final m = jsonDecode(jsonBody) as Map<String, dynamic>;
  final tag = (m['tag_name'] as String?) ?? '';
  final name = (m['name'] as String?)?.trim();
  return AppRelease(
    tag: tag,
    name: (name != null && name.isNotEmpty) ? name : tag,
    notes: (m['body'] as String?) ?? '',
    url: (m['html_url'] as String?) ?? '',
  );
}

/// Whether [remote] is a strictly newer release tag than [local]. Tags look
/// like `vMAJOR.MINOR.PATCH` with an optional `-beta.N` suffix; per semver a
/// full release outranks a pre-release of the same core version, and higher
/// beta numbers outrank lower ones. Unparseable tags are treated
/// conservatively (a bad remote is never "newer").
bool isNewerTag(String remote, String local) {
  final r = _parseTag(remote);
  final l = _parseTag(local);
  if (r == null) return false;
  if (l == null) return true;
  for (var i = 0; i < 3; i++) {
    if (r.core[i] != l.core[i]) return r.core[i] > l.core[i];
  }
  // Same core version: a full release beats a pre-release; otherwise compare
  // beta numbers.
  if (r.pre == null && l.pre == null) return false;
  if (r.pre == null) return true; // remote is the full release
  if (l.pre == null) return false; // local is already the full release
  return r.pre! > l.pre!;
}

class _Tag {
  const _Tag(this.core, this.pre);
  final List<int> core; // [major, minor, patch]
  final int? pre; // beta number, or null for a full release
}

_Tag? _parseTag(String tag) {
  final m = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$',
  ).firstMatch(tag.trim());
  if (m == null) return null;
  return _Tag(
    [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)],
    m[4] == null ? null : int.parse(m[4]!),
  );
}
