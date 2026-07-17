import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/docs/docs_assets.dart';
import 'package:timedart/features/docs/docs_catalog.dart';
import 'package:timedart/widgets/markdown_style.dart';
import 'package:timedart/widgets/panel.dart';
import 'package:timedart/widgets/tap_target.dart';

// The in-app documentation screen (#252): an offline, themed reader over the
// bundled [DocsCatalog]. The loader shell ([DocsScreen]) fetches the catalogue
// from assets; [DocsView] is the pure UI over an already-built catalogue, so a
// widget test can drive it from an in-memory catalogue with no rootBundle.

/// Push the documentation screen. The app is otherwise dialog/panel-based, but
/// docs are a content surface of their own, so they get a full route.
Future<void> openDocs(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const DocsScreen()));

/// Back affordance for the docs app bars. Uses [appIconButton] so it meets the
/// 48 touch target on narrow (the app convention) rather than the ~44 a default
/// BackButton resolves to under the comfortable density; [leadingWidth] is set
/// to match so the title still hugs it.
Widget _docsBackButton() => Builder(
  builder: (ctx) => appIconButton(
    icon: Icons.arrow_back,
    tooltip: 'Back',
    onPressed: () => Navigator.of(ctx).maybePop(),
  ),
);

/// The section menu's fixed width in the wide layout.
const double _kDocsMenuWidth = 260.0;

/// Left inset of the reading column for a content pane of [paneWidth]: keeps a
/// notional [AppTokens.maxContentWidth] column's left edge, plus the base
/// gutter. Shared by the page body and the app bar so the back button/title
/// line up above the body text.
double _docsContentLeftInset(double paneWidth) =>
    ((paneWidth - AppTokens.maxContentWidth) / 2).clamp(0.0, double.infinity) +
    AppTokens.space2xl;

/// Optical inset of a glyph within an [appIconButton]'s narrow touch box — the
/// icon is centred in a [AppTokens.minTouchTarget] box, so its edge sits this
/// far inside the box. Shifting a button out by this much lands the *glyph* on
/// the content edge while the (larger) tap box overhangs into the margin.
double _glyphInset(double iconSize) =>
    (AppTokens.minTouchTarget - iconSize) / 2;

/// The docs app bar. The back button's glyph aligns with the body's left edge
/// ([leftInset]); its tap box overhangs left into the margin.
AppBar _docsAppBar({
  required Widget title,
  required double leftInset,
  List<Widget>? actions,
}) {
  final leadPad = (leftInset - _glyphInset(AppTokens.iconMd)).clamp(
    0.0,
    double.infinity,
  );
  return AppBar(
    titleSpacing: 0,
    leadingWidth: leadPad + AppTokens.minTouchTarget,
    leading: Padding(
      padding: EdgeInsets.only(left: leadPad),
      child: _docsBackButton(),
    ),
    title: title,
    actions: actions,
  );
}

/// Loader shell: reads the bundled catalogue, then hands off to [DocsView].
class DocsScreen extends StatefulWidget {
  const DocsScreen({super.key});

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  late final Future<DocsCatalog> _catalog = loadDocsCatalog();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocsCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Documentation')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space2xl),
                child: Text(
                  "Documentation couldn't be loaded.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Documentation')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return DocsView(catalog: snapshot.data!);
      },
    );
  }
}

/// The documentation reader over a built [catalog]: a section/page menu and the
/// selected page, with prev/next navigation across the reading order. Wide shows
/// the page and the menu side by side (menu right); narrow shows the page with
/// the menu in a drawer.
class DocsView extends StatefulWidget {
  const DocsView({super.key, required this.catalog, this.initialSlug});

  final DocsCatalog catalog;

  /// Page to open on first show; defaults to the first page in reading order.
  final String? initialSlug;

  @override
  State<DocsView> createState() => _DocsViewState();
}

class _DocsViewState extends State<DocsView> {
  String? _slug;

