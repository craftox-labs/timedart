import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/shell/keymap.dart';
import 'package:timedart/features/shell/side_panel.dart';
import 'package:timedart/widgets/focus_ring.dart';
import 'package:timedart/widgets/panel.dart';
import 'package:timedart/widgets/tap_target.dart';

/// The side panel while in Settings mode: two flat collapsible sections —
/// Templates (the visual style) and Profiles — listing the configured rows.
/// Selecting a row opens that entity's editor directly in the content pane
/// (the shell gates the switch behind an unsaved-changes check). Mirrors
/// [SidePanel]'s look and keyboard nav (j/k move, Enter/l expand-or-open,
/// h collapse, Esc back) but is a separate widget so the client/project panel's
/// tuned navigation is untouched.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.db,
    required this.onBack,
    this.selectedTemplateId,
    this.selectedProfileId,
    this.onAddTemplate,
    this.onEditTemplate,
    this.onAddProfile,
    this.onEditProfile,
    this.onRerunOnboarding,
    this.onExportData,
    this.onImportData,
    this.onCheckForUpdates,
    this.onShowHelp,
    this.onOpenSettings,
    this.onOpenTracker,
    this.onFocusTracker,
    this.onFocusPanel,
    this.settingsActive = false,
    this.showFooter = true,
    this.autofocus = false,
    this.cursorFocusNode,
    this.searchFocusNode,
  });

  final AppDatabase db;
  final VoidCallback onBack; // leave Settings mode (Esc / the back arrow)
  // Externally supplied so the shell's shared pane-switch focus (Tab,
  // Ctrl-h/l — this panel already forwards ctrl-combos to the shell, see
  // _onKey) can target this panel's row cursor, same as SidePanel. Falls back
  // to an internal node when not supplied (e.g. the narrow drawer).
  final FocusNode? cursorFocusNode;
  // Search field focus, owned by the shell so a global `/` (from any pane) can
  // jump into search while in Settings — mirrors SidePanel.searchFocusNode.
  // Null → an internal node (the narrow drawer).
  final FocusNode? searchFocusNode;
  // The entity currently open in the content pane, if any — drives the
  // highlighted row. The panel no longer owns its own selection: a row tap
  // opens that entity's editor directly (see onEditTemplate/onEditProfile).
  final String? selectedTemplateId;
  final String? selectedProfileId;
  // Add/edit affordances per section — an add `+` on the header appears only
  // where the matching callback is wired. `startEditing` is true when the
  // entity should open straight into edit mode (the `e` shortcut) rather
  // than the read-only view a plain open otherwise lands on.
  final VoidCallback? onAddTemplate;
  final void Function(InvoiceTemplate, {bool startEditing})? onEditTemplate;
  final VoidCallback? onAddProfile;
  final void Function(InvoiceProfile, {bool startEditing})? onEditProfile;
  // App-level actions under the General section. Replays first-run onboarding
  // (also the dev/test reset); null hides the row.
  final Future<void> Function()? onRerunOnboarding;
  // Export the whole database to a portable backup file (PRD #189, #190);
  // null hides the row.
  final Future<void> Function()? onExportData;
  // Import a backup file, replacing all data (PRD #189, #191); null hides it.
  final Future<void> Function()? onImportData;
  // Check GitHub Releases for a newer build (Phase 1 update check); null hides
  // the row (e.g. on web, which is always the deployed latest).
  final Future<void> Function()? onCheckForUpdates;
  // Footer callbacks, matching the normal panel's base row.
  final VoidCallback? onShowHelp;
  final VoidCallback? onOpenSettings;
  // Go to the tracker — the timedart symbol beside the footer gear.
  final VoidCallback? onOpenTracker;
  // Pane-switch intents, forwarded to the shell's focus methods (Ctrl-h/l and
  // the Ctrl-w chord). Null in layouts without keyboard nav (drawer).
  final VoidCallback? onFocusTracker;
  final VoidCallback? onFocusPanel;
  // Whether Settings is the active section (drives the footer switch tint).
  final bool settingsActive;
  // Suppressed in the wide layout — the header carries those actions there.
  final bool showFooter;
  final bool autofocus;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

