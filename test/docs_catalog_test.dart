import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/docs/docs_catalog.dart';

// The docs catalogue is the heart of the in-app docs slice (#252): frontmatter
// parsing, the grouping/ordering rules, page lookup, and prev/next navigation.
// It's pure, so the whole contract is pinned here from in-memory strings — no
// Flutter, no rootBundle.

String _page({
  String? title = 'Title',
  String? group = 'Group',
  Object? order = 10,
  String? summary,
  String body = 'Body text.',
}) {
  final lines = <String>['---'];
  if (title != null) lines.add('title: $title');
  if (group != null) lines.add('group: $group');
  if (order != null) lines.add('order: $order');
  if (summary != null) lines.add('summary: $summary');
  lines
    ..add('---')
    ..add('')
    ..add(body);
  return lines.join('\n');
}

void main() {
  group('frontmatter parsing', () {
    test(
      'parses fields, derives slug from the file name, strips frontmatter',
      () {
        final c = DocsCatalog.fromSources({
          'getting-started.md': _page(
            title: 'Getting started',
            group: 'Getting started',
            order: 10,
            summary: 'The lede.',
            body: '# Getting started\n\nHello.',
          ),
        });
        final page = c.getPage('getting-started')!;
        expect(page.slug, 'getting-started');
        expect(page.title, 'Getting started');
        expect(page.group, 'Getting started');
        expect(page.order, 10);
        expect(page.summary, 'The lede.');
        expect(page.body, '# Getting started\n\nHello.');
        expect(page.body.contains('---'), isFalse);
        expect(page.body.contains('title:'), isFalse);
      },
    );

    test('summary is optional', () {
      final c = DocsCatalog.fromSources({'a.md': _page(summary: null)});
      expect(c.getPage('a')!.summary, isNull);
    });

    test('strips a leading path from the file name for the slug', () {
      final c = DocsCatalog.fromSources({
        'docs/content/tracking-time.md': _page(),
      });
      expect(c.getPage('tracking-time'), isNotNull);
    });

    test('unwraps quoted values', () {
      final c = DocsCatalog.fromSources({
        'a.md': _page(title: '"Quoted title"', summary: "'Quoted summary'"),
      });
      final page = c.getPage('a')!;
      expect(page.title, 'Quoted title');
      expect(page.summary, 'Quoted summary');
    });

    test('tolerates CRLF line endings', () {
      final raw = _page().replaceAll('\n', '\r\n');
      final c = DocsCatalog.fromSources({'a.md': raw});
      expect(c.getPage('a')!.title, 'Title');
    });

    test('throws when a required field is missing', () {
      expect(
        () => DocsCatalog.fromSources({'a.md': _page(title: null)}),
        throwsA(isA<DocParseException>()),
      );
      expect(
        () => DocsCatalog.fromSources({'a.md': _page(group: null)}),
        throwsA(isA<DocParseException>()),
      );
      expect(
        () => DocsCatalog.fromSources({'a.md': _page(order: null)}),
        throwsA(isA<DocParseException>()),
      );
    });

    test('throws when order is not an integer', () {
      expect(
        () => DocsCatalog.fromSources({'a.md': _page(order: 'ten')}),
        throwsA(isA<DocParseException>()),
      );
    });

    test('throws when there is no frontmatter block', () {
      expect(
        () => DocsCatalog.fromSources({'a.md': '# Just a heading\n\nNo meta.'}),
        throwsA(isA<DocParseException>()),
      );
    });

    test('throws when the frontmatter block is unterminated', () {
      expect(
        () => DocsCatalog.fromSources({
          'a.md': '---\ntitle: X\ngroup: Y\norder: 1\nbody with no close',
        }),
        throwsA(isA<DocParseException>()),
      );
    });

    test('throws on a malformed (colon-less) frontmatter line', () {
      expect(
        () => DocsCatalog.fromSources({
          'a.md': '---\ntitle: X\nthis line has no colon\norder: 1\n---\nBody',
        }),
        throwsA(isA<DocParseException>()),
      );
    });
  });

  group('ordering', () {
    test('pages within a group sort by order, ties by title', () {
      final c = DocsCatalog.fromSources({
        'b.md': _page(title: 'Beta', group: 'G', order: 20),
        'a.md': _page(title: 'Alpha', group: 'G', order: 10),
        'c.md': _page(title: 'Charlie', group: 'G', order: 20),
      });
      expect(
        c.groups.single.pages.map((p) => p.title),
        ['Alpha', 'Beta', 'Charlie'], // order 10, then 20 tie broken by title
      );
    });

    test('groups sort by the minimum order among their pages', () {
      final c = DocsCatalog.fromSources({
        'x.md': _page(title: 'X', group: 'Later', order: 30),
        'y.md': _page(title: 'Y', group: 'Earlier', order: 5),
        'z.md': _page(title: 'Z', group: 'Later', order: 1),
      });
      // "Later" holds order 1, so it precedes "Earlier" (min 5) despite the name.
      expect(c.groups.map((g) => g.title), ['Later', 'Earlier']);
    });

    test('reading order flattens groups then in-group order', () {
      final c = DocsCatalog.fromSources({
        'a.md': _page(title: 'A', group: 'First', order: 10),
        'b.md': _page(title: 'B', group: 'First', order: 20),
        'c.md': _page(title: 'C', group: 'Second', order: 30),
      });
      expect(c.pages.map((p) => p.slug), ['a', 'b', 'c']);
    });
  });

  group('getPage', () {
    test('returns the page on a hit', () {
      final c = DocsCatalog.fromSources({'a.md': _page()});
      expect(c.getPage('a'), isNotNull);
    });
    test('returns null on a miss', () {
      final c = DocsCatalog.fromSources({'a.md': _page()});
      expect(c.getPage('nope'), isNull);
    });
  });

  group('prevNext', () {
    DocsCatalog three() => DocsCatalog.fromSources({
      'a.md': _page(title: 'A', group: 'G', order: 10),
      'b.md': _page(title: 'B', group: 'G', order: 20),
      'c.md': _page(title: 'C', group: 'G', order: 30),
    });

    test('first page has no previous', () {
      final adj = three().prevNext('a');
      expect(adj.previous, isNull);
      expect(adj.next!.slug, 'b');
    });

    test('middle page has both', () {
      final adj = three().prevNext('b');
      expect(adj.previous!.slug, 'a');
      expect(adj.next!.slug, 'c');
    });

    test('last page has no next', () {
      final adj = three().prevNext('c');
      expect(adj.previous!.slug, 'b');
      expect(adj.next, isNull);
    });

    test('unknown slug yields both null', () {
      final adj = three().prevNext('missing');
      expect(adj.previous, isNull);
      expect(adj.next, isNull);
    });

    test('a single-page set has neither previous nor next', () {
      final c = DocsCatalog.fromSources({'only.md': _page()});
      final adj = c.prevNext('only');
      expect(adj.previous, isNull);
      expect(adj.next, isNull);
    });
  });

  group('edge cases', () {
    test('empty set has no groups and no pages', () {
      final c = DocsCatalog.fromSources({});
      expect(c.groups, isEmpty);
      expect(c.pages, isEmpty);
      expect(c.getPage('anything'), isNull);
    });
  });

  // A regression guard over the actual bundled docs (read from disk, not the
  // asset bundle — same files the AssetManifest glob picks up at runtime): they
  // must all parse and land in the contracted group order.
  group('bundled docs', () {
    DocsCatalog realCatalog() {
      final dir = Directory('docs/content');
      final sources = {
        for (final f in dir.listSync().whereType<File>())
          if (f.path.endsWith('.md')) f.path: f.readAsStringSync(),
      };
      return DocsCatalog.fromSources(sources);
    }

    test('all pages parse and order into the expected groups', () {
      final c = realCatalog();
      expect(c.pages, hasLength(6));
      expect(c.groups.map((g) => g.title), [
        'Getting started',
        'Tracking',
        'Invoicing',
        'Data',
        'Reference',
      ]);
      // Reference holds keyboard-shortcuts (50) then the CLI page (60).
      expect(
        c.groups.last.pages.map((p) => p.slug),
        ['keyboard-shortcuts', 'cli'],
      );
    });
  });
}
