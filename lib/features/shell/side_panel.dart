import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/text_styles.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/shell/panel_rows.dart';
import 'package:time_tracker/widgets/focus_ring.dart';
import 'package:url_launcher/url_launcher.dart';

class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.db,
    this.selectedJobId,
    this.onSelect,
    required this.onEditJob,
    required this.onAddJob,
    required this.onEditClient,
    required this.onAddClient,
    this.cursorFocusNode,
    this.searchFocusNode,
    this.onExitToTracker,
    this.onShowHelp,
    this.onOpenSettings,
    this.showFooter = true,
    this.autofocus = false,
  });
  final AppDatabase db;
  final int? selectedJobId;
  final void Function(int)? onSelect; // select a job for the timer
  final void Function(Job) onEditJob;
  final void Function(int clientId) onAddJob; // add a job under this client
  final void Function(Client) onEditClient;
  final VoidCallback onAddClient;
  // Row-cursor focus, owned by the shell so it can move focus *into* the panel.
  // Null in layouts without keyboard nav (drawer) — an internal node is used.
  final FocusNode? cursorFocusNode;
  // Search-field focus, owned by the shell so a global `/` (from any pane) can
  // jump straight into search. Null → an internal node (drawer layout).
  final FocusNode? searchFocusNode;
  // Called when the user asks to leave the panel for the tracker pane
  // (Tab / Ctrl-l / Ctrl-w l). Null when there's nowhere to go.
  final VoidCallback? onExitToTracker;
  // `?` (Shift+/) — open the shortcuts help. Routed up because the panel
  // consumes the `/` key itself (so it can't bubble to the shell).
  final VoidCallback? onShowHelp;
  // Open App Settings (Branding mode). Shown as a gear in the panel footer.
  final VoidCallback? onOpenSettings;
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
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();
  late final Stream<List<Job>> _jobsStream = widget.db.watchJobs();
  final _searchController = TextEditingController();
  FocusNode? _internalSearch;
  FocusNode get _searchFocus =>
      widget.searchFocusNode ?? (_internalSearch ??= FocusNode());
  String _query = '';

  // Manually expanded clients. Selecting a job seeds its client here once (so
  // it opens but can still be collapsed); searching force-expands everything
  // at the effective-expansion layer without touching this set.
  final Set<int> _expanded = {};
  int? _seededSelection; // selectedJobId we last auto-expanded a client for

  // Row cursor over the flattened visible list (clients + jobs of expanded
  // clients). Kept valid against [_rows] after every rebuild.
  int _cursor = 0;
  bool _pendingG = false; // saw the first `g` of a `gg`
  bool _pendingChord = false; // saw Ctrl-w, awaiting an h/l window motion
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
    _pendingG = false;
    _pendingChord = false;
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

  int? _selectedClientId(List<Job> jobs) {
    for (final j in jobs) {
      if (j.id == widget.selectedJobId) return j.clientId;
    }
    return null;
  }

  int? _indexOfClient(int clientId) {
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

  // n / N: hop to the next/previous job row (reads best while searching).
  void _jumpMatch(int dir) {
    for (var i = _cursor + dir; i >= 0 && i < _rows.length; i += dir) {
      if (_rows[i] is JobRow) {
        _jumpTo(i);
        return;
      }
    }
  }

  // e : edit the focused row (client or job) — mirrors the tracker's `e`.
  void _editCurrent() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is ClientRow) {
      widget.onEditClient(row.client);
    } else if (row is JobRow) {
      widget.onEditJob(row.job);
    }
  }

  void _expandOrOpen() {
    if (_cursor >= _rows.length) return;
    final row = _rows[_cursor];
    if (row is ClientRow) {
      if (!row.expanded && row.hasJobs) {
        setState(() => _expanded.add(row.clientId));
        _ensureVisible();
      } else if (row.expanded && row.hasJobs) {
        _moveCursor(1); // step into the first job
      }
    } else if (row is JobRow) {
      widget.onSelect?.call(row.job.id); // open == a click
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
    } else if (row is JobRow) {
      final idx = _indexOfClient(row.clientId);
      if (idx != null) _jumpTo(idx);
    }
  }

  // Mouse and keyboard share the one expansion set.
  void _toggleClient(int clientId) {
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // While typing in the search field, keys belong to the field.
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final right =
        key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.arrowRight;
    final left =
        key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.arrowLeft;

    // --- Pane switching (leave for the tracker) ---
    // Handled here rather than left to bubble, because the bare l/h row-nav
    // keys below would otherwise shadow both the Ctrl-combo and the Ctrl-w
    // chord's second key. Only the panel→tracker direction lives here; the
    // shell owns tracker→panel. The panel sits on the RIGHT, so leaving for the
    // tracker means moving left (Ctrl-h / Ctrl-← / Ctrl-w h).
    if (event is KeyDownEvent) {
      if (ctrl && key == LogicalKeyboardKey.keyW) {
        _pendingChord = true;
        return KeyEventResult.handled;
      }
      if (_pendingChord) {
        _pendingChord = false;
        if (left) {
          widget.onExitToTracker?.call();
          return KeyEventResult.handled;
        }
        if (right) return KeyEventResult.handled; // Ctrl-w l → panel; already here
        // any other key: abandon the chord, fall through to normal handling
      } else {
        if (ctrl && left) {
          widget.onExitToTracker?.call();
          return KeyEventResult.handled;
        }
        if (ctrl && right) return KeyEventResult.handled; // Ctrl-l → already here
      }
    }
    // Any other Ctrl-combo isn't a row-nav key — let it bubble (Tab and the
    // tracker→panel bindings are the shell's job).
    if (ctrl) return KeyEventResult.ignored;

    // Movement repeats when held.
    if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowDown) {
      _moveCursor(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowUp) {
      _moveCursor(-1);
      return KeyEventResult.handled;
    }

    // The rest fire once per press.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // gg / G — handle before the pending-g reset below.
    if (key == LogicalKeyboardKey.keyG) {
      if (shift) {
        _pendingG = false;
        _jumpTo(_rows.length - 1);
      } else if (_pendingG) {
        _pendingG = false;
        _jumpTo(0);
      } else {
        _pendingG = true;
      }
      return KeyEventResult.handled;
    }
    _pendingG = false; // any other key breaks a half-typed gg

    if (right ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _expandOrOpen();
      return KeyEventResult.handled;
    }
    if (left) {
      _collapseOrParent();
      return KeyEventResult.handled;
    }
    // `?` = help (matched by character — a shifted `/` isn't reported as the
    // slash logical key); plain `/` = search.
    if (event.character == '?') {
      widget.onShowHelp?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.slash) {
      _focusSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      _jumpMatch(shift ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyE) {
      _editCurrent();
      return KeyEventResult.handled;
    }
    // a = add job under the focused row's client; A = add client.
    if (key == LogicalKeyboardKey.keyA) {
      if (shift) {
        widget.onAddClient();
      } else {
        _addJobCurrent();
      }
      return KeyEventResult.handled;
    }
    // Tab is left for the shell (tracker↔panel toggle) — don't consume.
    return KeyEventResult.ignored;
  }

  // A : add a job under the focused row's client (client or job row).
  void _addJobCurrent() {
    if (_cursor >= _rows.length) return;
    widget.onAddJob(_rows[_cursor].clientId);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _cursorNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          _SearchHeader(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: (v) => setState(() {
              _query = v;
              _cursor = 0;
            }),
            onClear: _query.isEmpty ? null : _clearSearch,
            onAddClient: widget.onAddClient,
            // Esc returns focus to the row cursor.
            onEscape: () => _cursorNode.requestFocus(),
          ),
          Expanded(
            child: StreamBuilder<List<Client>>(
              stream: _clientsStream,
              builder: (context, clientSnap) {
                final clients = clientSnap.data ?? [];
                return StreamBuilder<List<Job>>(
                  stream: _jobsStream,
                  builder: (context, jobSnap) {
                    final jobs = jobSnap.data ?? [];
                    return _buildList(clients, jobs);
                  },
                );
              },
            ),
          ),
          // A quiet footer at the base: an App Settings gear (drawer layout).
          // In the wide layout it's suppressed — those actions sit in the header.
          if (widget.showFooter &&
              (widget.onShowHelp != null || widget.onOpenSettings != null))
            PanelFooter(
              onShowHelp: widget.onShowHelp,
              onOpenSettings: widget.onOpenSettings,
            ),
          const CraftoxBadge(),
        ],
      ),
    );
  }

  Widget _buildList(List<Client> clients, List<Job> jobs) {
    // Drop expansion state for clients that no longer exist (deleted).
    final clientIds = clients.map((c) => c.id).toSet();
    _expanded.removeWhere((id) => !clientIds.contains(id));

    // Seed the selected job's client into the expansion set once per selection
    // change, so it opens on select but stays collapsible afterwards.
    if (widget.selectedJobId != _seededSelection) {
      _seededSelection = widget.selectedJobId;
      final selectedClientId = _selectedClientId(jobs);
      if (selectedClientId != null) _expanded.add(selectedClientId);
    }

    _searching = _query.trim().isNotEmpty;
    // Searching force-expands every visible client; otherwise the set decides.
    bool effectiveExpanded(int clientId) =>
        _searching || _expanded.contains(clientId);

    _rows = buildPanelRows(
      clients: clients,
      jobs: jobs,
      query: _query,
      isExpanded: effectiveExpanded,
    );
    if (_cursor >= _rows.length) {
      _cursor = _rows.isEmpty ? 0 : _rows.length - 1;
    }

    if (clients.isEmpty) {
      return const _EmptyNote('No clients yet — add one above.');
    }
    if (_rows.isEmpty) {
      return _EmptyNote('No matches for "${_query.trim()}".');
    }

    final cursorActive = _cursorNode.hasPrimaryFocus;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space4xs),
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final row = _rows[i];
        final focused = i == _cursor && cursorActive;
        final key = i == _cursor ? _cursorKey : null;
        final tile = FocusRing(
          focused: focused,
          edgesOnly: true, // top/bottom rules only, matching the entry list
          child: switch (row) {
            ClientRow() => _ClientHeaderTile(
              key: key,
              client: row.client,
              expanded: row.expanded,
              onToggle: () => _toggleClient(row.clientId),
              onAddJob: () => widget.onAddJob(row.clientId),
              onEditClient: () => widget.onEditClient(row.client),
            ),
            JobRow() => JobRowItem(
              key: key,
              job: row.job,
              isSelected: row.job.id == widget.selectedJobId,
              onTap: () => widget.onSelect?.call(row.job.id),
              onEdit: () => widget.onEditJob(row.job),
            ),
          },
        );

        // A divider above each client group (except the first), and breathing
        // space after a client's last job — the visual grouping ExpansionTile
        // used to provide.
        final dividerBefore = i > 0 && row is ClientRow;
        final lastJobOfClient =
            row is JobRow && (i + 1 >= _rows.length || _rows[i + 1] is ClientRow);
        if (!dividerBefore && !lastJobOfClient) return tile;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dividerBefore)
              const Divider(
                height: AppTokens.strokeThin,
                thickness: AppTokens.strokeThin,
                color: AppTokens.colorBorder,
              ),
            tile,
            if (lastJobOfClient) const SizedBox(height: AppTokens.spaceSm),
          ],
        );
      },
    );
  }
}

