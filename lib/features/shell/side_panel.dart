import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/panel.dart';
import 'package:timedart/features/shell/keymap.dart';
import 'package:timedart/features/shell/panel_rows.dart';
import 'package:timedart/widgets/focus_ring.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timedart/widgets/tap_target.dart';

class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.db,
    this.selectedProjectId,
    this.onSelect,
    required this.onEditProject,
    required this.onAddProject,
    required this.onEditClient,
    required this.onAddClient,
    this.cursorFocusNode,
    this.searchFocusNode,
    this.onFocusTracker,
    this.onFocusPanel,
    this.onShowHelp,
    this.onOpenSettings,
    this.onOpenTracker,
    this.settingsActive = false,
    this.showFooter = true,
    this.autofocus = false,
  });
  final AppDatabase db;
  final String? selectedProjectId;
  final void Function(String)? onSelect; // select a project for the timer
  final void Function(Project) onEditProject;
  final void Function(String clientId)
  onAddProject; // add a project under this client
  final void Function(Client) onEditClient;
  final VoidCallback onAddClient;
  // Row-cursor focus, owned by the shell so it can move focus *into* the panel.
  // Null in layouts without keyboard nav (drawer) — an internal node is used.
  final FocusNode? cursorFocusNode;
  // Search-field focus, owned by the shell so a global `/` (from any pane) can
  // jump straight into search. Null → an internal node (drawer layout).
  final FocusNode? searchFocusNode;
  // Pane-switch intents, forwarded to the shell's focus methods (the panel
  // sits on the right, so focusTracker leaves left, focusPanel is a refocus).
  // Null in layouts without keyboard nav (drawer).
  final VoidCallback? onFocusTracker;
  final VoidCallback? onFocusPanel;
  // `?` (Shift+/) — open the shortcuts help. Routed up because the panel
  // consumes the `/` key itself (so it can't bubble to the shell).
  final VoidCallback? onShowHelp;
  // Open App Settings. Shown as a gear in the panel footer.
  final VoidCallback? onOpenSettings;
  // Go to the tracker. Shown as the timedart symbol beside the footer gear.
  final VoidCallback? onOpenTracker;
  // Whether Settings is the active section (drives the footer switch tint).
  final bool settingsActive;
  // Render the base-of-panel footer (Shortcuts/Settings). False in the wide
  // layout, where those actions live in the header instead. onShowHelp is still
  // honoured for `?`-key routing regardless.
  final bool showFooter;
  // Take the row cursor on first build (wide layout, where keys are live).
  final bool autofocus;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  // Reassigned when "Show archived" flips (StreamBuilder re-subscribes on the
  // new instance), so archived clients/projects come and go from the list.
  late Stream<List<Client>> _clientsStream = widget.db.watchClients();
  late Stream<List<Project>> _projectsStream = widget.db.watchProjects();
  bool _showArchived = false;
  final _searchController = TextEditingController();
  FocusNode? _internalSearch;
  FocusNode get _searchFocus =>
      widget.searchFocusNode ?? (_internalSearch ??= FocusNode());
  String _query = '';

  // Manually expanded clients. Selecting a project seeds its client here once (so
  // it opens but can still be collapsed); searching force-expands everything
  // at the effective-expansion layer without touching this set.
  final Set<String> _expanded = {};
  String?
  _seededSelection; // selectedProjectId we last auto-expanded a client for

  // Row cursor over the flattened visible list (clients + projects of expanded
  // clients). Kept valid against [_rows] after every rebuild.
  int _cursor = 0;
  final _chords = ChordDetector(); // gg / Ctrl-w window-motion sequence state
  List<PanelRow> _rows = const [];
  bool _searching = false;
  final _cursorKey = GlobalKey(); // rides the focused row for ensureVisible
  final _scroll = ScrollController();
  static const _estRowHeight = 40.0; // rough row height for off-screen jumps

  FocusNode? _internalFocus;
  FocusNode get _cursorNode =>
      widget.cursorFocusNode ?? (_internalFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    // Repaint the focus indicator as the cursor gains/loses primary focus.
    _cursorNode.addListener(_onFocusChanged);
    // Select-all whenever the search field gains focus, so typing replaces a
    // stale query. Lives on the node (not just the local `/` path) so the
    // shell's global `/` gets the same behaviour.
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

  void _onFocusChanged() {
    // A focus excursion (into search, out to the tracker) abandons any
    // half-typed sequence — otherwise it would mis-fire on the next keypress.
    _chords.reset();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cursorNode.removeListener(_onFocusChanged);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _internalFocus?.dispose();
    _internalSearch?.dispose();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _cursor = 0;
    });
  }

  void _toggleShowArchived() => setState(() {
    _showArchived = !_showArchived;
    _clientsStream = widget.db.watchClients(includeArchived: _showArchived);
    _projectsStream = widget.db.watchProjects(includeArchived: _showArchived);
  });

  String? _selectedClientId(List<Project> projects) {
    for (final j in projects) {
      if (j.id == widget.selectedProjectId) return j.clientId;
    }
    return null;
  }

  int? _indexOfClient(String clientId) {
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      if (r is ClientRow && r.clientId == clientId) return i;
    }
    return null;
  }

  // --- Cursor movement ---
  void _moveCursor(int delta) {
    if (_rows.isEmpty) return;
    final next = (_cursor + delta).clamp(0, _rows.length - 1);
    if (next != _cursor) {
      setState(() => _cursor = next);
      _ensureVisible();
    }
  }

  void _jumpTo(int index) {
    if (_rows.isEmpty) return;
    final next = index.clamp(0, _rows.length - 1);
    if (next != _cursor) {
      setState(() => _cursor = next);
      _ensureVisible();
    }
  }

  // n / N: hop to the next/previous project row (reads best while searching).
  void _jumpMatch(int dir) {
    for (var i = _cursor + dir; i >= 0 && i < _rows.length; i += dir) {
      if (_rows[i] is ProjectRow) {
        _jumpTo(i);
        return;
      }
    }
  }

  // e : edit the focused row (client or project) — mirrors the tracker's `e`.
  void _editCurrent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is ClientRow) {
      widget.onEditClient(row.client);
    } else if (row is ProjectRow) {
      widget.onEditProject(row.project);
    }
  }

  void _expandOrOpen() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is ClientRow) {
      if (!row.expanded && row.hasProjects) {
        setState(() => _expanded.add(row.clientId));
        _ensureVisible();
      } else if (row.expanded && row.hasProjects) {
        _moveCursor(1); // step into the first project
      }
    } else if (row is ProjectRow) {
      widget.onSelect?.call(row.project.id); // open == a click
    }
  }

  void _collapseOrParent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is ClientRow) {
      // Searching forces every client open, so collapse is a no-op then.
      if (row.expanded && !_searching) {
        setState(() => _expanded.remove(row.clientId));
      }
    } else if (row is ProjectRow) {
      final idx = _indexOfClient(row.clientId);
      if (idx != null) _jumpTo(idx);
    }
  }

  // Mouse and keyboard share the one expansion set.
  void _toggleClient(String clientId) {
    setState(() {
      if (_expanded.contains(clientId)) {
        _expanded.remove(clientId);
      } else {
        _expanded.add(clientId);
      }
      final i = _indexOfClient(clientId);
      if (i != null) _cursor = i;
    });
  }

  // Select-all happens in _onSearchFocusChanged (fires for this and the shell's
  // global `/` alike).
  void _focusSearch() => _searchFocus.requestFocus();

  void _ensureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cursorKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
        );
        return;
      }
      // The row isn't laid out (ListView.builder skips off-screen items), so
      // ensureVisible has nothing to target — e.g. G / gg jumping far. Jump to
      // an estimated offset to bring the row into range, then refine next frame
      // once it's actually built.
      if (!_scroll.hasClients) return;
      final approx = (_cursor * _estRowHeight).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(approx);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final refined = _cursorKey.currentContext;
        if (refined != null) {
          Scrollable.ensureVisible(refined, alignment: 0.5);
        }
      });
    });
  }

  // Panel scope = list nav + panel actions + the global pane-switch bindings.
  // The panel owns its Ctrl-w chord (and search/help) locally because it owns
  // the h/l keys that complete/shadow it; pane switching is forwarded to the
  // shell. Everything else (Tab, Space, t, Ctrl-,) bubbles.
  static const _scopes = {KeyScope.list, KeyScope.panel, KeyScope.global};

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // While typing in the search field, keys belong to the field.
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
        // Movement repeats when held; everything else fires once per press.
        if (event is! KeyDownEvent && !Keymap.isRepeatable(intent)) {
          return KeyEventResult.ignored;
        }
        return _handleIntent(intent)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
    }
  }

  // Maps a resolved intent to this panel's action; returns false for intents it
  // doesn't own (Tab / Space / t / Ctrl-,) so the shell handles them.
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
        _expandOrOpen();
      case KeyIntent.collapseOrParent:
        _collapseOrParent();
      case KeyIntent.editItem:
        _editCurrent();
      case KeyIntent.addProject:
        _addProjectCurrent();
      case KeyIntent.addClient:
        widget.onAddClient();
      case KeyIntent.nextMatch:
        _jumpMatch(1);
      case KeyIntent.prevMatch:
        _jumpMatch(-1);
      case KeyIntent.search:
        _focusSearch();
      case KeyIntent.showHelp:
        widget.onShowHelp?.call();
      case KeyIntent.focusTracker:
        widget.onFocusTracker?.call();
      case KeyIntent.focusPanel:
        widget.onFocusPanel?.call();
      default:
        return false; // bubble to the shell
    }
    return true;
  }

  // A : add a project under the focused row's client (client or project row).
  void _addProjectCurrent() {
    if (_cursor >= _rows.length) return;
    widget.onAddProject(_rows[_cursor].clientId);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _cursorNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          PanelSearchField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: (v) => setState(() {
              _query = v;
              _cursor = 0;
            }),
            onClear: _query.isEmpty ? null : _clearSearch,
            // Esc returns focus to the row cursor.
            onEscape: () => _cursorNode.requestFocus(),
            trailing: appIconButton(
              icon: Icons.add,
              iconSize: AppTokens.iconMd,
              tooltip: 'Add client (A)',
              onPressed: widget.onAddClient,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Client>>(
              stream: _clientsStream,
              builder: (context, clientSnap) {
                final clients = clientSnap.data ?? [];
                return StreamBuilder<List<Project>>(
                  stream: _projectsStream,
                  builder: (context, projectSnap) {
                    final projects = projectSnap.data ?? [];
                    return _buildList(clients, projects);
                  },
                );
              },
            ),
          ),
          _ShowArchivedToggle(
            showing: _showArchived,
            onTap: _toggleShowArchived,
          ),
          // Lift the toggle off the bottom edge on mobile so it's clearer and
          // easier to reach; desktop keeps it snug above the footer/badge.
          if (context.isNarrow) const SizedBox(height: AppTokens.spaceMd),
          // A quiet footer at the base: an App Settings gear (drawer layout).
          // In the wide layout it's suppressed — those actions sit in the header.
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

  Widget _buildList(List<Client> clients, List<Project> projects) {
    // Drop expansion state for clients that no longer exist (deleted).
    final clientIds = clients.map((c) => c.id).toSet();
    _expanded.removeWhere((id) => !clientIds.contains(id));

    // Seed the selected project's client into the expansion set once per selection
    // change, so it opens on select but stays collapsible afterwards.
    if (widget.selectedProjectId != _seededSelection) {
      _seededSelection = widget.selectedProjectId;
      final selectedClientId = _selectedClientId(projects);
      if (selectedClientId != null) _expanded.add(selectedClientId);
    }

    _searching = _query.trim().isNotEmpty;
    // Searching force-expands every visible client; otherwise the set decides.
    bool effectiveExpanded(String clientId) =>
        _searching || _expanded.contains(clientId);

    _rows = buildPanelRows(
      clients: clients,
      projects: projects,
      query: _query,
      isExpanded: effectiveExpanded,
    );
    if (_cursor >= _rows.length) {
      _cursor = _rows.isEmpty ? 0 : _rows.length - 1;
    }

    if (clients.isEmpty) {
      return const PanelEmptyNote('No clients yet — add one above.');
    }
    if (_rows.isEmpty) {
      return PanelEmptyNote('No matches for "${_query.trim()}".');
    }

    final cursorActive = _cursorNode.hasPrimaryFocus;
    return ListView.builder(
      controller: _scroll,
      padding: panelListPadding,
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final row = _rows[i];
        final focused = i == _cursor && cursorActive;
        final key = i == _cursor ? _cursorKey : null;
        // Archived rows (only visible while "Show archived" is on) read dimmed —
        // a project is archived-context if it or its client is archived.
        final archived = switch (row) {
          ClientRow() => row.client.archivedAt != null,
          ProjectRow() =>
            row.project.archivedAt != null || row.client.archivedAt != null,
        };
        final tile = FocusRing(
          focused: focused,
          edgesOnly: true, // top/bottom rules only, matching the entry list
          child: switch (row) {
            ClientRow() => _ClientHeaderTile(
              key: key,
              client: row.client,
              expanded: row.expanded,
              onToggle: () => _toggleClient(row.clientId),
              onAddProject: () => widget.onAddProject(row.clientId),
              onEditClient: () => widget.onEditClient(row.client),
            ),
            ProjectRow() => ProjectRowItem(
              key: key,
              project: row.project,
              isSelected: row.project.id == widget.selectedProjectId,
              onTap: () => widget.onSelect?.call(row.project.id),
              onEdit: () => widget.onEditProject(row.project),
            ),
          },
        );

        final display = archived ? Opacity(opacity: 0.5, child: tile) : tile;

        // A divider above each client group (except the first), and breathing
        // space after a client's last project — the visual grouping ExpansionTile
        // used to provide.
        final dividerBefore = i > 0 && row is ClientRow;
        final lastProjectOfClient =
            row is ProjectRow &&
            (i + 1 >= _rows.length || _rows[i + 1] is ClientRow);
        return panelGroupItem(
          dividerBefore: dividerBefore,
          spacerAfter: lastProjectOfClient,
          child: display,
        );
      },
    );
  }
}

