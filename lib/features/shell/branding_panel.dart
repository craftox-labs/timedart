import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/shell/side_panel.dart';
import 'package:time_tracker/widgets/focus_ring.dart';
import 'package:time_tracker/widgets/panel_title_bar.dart';

/// The side panel while in Branding (Settings) mode: three flat collapsible
/// sections — Themes, Profiles, Templates — listing the configured rows.
/// Selecting a row drives the content-pane preview. Mirrors [SidePanel]'s look
/// and keyboard nav (j/k move, Enter/l expand-or-select, h collapse, Esc back)
/// but is a separate widget so the client/job panel's tuned navigation is
/// untouched. Editing/adding rows arrives with the editors (a later PR).
class BrandingPanel extends StatefulWidget {
  const BrandingPanel({
    super.key,
    required this.db,
    required this.onSelectTheme,
    required this.onSelectProfile,
    required this.onSelectTemplate,
    required this.onBack,
    this.onShowHelp,
    this.onOpenSettings,
    this.autofocus = false,
  });

  final AppDatabase db;
  final void Function(int themeId) onSelectTheme;
  final void Function(int profileId) onSelectProfile;
  final void Function(InvoiceTemplate template) onSelectTemplate;
  final VoidCallback onBack; // leave Branding mode (Esc / the back arrow)
  // Footer callbacks, matching the normal panel's base row.
  final VoidCallback? onShowHelp;
  final VoidCallback? onOpenSettings;
  final bool autofocus;

  @override
  State<BrandingPanel> createState() => _BrandingPanelState();
}

enum _Section { themes, profiles, templates }

String _sectionLabel(_Section s) => switch (s) {
      _Section.themes => 'Themes',
      _Section.profiles => 'Profiles',
      _Section.templates => 'Templates',
    };

// A flattened visible row: a section header, or one entity under an open one.
sealed class _BRow {
  const _BRow();
}

class _HeaderRow extends _BRow {
  final _Section section;
  final bool expanded;
  final bool hasItems;
  const _HeaderRow(this.section, {required this.expanded, required this.hasItems});
}

class _EntityRow extends _BRow {
  final _Section section;
  final int id;
  final String name;
  final bool isDefault;
  const _EntityRow(this.section, {required this.id, required this.name, required this.isDefault});
}

class _BrandingPanelState extends State<BrandingPanel> {
  late final Stream<List<InvoiceTheme>> _themes = widget.db.watchThemes();
  late final Stream<List<InvoiceProfile>> _profiles = widget.db.watchProfiles();
  late final Stream<List<InvoiceTemplate>> _templates = widget.db.watchTemplates();

  // Sections start open — a settings surface reads best fully expanded.
  final Set<_Section> _expanded = {..._Section.values};
  final FocusNode _cursorNode = FocusNode(debugLabel: 'brandingCursor');
  int _cursor = 0;
  List<_BRow> _rows = const [];

  // Which entity is highlighted (drives the preview + the selected pill).
  _Section? _selSection;
  int? _selId;

  @override
  void initState() {
    super.initState();
    _cursorNode.addListener(_repaint);
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cursorNode.removeListener(_repaint);
    _cursorNode.dispose();
    super.dispose();
  }

  void _moveCursor(int delta) {
    if (_rows.isEmpty) return;
    final next = (_cursor + delta).clamp(0, _rows.length - 1);
    if (next != _cursor) setState(() => _cursor = next);
  }

  void _toggleSection(_Section s) {
    setState(() {
      if (!_expanded.remove(s)) _expanded.add(s);
    });
  }

  // Templates need the full row (themeId/profileId) to drive the preview, but
  // _EntityRow carries only an id, so we keep the latest templates snapshot to
  // resolve a tap back to its row.
  List<InvoiceTemplate> _latestTemplates = const [];

  void _selectEntity(_EntityRow row) {
    setState(() {
      _selSection = row.section;
      _selId = row.id;
    });
    switch (row.section) {
      case _Section.themes:
        widget.onSelectTheme(row.id);
      case _Section.profiles:
        widget.onSelectProfile(row.id);
      case _Section.templates:
        for (final t in _latestTemplates) {
          if (t.id == row.id) {
            widget.onSelectTemplate(t);
            break;
          }
        }
    }
  }