// A subtle inset ring on the keyboard-focused row — deliberately distinct from
// the green *selected*-job tint so both can show at once.
// --- Search field + Add-client button, pinned to the top of the panel ---
class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear; // null when there's nothing to clear
  final VoidCallback onAddClient;
  final VoidCallback onEscape;

  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onAddClient,
    required this.onEscape,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Square left corners so the field sits flush to the panel border;
    // rounded on the right only.
    const fieldRadius = BorderRadius.horizontal(
      right: Radius.circular(AppTokens.radiusSm),
    );
    return Padding(
      // Left flush to the border; right inset matches the rows so the
      // Add-client + lands in the edit-button column. Top matches the content
      // pane's spaceLg inset so both panes start at the same height.
      padding: const EdgeInsets.fromLTRB(
        0,
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceLg,
      ),
      child: Row(
        children: [
          Expanded(
            // Esc blurs the field and hands focus back to the row cursor.
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): onEscape,
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: AppTokens.fontSizeSm),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  // Filled, no stroke: the fill gives the flush-left /
                  // rounded-right shape, so there's no left border to leave a
                  // hair against the panel edge.
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  // Icon aligned with the client chevron (~spaceMd from edge).
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(
                      left: AppTokens.spaceMd,
                      right: AppTokens.spaceXs,
                    ),
                    child: Icon(Icons.search, size: AppTokens.iconSm),
                  ),
                  prefixIconConstraints: const BoxConstraints(minHeight: 36),
                  // Same cap as the prefix so the field height doesn't jump when
                  // the clear button appears on input.
                  suffixIconConstraints: const BoxConstraints(minHeight: 36),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: fieldRadius,
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: fieldRadius,
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: onClear == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: AppTokens.iconSm),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Clear search',
                          onPressed: onClear,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          // Tight, like the row edit buttons, so centres align in a column.
          IconButton(
            icon: const Icon(Icons.add),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Add client (A)',
            onPressed: onAddClient,
          ),
        ],
      ),
    );
  }
}