// A deliberately low-key control at the base of the list: reveals/hides archived
// clients & projects (#246). Off by default; a plain muted text row, not a
// prominent switch, so it stays out of the way until wanted.
class _ShowArchivedToggle extends StatelessWidget {
  const _ShowArchivedToggle({required this.showing, required this.onTap});
  final bool showing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: context.isNarrow ? AppTokens.spaceSm : AppTokens.spaceXs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              showing ? Icons.visibility_off_outlined : Icons.archive_outlined,
              size: AppTokens.iconSm,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.spaceXs),
            Text(
              showing ? 'Hide archived' : 'Show archived',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: AppTokens.fontSizeSm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Client header: chevron + name + add/edit, tap toggles expansion ---
class _ClientHeaderTile extends StatelessWidget {
  final Client client;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddProject;
  final VoidCallback onEditClient;

  const _ClientHeaderTile({
    super.key,
    required this.client,
    required this.expanded,
    required this.onToggle,
    required this.onAddProject,
    required this.onEditClient,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return panelGroupHeaderTile(
      context: context,
      onTap: onToggle,
      leading: Icon(
        expanded ? Icons.expand_more : Icons.chevron_right,
        size: AppTokens.iconMd,
        color: expanded
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        client.name,
        style: theme.extension<AppTextStyles>()!.rowTitle,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          appIconButton(
            icon: Icons.add,
            tooltip: 'Add project (a)',
            onPressed: onAddProject,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          // Edit sits rightmost, aligning with the project rows' edit icon.
          appIconButton(
            icon: Icons.edit_note,
            iconSize: AppTokens.iconMd,
            tooltip: 'Edit client (e)',
            onPressed: onEditClient,
          ),
        ],
      ),
    );
  }
}

// --- Project row ---
class ProjectRowItem extends StatelessWidget {
  final Project project;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const ProjectRowItem({
    super.key,
    required this.project,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return panelRowTile(
      context: context,
      selected: isSelected,
      title: Text(
        project.code == null
            ? project.title
            : '${project.code} - ${project.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).extension<AppTextStyles>()!.rowTitleSmall,
      ),
      trailing: appIconButton(
        icon: Icons.edit_note,
        iconSize: AppTokens.iconMd,
        tooltip: 'Edit project (e)',
        onPressed: onEdit,
      ),
      onTap: onTap,
    );
  }
}

// Base-of-panel Craftox badge — a small linked logo, always present regardless
// of layout/panel mode (unlike PanelFooter, which the wide layout suppresses
// in favour of the header). Public so the settings panel shows it too.
class CraftoxBadge extends StatelessWidget {
  const CraftoxBadge({super.key});

  static final _uri = Uri.parse('https://craftox-labs.github.io');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(
          height: AppTokens.strokeThin,
          thickness: AppTokens.strokeThin,
          color: AppTokens.colorBorder,
        ),
        SizedBox(
          width: double.infinity,
          child: InkWell(
            onTap: () => launchUrl(_uri),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
              child: Center(
                child: SvgPicture.asset(
                  'assets/logo/co_logo_horizontal.svg',
                  height: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
