import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/constants/theme.dart';
import 'package:timedart/features/docs/docs_catalog.dart';
import 'package:timedart/features/docs/docs_screen.dart';

// Widget-level smoke coverage for the docs reader ([DocsView]): the sidebar
// lists the catalogue's pages, opening one shows its body, and prev/next steps
// through the reading order. Driven from an in-memory catalogue so there's no
// rootBundle dependency (asset loading lives behind the docs_assets seam).

String _page({
  required String title,
  required String group,
  required int order,
  String body = 'Body text.',
}) => '---\ntitle: $title\ngroup: $group\norder: $order\n---\n\n$body';

final _catalog = DocsCatalog.fromSources({
  'getting-started.md': _page(
    title: 'Getting started',
    group: 'Getting started',
    order: 10,
    body:
        '# Getting started\n\nWelcome to the docs.\n\n'
        '> **Note:** A running timer survives a restart.',
  ),
  'tracking-time.md': _page(
    title: 'Tracking time',
    group: 'Tracking',
    order: 20,
    body: '# Tracking time\n\nHow the timer works. Press `Ctrl`+`S`.',
  ),
  // A second page in "Tracking" so it's a real multi-page group (its header
  // shows, unlike the single-page groups).
  'tracking-rates.md': _page(
    title: 'Tracking rates',
    group: 'Tracking',
    order: 30,
    body: '# Tracking rates\n\nAbout rates.',
  ),
});

Future<void> _pump(WidgetTester tester, {String? initialSlug}) async {
  // A wide surface so the master-detail layout shows the sidebar and page
  // together (narrow splits them across two steps).
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      home: DocsView(catalog: _catalog, initialSlug: initialSlug),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sidebar lists every catalogue page', (tester) async {
    await _pump(tester);
    // Group headers and page rows are both present.
    expect(find.text('Tracking'), findsOneWidget);
    // "Getting started" is both a group header and a page title, so it appears
    // more than once; "Tracking time" is a page row only.
    expect(find.text('Tracking time'), findsWidgets);
    expect(find.text('Getting started'), findsWidgets);
  });

  testWidgets('opens the first page by default and renders its body', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('Welcome to the docs.'), findsOneWidget);
    // The callout renders as an admonition, keeping its body text.
    expect(find.textContaining('survives a restart'), findsOneWidget);
  });

  testWidgets('selecting a page from the sidebar shows it', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Tracking time').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('How the timer works.'), findsOneWidget);
    // Inline code renders as keycaps (its own Text widget), not swallowed into
    // the paragraph run.
    expect(find.text('Ctrl'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('next navigates forward through the reading order', (
    tester,
  ) async {
    await _pump(tester);
    // First page: only a Next control (no previous).
    expect(find.text('Previous'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('How the timer works.'), findsOneWidget);
    // A middle page has both controls; step once more to the last page.
    expect(find.text('Previous'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('About rates.'), findsOneWidget);
    // Last page: a Previous control, no Next.
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('previous navigates back through the reading order', (
    tester,
  ) async {
    await _pump(tester, initialSlug: 'tracking-time');
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome to the docs.'), findsOneWidget);
  });

  testWidgets('narrow shows the page directly; the menu drawer switches pages', (
    tester,
  ) async {
    // Narrow surface (< breakpointMd): no side-by-side sidebar.
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: DocsView(catalog: _catalog),
      ),
    );
    await tester.pumpAndSettle();

    // The first page is shown straight away; the section list is not (it's in
    // the closed drawer). The "Tracking" group header is drawer-only (the pager
    // shows the page *title* "Tracking time", so that isn't a drawer marker).
    expect(find.textContaining('Welcome to the docs.'), findsOneWidget);
    expect(find.text('Tracking'), findsNothing);

    // Open the contents drawer, pick another page: it closes and the page swaps.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Tracking'), findsOneWidget); // group header, drawer-only
    await tester.tap(find.text('Tracking time').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('How the timer works.'), findsOneWidget);
    // The group header is drawer-only, so its absence confirms the drawer closed.
    expect(find.text('Tracking'), findsNothing);
  });

  testWidgets('a section header shows only when its group has >1 page', (
    tester,
  ) async {
    final catalog = DocsCatalog.fromSources({
      'a.md': _page(title: 'Alpha', group: 'Solo', order: 10, body: '# Alpha'),
      'b.md': _page(title: 'Beta', group: 'Pair', order: 20, body: '# Beta'),
      'c.md': _page(title: 'Gamma', group: 'Pair', order: 30, body: '# Gamma'),
    });
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: DocsView(catalog: catalog),
      ),
    );
    await tester.pumpAndSettle();

    // Single-page group: no header (it would just echo the page name).
    expect(find.text('Solo'), findsNothing);
    // Multi-page group: header shown.
    expect(find.text('Pair'), findsOneWidget);
  });
}