// --- Small centred note for empty / no-match states ---
class _EmptyNote extends StatelessWidget {
  final String message;
  const _EmptyNote(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceXs,
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

// --- Client header: chevron + name + add/edit, tap toggles expansion ---
class _ClientHeaderTile extends StatelessWidget {
  final Client client;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddJob;
  final VoidCallback onEditClient;

  const _ClientHeaderTile({
    super.key,
    required this.client,
    required this.expanded,
    required this.onToggle,
    required this.onAddJob,
    required this.onEditClient,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      minTileHeight: 36,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
      ),
      horizontalTitleGap: AppTokens.space2xs,
      onTap: onToggle,
      leading: Icon(
        expanded ? Icons.expand_more : Icons.chevron_right,
        size: AppTokens.iconSm,
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
          IconButton(
            icon: const Icon(Icons.add),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Add job (a)',
            onPressed: onAddJob,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          // Edit sits rightmost, aligning with the job rows' edit icon.
          IconButton(
            icon: const Icon(Icons.edit_note),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit client (e)',
            onPressed: onEditClient,
          ),
        ],
      ),
    );
  }
}

// --- Job row ---
class JobRowItem extends StatelessWidget {
  final Job job;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const JobRowItem({
    super.key,
    required this.job,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      selected: isSelected,
      // Left indent under the client; right inset matches the client header
      // (spaceMd) so the action icons line up in a column. Tight vertical
      // padding keeps job rows close together.
      contentPadding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.space3xs,
        AppTokens.spaceMd,
        AppTokens.space3xs,
      ),
      title: Text(
        '${job.code} - ${job.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).extension<AppTextStyles>()!.rowTitleSmall,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_note),
        iconSize: AppTokens.iconMd,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: 'Edit job (e)',
        onPressed: onEdit,
      ),
      onTap: onTap,
    );
  }
}