  @override
  void initState() {
    super.initState();
    final pages = widget.catalog.pages;
    _slug = widget.initialSlug ?? (pages.isEmpty ? null : pages.first.slug);
  }

  void _select(String slug) => setState(() => _slug = slug);

  @override
  Widget build(BuildContext context) {
    final pages = widget.catalog.pages;
    if (pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documentation')),
        body: Center(
          child: Text(
            'No documentation is available yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final page =
        (_slug == null ? null : widget.catalog.getPage(_slug!)) ?? pages.first;
    final narrow = context.isNarrow;

    if (narrow) {
      // The page fills the screen; the section list opens as a right-side
      // drawer from a menu button (menu is on the right on wide too), so
      // there's no nested index → page → back hop. Selecting closes it.
      return LayoutBuilder(
        builder: (context, c) => Scaffold(
          appBar: _docsAppBar(
            title: Text(page.title),
            leftInset: _docsContentLeftInset(c.maxWidth),
            actions: [
              Padding(
                // Land the glyph on the content's right edge (space2xl), tap
                // box overhanging right. appIconButton floors the hit box at
                // minTouchTarget (48) on narrow — the app's touch convention.
                padding: EdgeInsets.only(
                  right: AppTokens.space2xl - _glyphInset(AppTokens.iconLg),
                ),
                child: Builder(
                  builder: (ctx) => appIconButton(
                    icon: Icons.menu,
                    iconSize: AppTokens.iconLg,
                    tooltip: 'Contents',
                    onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                  ),
                ),
              ),
            ],
          ),
          endDrawer: Drawer(
            child: SafeArea(
              child: Builder(
                builder: (ctx) => _Sidebar(
                  catalog: widget.catalog,
                  selected: page.slug,
                  onSelect: (slug) {
                    _select(slug);
                    Scaffold.of(ctx).closeEndDrawer();
                  },
                ),
              ),
            ),
          ),
          body: _DocPageBody(
            catalog: widget.catalog,
            page: page,
            onSelect: _select,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        // The app bar spans the full width; the content pane is what's left of
        // it after the menu + divider, so inset the back button by that pane's
        // content inset to line it up above the body text.
        final paneWidth = c.maxWidth - _kDocsMenuWidth - AppTokens.strokeThin;
        return Scaffold(
          appBar: _docsAppBar(
            title: const Text('Documentation'),
            leftInset: _docsContentLeftInset(paneWidth),
          ),
          // Content left, section menu right — mirrors the app shell's
          // tracker (left) | panel (right) arrangement.
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _DocPageBody(
                  catalog: widget.catalog,
                  page: page,
                  onSelect: _select,
                ),
              ),
              const VerticalDivider(width: AppTokens.strokeThin),
              SizedBox(
                width: _kDocsMenuWidth,
                child: _Sidebar(
                  catalog: widget.catalog,
                  selected: page.slug,
                  onSelect: _select,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The section/page list. Groups are headers; pages are selectable rows.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.catalog,
    required this.selected,
    required this.onSelect,
  });

  final DocsCatalog catalog;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = theme.extension<AppTextStyles>()!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      children: [
        for (final group in catalog.groups) ...[
          // A single-page group's header just echoes the page name, so only
          // show a header once a section actually groups more than one page.
          if (group.pages.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceSm,
                AppTokens.spaceLg,
                AppTokens.space3xs,
              ),
              child: Text(
                group.title,
                style: styles.sectionHeader.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          for (final page in group.pages)
            _PageRow(
              title: page.title,
              selected: page.slug == selected,
              onTap: () => onSelect(page.slug),
            ),
        ],
      ],
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowTitle = theme.extension<AppTextStyles>()!.rowTitleSmall;
    return panelRowTile(
      context: context,
      selected: selected,
      onTap: onTap,
      // Selected page keeps its primary-colour cue; the shared tile supplies the
      // surfaceContainerHighest background for the selection.
      title: Text(
        title,
        style: selected
            ? rowTitle.copyWith(color: theme.colorScheme.primary)
            : rowTitle,
      ),
    );
  }
}

/// A rendered page: title, optional summary lede, the markdown body, and the
/// prev/next controls across the reading order.
class _DocPageBody extends StatelessWidget {
  const _DocPageBody({
    required this.catalog,
    required this.page,
    required this.onSelect,
  });

  final DocsCatalog catalog;
  final DocPage page;
  // Selecting from within a page (a body link or prev/next) just switches which
  // page is shown.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adjacent = catalog.prevNext(page.slug);
    return LayoutBuilder(
      builder: (context, c) {
        // Keep the reading column's LEFT edge where a centred, capped column
        // would start, but let content run right to the menu divider with only
        // a small trailing pad — removes the dead band on the right while
        // leaving the left inset unchanged (mirrors the shell's stretch pages).
        final left = _docsContentLeftInset(c.maxWidth);
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: left,
              right: AppTokens.space2xl,
              top: AppTokens.spaceXl,
              bottom: AppTokens.spaceXl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (page.summary != null && page.summary!.isNotEmpty) ...[
                  Text(
                    page.summary!.toUpperCase(),
                    style: theme.extension<AppTextStyles>()!.eyebrow,
                  ),
                  const SizedBox(height: AppTokens.spaceLg),
                ],
                MarkdownBody(
                  data: page.body,
                  styleSheet: appMarkdownStyleSheet(theme),
                  imageBuilder: _imageBuilder,
                  builders: {
                    'blockquote': _AdmonitionBuilder(),
                    'code': _KeycapBuilder(),
                  },
                  onTapLink: (text, href, title) => _onTapLink(context, href),
                ),
                const SizedBox(height: AppTokens.space2xl),
                _PrevNext(
                  previous: adjacent.previous,
                  next: adjacent.next,
                  onSelect: onSelect,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onTapLink(BuildContext context, String? href) {
    if (href == null) return;
    // External links open in the browser; an in-docs link (a bare or /docs/
    // slug) selects that page.
    if (href.startsWith('http://') || href.startsWith('https://')) {
      launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      return;
    }
    final slug = href
        .replaceFirst(RegExp(r'^/?(docs/)?'), '')
        .replaceAll('/', '');
    if (catalog.getPage(slug) != null) onSelect(slug);
  }
}

/// Prev/next controls over the reading order. The first page shows no previous;
/// the last shows no next.
class _PrevNext extends StatelessWidget {
  const _PrevNext({
    required this.previous,
    required this.next,
    required this.onSelect,
  });

  final DocPage? previous;
  final DocPage? next;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (previous == null && next == null) return const SizedBox.shrink();
    return Row(
      children: [
        if (previous != null)
          Expanded(
            child: _NavCard(
              label: 'Previous',
              title: previous!.title,
              alignEnd: false,
              onTap: () => onSelect(previous!.slug),
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: AppTokens.spaceMd),
        if (next != null)
          Expanded(
            child: _NavCard(
              label: 'Next',
              title: next!.title,
              alignEnd: true,
              onTap: () => onSelect(next!.slug),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.label,
    required this.title,
    required this.alignEnd,
    required this.onTap,
  });

  final String label;
  final String title;
  final bool alignEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          border: Border.all(color: AppTokens.colorBorder),
        ),
        child: Column(
          crossAxisAlignment: alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!alignEnd)
                  const Icon(Icons.chevron_left, size: AppTokens.iconSm),
                Text(label, style: theme.textTheme.bodySmall),
                if (alignEnd)
                  const Icon(Icons.chevron_right, size: AppTokens.iconSm),
              ],
            ),
            const SizedBox(height: AppTokens.space3xs),
            Text(
              title,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: TextStyle(
                fontFamily: AppTokens.fontFamily,
                fontSize: AppTokens.fontSizeSm,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a bundled image referenced by a relative path (`assets/foo.png`) as
/// an asset under [docsAssetDir]. Falls back to the alt text if it can't load.
Widget _imageBuilder(Uri uri, String? title, String? alt) {
  final path = '$docsAssetDir/${uri.path}';
  return Image.asset(
    path,
    errorBuilder: (context, error, stackTrace) =>
        Text(alt ?? '', style: Theme.of(context).textTheme.bodySmall),
  );
}

/// Renders inline `code` spans as keycaps. The docs use inline code for
/// keyboard keys (per the docs contract), so they read like the app's shortcut
/// keycaps — a flat, bordered, rounded chip in the app font (mirrors the
/// shortcuts dialog's `_cap`) rather than a cramped monospace highlight. A
/// fenced code block (multi-line) falls through to the default block rendering.
class _KeycapBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (text.contains('\n')) return null; // a code block, not an inline key
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space2xs,
        vertical: AppTokens.space4xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusButton),
        border: Border.all(
          color: AppTokens.colorBorder,
          width: AppTokens.strokeThin,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTokens.fontFamily,
          fontSize: AppTokens.fontSizeXs,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// Markdown theming from the app's design tokens. Built from the ambient theme,
/// then nudged so headings, code, links, and spacing read like the rest of the
/// app rather than flutter_markdown's Material defaults.
/// One admonition kind (the callout convention): its leading marker, label,
/// icon, and accent colour.
enum _Admonition {
  note('Note', Icons.info_outline),
  tip('Tip', Icons.lightbulb_outline),
  warning('Warning', Icons.warning_amber_outlined);

  const _Admonition(this.label, this.icon);
  final String label;
  final IconData icon;

  Color color(ColorScheme scheme) => switch (this) {
    _Admonition.note => scheme.primary,
    _Admonition.tip => AppTokens.colorAccentText,
    _Admonition.warning => const Color(0xFFE0A82E),
  };

  static _Admonition? fromLead(String lead) => switch (lead.toLowerCase()) {
    'note' => _Admonition.note,
    'tip' => _Admonition.tip,
    'warning' => _Admonition.warning,
    _ => null,
  };
}

/// Renders blockquotes. A blockquote whose text begins with `Note:` / `Tip:` /
/// `Warning:` (the callout convention — the marker is bolded in source, which
/// the parser flattens into the leading text) becomes a styled admonition;
/// any other blockquote falls back to a plain quoted block.
class _AdmonitionBuilder extends MarkdownElementBuilder {
  static final _lead = RegExp(r'^(Note|Tip|Warning):\s*', caseSensitive: false);

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Collapse source line wraps (a hard `\n` in the markdown) to spaces so the
    // callout flows and wraps to its width, like single-line callouts.
    final text = element.textContent.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
    final match = _lead.firstMatch(text);
    final kind = match == null ? null : _Admonition.fromLead(match.group(1)!);

    if (kind == null) {
      // A generic blockquote: a muted, left-ruled block.
      return Container(
        margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceMd,
          AppTokens.spaceXs,
          AppTokens.spaceMd,
          AppTokens.spaceXs,
        ),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTokens.colorBorder, width: 3),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppTokens.fontFamily,
            fontSize: AppTokens.fontSizeDocsBody,
            fontWeight: AppTokens.fontWeightDocsBody,
            fontStyle: FontStyle.italic,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final color = kind.color(scheme);
    final body = text.substring(match!.end);
    // Flat, like the primary button: a tinted fill + a faint full border on the
    // button radius — no shadow, no left rule.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusButton),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sized up and centred on the first text line (its line box) so it
          // reads as a deliberate marker, not a stray glyph floating high.
          SizedBox(
            height: AppTokens.fontSizeDocsBody * AppTokens.fontHeightDocsBody,
            child: Icon(kind.icon, size: AppTokens.iconLg, color: color),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${kind.label}: ',
                    style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  ),
                  TextSpan(text: body),
                ],
                style: TextStyle(
                  fontFamily: AppTokens.fontFamily,
                  fontSize: AppTokens.fontSizeDocsBody,
                  fontWeight: AppTokens.fontWeightDocsBody,
                  height: AppTokens.fontHeightDocsBody,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
