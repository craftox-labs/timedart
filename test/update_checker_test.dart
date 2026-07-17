import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timedart/features/updates/update_checker.dart';

// Coverage for the update check (Phase 1): tag comparison, JSON parsing, and
// the check() status logic against a mocked GitHub Releases response.

String _releaseJson({
  String tag = 'v0.9.0-beta.8',
  String name = 'v0.9.0-beta.8',
  String body = 'Notes here',
}) => jsonEncode({
  'tag_name': tag,
  'name': name,
  'body': body,
  'html_url': 'https://github.com/craftox-labs/timedart/releases/tag/$tag',
});

UpdateChecker _checker(
  String currentTag, {
  int status = 200,
  String? body,
}) => UpdateChecker(
  currentTag: currentTag,
  client: MockClient((_) async => http.Response(body ?? _releaseJson(), status)),
);

void main() {
  group('isNewerTag', () {
    test('higher beta number is newer', () {
      expect(isNewerTag('v0.9.0-beta.8', 'v0.9.0-beta.7'), isTrue);
      expect(isNewerTag('v0.9.0-beta.7', 'v0.9.0-beta.8'), isFalse);
    });
    test('equal tags are not newer', () {
      expect(isNewerTag('v0.9.0-beta.7', 'v0.9.0-beta.7'), isFalse);
    });
    test('full release outranks a pre-release of the same core', () {
      expect(isNewerTag('v0.9.0', 'v0.9.0-beta.9'), isTrue);
      expect(isNewerTag('v0.9.0-beta.9', 'v0.9.0'), isFalse);
    });
    test('core version dominates the pre-release suffix', () {
      expect(isNewerTag('v0.10.0-beta.1', 'v0.9.0-beta.9'), isTrue);
      expect(isNewerTag('v1.0.0', 'v0.9.0'), isTrue);
      expect(isNewerTag('v0.9.1', 'v0.9.0-beta.1'), isTrue);
    });
    test('unparseable tags are handled conservatively', () {
      expect(isNewerTag('garbage', 'v0.9.0-beta.7'), isFalse);
      expect(isNewerTag('v0.9.0-beta.8', 'garbage'), isTrue);
    });
  });

  group('parseRelease', () {
    test('reads tag, notes, url; names falls back to tag', () {
      final r = parseRelease(_releaseJson(name: ''));
      expect(r.tag, 'v0.9.0-beta.8');
      expect(r.name, 'v0.9.0-beta.8'); // empty name → tag
      expect(r.notes, 'Notes here');
      expect(r.url, contains('/releases/tag/'));
    });
  });

  group('check', () {
    test('reports UpdateAvailable when the remote tag is newer', () async {
      final status = await _checker('v0.9.0-beta.7').check();
      expect(status, isA<UpdateAvailable>());
      expect((status as UpdateAvailable).release.tag, 'v0.9.0-beta.8');
    });

    test('reports UpToDate when running the latest', () async {
      expect(await _checker('v0.9.0-beta.8').check(), isA<UpToDate>());
    });

    test('reports DevBuild when no release tag is baked in', () async {
      final status = await _checker('').check();
      expect(status, isA<DevBuild>());
      expect((status as DevBuild).latest?.tag, 'v0.9.0-beta.8');
    });

    test('reports CheckFailed on a non-200 response', () async {
      final status = await _checker('v0.9.0-beta.7', status: 403).check();
      expect(status, isA<CheckFailed>());
    });
  });
}