// Base-of-panel footer: a `?` keycap + "Shortcuts" hint (opens the help modal),
// and an App Settings gear. Either half is shown only when its callback is set.
// Public so the branding panel shows the same footer.
class PanelFooter extends StatelessWidget {
  const PanelFooter({super.key, this.onShowHelp, this.onOpenSettings});
  final VoidCallback? onShowHelp;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(
          height: AppTokens.strokeThin,
          thickness: AppTokens.strokeThin,
          color: AppTokens.colorBorder,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: AppTokens.space3xs,
          ),
          child: Row(
            children: [
              if (onShowHelp != null)
                InkWell(
                  onTap: onShowHelp,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.spaceXs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.space2xs,
                            vertical: AppTokens.space4xs,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusSm,
                            ),
                            border: Border.all(color: AppTokens.colorBorder),
                          ),
                          child: Text(
                            '?',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceXs),
                        Text(
                          'Shortcuts',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              if (onOpenSettings != null)
                IconButton(
                  icon: const Icon(Icons.settings),
                  iconSize: AppTokens.iconMd,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Settings',
                  onPressed: onOpenSettings,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// Base-of-panel Craftox badge — a small linked logo, always present regardless
// of layout/panel mode (unlike PanelFooter, which the wide layout suppresses
// in favour of the header). Public so the branding panel shows it too.
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
              padding: const EdgeInsets.symmetric(
                vertical: AppTokens.spaceSm,
              ),
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