// Order here drives the panel's section order: General first, then the lists.
enum _Section { general, templates, profiles }

String _sectionLabel(_Section s) => switch (s) {
  _Section.templates => 'Templates',
  _Section.profiles => 'Profiles',
  _Section.general => 'General',
};

String _sectionSingular(_Section s) => switch (s) {
  _Section.templates => 'Template',
  _Section.profiles => 'Profile',
  _Section.general => 'General',
};

// A flattened visible row: a section header, or one entity under an open one.
sealed class _BRow {
  const _BRow();
}

class _HeaderRow extends _BRow {
  final _Section section;
  final bool expanded;
  final bool hasItems;
  const _HeaderRow(
    this.section, {
    required this.expanded,
    required this.hasItems,
  });
}

class _EntityRow extends _BRow {
  final _Section section;
  final String id;
  final String name;
  final bool isDefault;
  const _EntityRow(
    this.section, {
    required this.id,
    required this.name,
    required this.isDefault,
  });
}

// A tappable command under the General section (e.g. Re-run setup) — no
// underlying entity, just a label + icon + action.
class _ActionRow extends _BRow {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _SettingsPanelState extends State<SettingsPanel> {
  late final Stream<List<InvoiceTemplate>> _templates = widget.db
      .watchTemplates();
  late final Stream<List<InvoiceProfile>> _profiles = widget.db.watchProfiles();

  // Sections start collapsed so the menu isn't overwhelming on open; the user
  // expands what they need, and that's remembered while they stay in Settings.
  final Set<_Section> _expanded = <_Section>{};
  FocusNode? _internalCursor;
  FocusNode get _cursorNode =>
      widget.cursorFocusNode ??
      (_internalCursor ??= FocusNode(debugLabel: 'settingsCursor'));

  // Search — mirrors SidePanel. Filters the sections' items by name/label;
  // an active query force-expands every matching section (see _buildList).
  final _searchController = TextEditingController();
  FocusNode? _internalSearch;
  FocusNode get _searchFocus =>
      widget.searchFocusNode ??
      (_internalSearch ??= FocusNode(debugLabel: 'settingsSearch'));
  String _query = '';
  bool _searching = false;

  int _cursor = 0;
  List<_BRow> _rows = const [];
  final _chords = ChordDetector(); // Ctrl-w window-motion sequence state

  @override
  void initState() {
    super.initState();
    _cursorNode.addListener(_repaint);
    // Select-all whenever the search field gains focus, so typing replaces a
    // stale query (matches SidePanel).
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus) {
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    }
  }