  void _activateCurrent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is _HeaderRow) {
      if (row.hasItems) _toggleSection(row.section);
    } else if (row is _EntityRow) {
      _selectEntity(row);
    }
  }

  void _collapseCurrent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is _HeaderRow) {
      if (row.expanded) _toggleSection(row.section);
    } else if (row is _EntityRow) {
      // Jump to the owning section header.
      for (var i = _cursor; i >= 0; i--) {
        if (_rows[i] is _HeaderRow) {
          setState(() => _cursor = i);
          break;
        }
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored; // let pane-switching bubble to the shell
    }
    final right = key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.arrowRight;
    final left = key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.arrowLeft;

    if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowDown) {
      _moveCursor(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowUp) {
      _moveCursor(-1);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (right || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _activateCurrent();
      return KeyEventResult.handled;
    }
    if (left) {
      _collapseCurrent();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _cursorNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          PanelTitleBar(title: 'Settings', onBack: widget.onBack),
          Expanded(
            child: StreamBuilder<List<InvoiceTheme>>(
              stream: _themes,
              builder: (context, themeSnap) {
                return StreamBuilder<List<InvoiceProfile>>(
                  stream: _profiles,
                  builder: (context, profileSnap) {
                    return StreamBuilder<List<InvoiceTemplate>>(
                      stream: _templates,
                      builder: (context, templateSnap) {
                        _latestTemplates = templateSnap.data ?? const [];
                        return _buildList(
                          themes: themeSnap.data ?? const [],
                          profiles: profileSnap.data ?? const [],
                          templates: _latestTemplates,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          if (widget.onShowHelp != null || widget.onOpenSettings != null)
            PanelFooter(
              onShowHelp: widget.onShowHelp,
              onOpenSettings: widget.onOpenSettings,
            ),
        ],
      ),
    );
  }

  Widget _buildList({
    required List<InvoiceTheme> themes,
    required List<InvoiceProfile> profiles,
    required List<InvoiceTemplate> templates,
  }) {
    List<_EntityRow> entities(_Section s) => switch (s) {
          _Section.themes => [
              for (final x in themes)
                _EntityRow(s, id: x.id, name: x.name, isDefault: x.isDefault),
            ],
          _Section.profiles => [
              for (final x in profiles)
                _EntityRow(s, id: x.id, name: x.name, isDefault: x.isDefault),
            ],
          _Section.templates => [
              for (final x in templates)
                _EntityRow(s, id: x.id, name: x.name, isDefault: x.isDefault),
            ],
        };

    final rows = <_BRow>[];
    for (final s in _Section.values) {
      final items = entities(s);
      final expanded = _expanded.contains(s);
      rows.add(_HeaderRow(s, expanded: expanded, hasItems: items.isNotEmpty));
      if (expanded) rows.addAll(items);
    }
    _rows = rows;
    if (_cursor >= _rows.length) _cursor = _rows.isEmpty ? 0 : _rows.length - 1;

    final cursorActive = _cursorNode.hasPrimaryFocus;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space4xs),
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final row = _rows[i];
        final focused = i == _cursor && cursorActive;
        final tile = FocusRing(
          focused: focused,
          edgesOnly: true,
          child: switch (row) {
            _HeaderRow() => _SectionHeaderTile(
                label: _sectionLabel(row.section),
                expanded: row.expanded,
                hasItems: row.hasItems,
                onTap: () {
                  setState(() => _cursor = i);
                  if (row.hasItems) _toggleSection(row.section);
                },
              ),
            _EntityRow() => _EntityTile(
                name: row.name,
                isDefault: row.isDefault,
                selected: row.section == _selSection && row.id == _selId,
                onTap: () {
                  setState(() => _cursor = i);
                  _selectEntity(row);
                },
              ),
          },
        );
        final dividerBefore = i > 0 && row is _HeaderRow;
        if (!dividerBefore) return tile;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(
              height: AppTokens.strokeThin,
              thickness: AppTokens.strokeThin,
              color: AppTokens.colorBorder,
            ),
            tile,
          ],
        );
      },
    );
  }
}

class _SectionHeaderTile extends StatelessWidget {
  const _SectionHeaderTile({
    required this.label,
    required this.expanded,
    required this.hasItems,
    required this.onTap,
  });
  final String label;
  final bool expanded;
  final bool hasItems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      minTileHeight: 36,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      horizontalTitleGap: AppTokens.space2xs,
      onTap: onTap,
      leading: Icon(
        expanded ? Icons.expand_more : Icons.chevron_right,
        size: AppTokens.iconSm,
        color: expanded ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: AppTokens.fontSizeSm,
          fontWeight: FontWeight.w500,
          color: t.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _EntityTile extends StatelessWidget {
  const _EntityTile({
    required this.name,
    required this.isDefault,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final bool isDefault;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      selected: selected,
      contentPadding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.space3xs,
        AppTokens.spaceMd,
        AppTokens.space3xs,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AppTokens.fontSizeXs,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          if (isDefault) ...[
            const SizedBox(width: AppTokens.spaceXs),
            Text(
              'default',
              style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