  void _focusSearch() => _searchFocus.requestFocus();

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _cursor = 0;
    });
  }

  void _repaint() {
    // A focus excursion abandons any half-typed chord.
    _chords.reset();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cursorNode.removeListener(_repaint);
    _internalCursor?.dispose();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _internalSearch?.dispose();
    _searchController.dispose();
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

  // _EntityRow carries only an id, so we keep the latest snapshots to resolve
  // an edited row back to its full object.
  List<InvoiceTemplate> _latestTemplates = const [];
  List<InvoiceProfile> _latestProfiles = const [];

  VoidCallback? _addFor(_Section s) => switch (s) {
    _Section.templates => widget.onAddTemplate,
    _Section.profiles => widget.onAddProfile,
    _Section.general => null, // actions, not a list you add to
  };

  bool _editableSection(_Section s) => switch (s) {
    _Section.templates => widget.onEditTemplate != null,
    _Section.profiles => widget.onEditProfile != null,
    _Section.general => false,
  };

  // The wired General-section actions (only those with a callback present).
  // Data actions first, then the dev/reset re-run.
  List<_ActionRow> _actionRows() => [
    if (widget.onExportData != null)
      _ActionRow(
        label: 'Export data',
        icon: Icons.file_download_outlined,
        onTap: () => widget.onExportData!(),
      ),
    if (widget.onImportData != null)
      _ActionRow(
        label: 'Import data',
        icon: Icons.file_upload_outlined,
        onTap: () => widget.onImportData!(),
      ),
    if (widget.onCheckForUpdates != null)
      _ActionRow(
        label: 'Check for updates',
        icon: Icons.system_update_alt,
        onTap: () => widget.onCheckForUpdates!(),
      ),
    if (widget.onRerunOnboarding != null)
      _ActionRow(
        label: 'Re-run setup',
        icon: Icons.replay,
        onTap: () => widget.onRerunOnboarding!(),
      ),
  ];

  void _edit(_Section s, String id, {bool startEditing = false}) {
    switch (s) {
      case _Section.templates:
        for (final x in _latestTemplates) {
          if (x.id == id) {
            return widget.onEditTemplate?.call(x, startEditing: startEditing);
          }
        }
      case _Section.profiles:
        for (final x in _latestProfiles) {
          if (x.id == id) {
            return widget.onEditProfile?.call(x, startEditing: startEditing);
          }
        }
      case _Section.general:
        break; // no editable entities — actions handle their own onTap
    }
  }

  void _activateCurrent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is _HeaderRow) {
      if (row.hasItems) _toggleSection(row.section);
    } else if (row is _EntityRow) {
      _edit(row.section, row.id);
    } else if (row is _ActionRow) {
      row.onTap();
    }
  }

  void _collapseCurrent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is _HeaderRow) {
      if (row.expanded) _toggleSection(row.section);
    } else {
      // An item row (entity or action): jump to the owning section header.
      for (var i = _cursor; i >= 0; i--) {
        if (_rows[i] is _HeaderRow) {
          setState(() => _cursor = i);
          break;
        }
      }
    }
  }

  // Settings scope = list nav + settings actions + the global pane-switch
  // bindings. Owning the global scope's Ctrl-w chord here (the panel owns the
  // h/l keys that complete it) is what fixes the previously-silent gap. `?`/`/`,
  // Tab, Ctrl-, and the timer keys bubble to the shell.
  static const _scopes = {KeyScope.list, KeyScope.settings, KeyScope.global};

  void _jumpTo(int index) {
    if (_rows.isEmpty) return;
    setState(() => _cursor = index.clamp(0, _rows.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // While typing in the search field, let it consume everything.
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;
    final r = Keymap.resolve(
      event,
      _chords,
      _scopes,
      ctrlDown: HardwareKeyboard.instance.isControlPressed,
      shiftDown: HardwareKeyboard.instance.isShiftPressed,
    );
    switch (r) {
      case KeyPending():
        return KeyEventResult.handled;
      case KeyNone():
        return KeyEventResult.ignored;
      case KeyMatch(:final intent):
        if (event is! KeyDownEvent && !Keymap.isRepeatable(intent)) {
          return KeyEventResult.ignored;
        }
        return _handleIntent(intent)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
    }
  }

  bool _handleIntent(KeyIntent intent) {
    switch (intent) {
      case KeyIntent.moveDown:
        _moveCursor(1);
      case KeyIntent.moveUp:
        _moveCursor(-1);
      case KeyIntent.top:
        _jumpTo(0);
      case KeyIntent.bottom:
        _jumpTo(_rows.length - 1);
      case KeyIntent.openOrExpand:
      case KeyIntent.activate:
        _activateCurrent();
      case KeyIntent.collapseOrParent:
        _collapseCurrent();
      case KeyIntent.addEntity:
        _addCurrent();
      case KeyIntent.editItem:
        _editCurrent();
      case KeyIntent.search:
        _focusSearch();
      case KeyIntent.back:
        widget.onBack();
      case KeyIntent.focusTracker:
        widget.onFocusTracker?.call();
      case KeyIntent.focusPanel:
        widget.onFocusPanel?.call();
      default:
        return false; // bubble to the shell
    }
    return true;
  }

  _Section? _sectionAtCursor() {
    if (_cursor >= _rows.length) return null;
    final row = _rows[_cursor];
    if (row is _HeaderRow) return row.section;
    if (row is _EntityRow) return row.section;
    if (row is _ActionRow) return _Section.general;
    return null;
  }

  void _addCurrent() {
    final s = _sectionAtCursor();
    if (s != null) _addFor(s)?.call();
  }

  void _editCurrent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is _EntityRow && _editableSection(row.section)) {
      _edit(row.section, row.id, startEditing: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _cursorNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          // Search replaces the old "← Settings" title bar on both layouts. The
          // page-header Tracker/Settings switch (wide) and the bottom nav
          // (narrow) handle section navigation; Esc still fires onBack.
          PanelSearchField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: (v) => setState(() {
              _query = v;
              _cursor = 0;
            }),
            onClear: _query.isEmpty ? null : _clearSearch,
            onEscape: () => _cursorNode.requestFocus(),
          ),
          Expanded(
            child: StreamBuilder<List<InvoiceTemplate>>(
              stream: _templates,
              builder: (context, templateSnap) {
                return StreamBuilder<List<InvoiceProfile>>(
                  stream: _profiles,
                  builder: (context, profileSnap) {
                    _latestTemplates = templateSnap.data ?? const [];
                    _latestProfiles = profileSnap.data ?? const [];
                    return _buildList(
                      templates: _latestTemplates,
                      profiles: _latestProfiles,
                    );
                  },
                );
              },
            ),
          ),
          if (widget.showFooter &&
              (widget.onShowHelp != null ||
                  widget.onOpenSettings != null ||
                  widget.onOpenTracker != null))
            PanelFooter(
              onShowHelp: widget.onShowHelp,
              onOpenSettings: widget.onOpenSettings,
              onOpenTracker: widget.onOpenTracker,
              settingsActive: widget.settingsActive,
            ),
          const CraftoxBadge(),
        ],
      ),
    );
  }

  // The searchable text of an item row (headers aren't matched directly).
  String _rowLabel(_BRow r) => switch (r) {
    _EntityRow(:final name) => name,
    _ActionRow(:final label) => label,
    _ => '',
  };

  Widget _buildList({
    required List<InvoiceTemplate> templates,
    required List<InvoiceProfile> profiles,
  }) {
    final q = _query.trim().toLowerCase();
    _searching = q.isNotEmpty;
    bool matches(String label) => label.toLowerCase().contains(q);

    List<_BRow> items(_Section s) {
      final all = switch (s) {
        _Section.templates => [
          for (final x in templates)
            _EntityRow(s, id: x.id, name: x.name, isDefault: x.isDefault),
        ],
        _Section.profiles => [
          for (final x in profiles)
            _EntityRow(s, id: x.id, name: x.name, isDefault: x.isDefault),
        ],
        _Section.general => _actionRows(),
      };
      if (!_searching) return all;
      return all.where((r) => matches(_rowLabel(r))).toList();
    }

    final rows = <_BRow>[];
    for (final s in _Section.values) {
      final sectionItems = items(s);
      // Hide a section with no items: General is hidden whenever empty, and any
      // section is hidden while searching if nothing under it matches.
      if (sectionItems.isEmpty && (s == _Section.general || _searching)) {
        continue;
      }
      // An active query force-expands every surviving section so matches show.
      final expanded = _searching || _expanded.contains(s);
      rows.add(
        _HeaderRow(s, expanded: expanded, hasItems: sectionItems.isNotEmpty),
      );
      if (expanded) rows.addAll(sectionItems);
    }
    _rows = rows;
    if (_cursor >= _rows.length) _cursor = _rows.isEmpty ? 0 : _rows.length - 1;

    if (_searching && _rows.isEmpty) {
      return PanelEmptyNote('No settings match "${_query.trim()}".');
    }

    final cursorActive = _cursorNode.hasPrimaryFocus;
    return ListView.builder(
      padding: panelListPadding,
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
              singularLabel: _sectionSingular(row.section),
              expanded: row.expanded,
              hasItems: row.hasItems,
              onTap: () {
                setState(() => _cursor = i);
                if (row.hasItems) _toggleSection(row.section);
              },
              onAdd: _addFor(row.section) == null
                  ? null
                  : () {
                      setState(() => _cursor = i);
                      _addFor(row.section)!.call();
                    },
            ),
            _EntityRow() => _EntityTile(
              name: row.name,
              isDefault: row.isDefault,
              selected: switch (row.section) {
                _Section.templates => row.id == widget.selectedTemplateId,
                _Section.profiles => row.id == widget.selectedProfileId,
                _Section.general => false,
              },
              onTap: () {
                setState(() => _cursor = i);
                _edit(row.section, row.id);
              },
              // Entering edit mode is now a control on the entity's own
              // page (the row just opens it, read-only, via onTap), so a
              // second edit-icon trigger on the row would be redundant.
              onEdit: null,
            ),
            _ActionRow() => _ActionTile(
              label: row.label,
              icon: row.icon,
              onTap: () {
                setState(() => _cursor = i);
                row.onTap();
              },
            ),
          },
        );
        final dividerBefore = i > 0 && row is _HeaderRow;
        // Breathing space after a section's last row — matches SidePanel's
        // gap after a client's last project.
        final lastOfSection =
            (row is _EntityRow || row is _ActionRow) &&
            (i + 1 >= _rows.length || _rows[i + 1] is _HeaderRow);
        return panelGroupItem(
          dividerBefore: dividerBefore,
          spacerAfter: lastOfSection,
          child: tile,
        );
      },
    );
  }
}

class _SectionHeaderTile extends StatelessWidget {
  const _SectionHeaderTile({
    required this.label,
    required this.singularLabel,
    required this.expanded,
    required this.hasItems,
    required this.onTap,
    this.onAdd,
  });
  final String label;
  final String singularLabel;
  final bool expanded;
  final bool hasItems;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return panelGroupHeaderTile(
      context: context,
      onTap: onTap,
      leading: Icon(
        expanded ? Icons.expand_more : Icons.chevron_right,
        size: AppTokens.iconMd,
        color: expanded
            ? t.colorScheme.primary
            : t.colorScheme.onSurfaceVariant,
      ),
      title: Text(label, style: t.extension<AppTextStyles>()!.sectionHeader),
      // A lone trailing icon, same as an entity row's edit icon — both flush
      // to the tile's right inset, so the `+` lines up in the same column as
      // the rows' edit icons below it (unlike the client header in the
      // tracker panel, there's no header-level second action to reserve
      // space for here).
      trailing: onAdd == null
          ? null
          : appIconButton(
              icon: Icons.add,
              iconSize: AppTokens.iconMd,
              tooltip: 'Add $singularLabel (a)',
              onPressed: onAdd,
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
    this.onEdit,
  });
  final String name;
  final bool isDefault;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return panelRowTile(
      context: context,
      selected: selected,
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.extension<AppTextStyles>()!.rowTitleSmall,
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
      trailing: onEdit == null
          ? null
          : appIconButton(
              icon: Icons.edit_note,
              iconSize: AppTokens.iconMd,
              tooltip: 'Edit (e)',
              onPressed: onEdit,
            ),
      onTap: onTap,
    );
  }
}

/// A General-section command row: a leading icon + label, indented under its
/// header like an entity row. No default badge, no edit affordance.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return panelRowTile(
      context: context,
      horizontalTitleGap: AppTokens.spaceXs,
      leading: Icon(
        icon,
        size: AppTokens.iconSm,
        color: t.colorScheme.onSurfaceVariant,
      ),
      title: Text(label, style: t.extension<AppTextStyles>()!.rowTitleSmall),
      onTap: onTap,
    );
  }
}
