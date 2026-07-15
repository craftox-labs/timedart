import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/backup.dart';
import 'package:timedart/util/save_file.dart';
import 'package:timedart/util/pick_file.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/shell/keymap.dart';
import 'package:timedart/features/shell/page_header.dart';
import 'package:timedart/features/shell/shortcuts_help.dart';
import 'package:timedart/features/shell/side_panel.dart';
import 'package:timedart/features/shell/settings_panel.dart';
import 'package:timedart/features/tracker/timer_view.dart';
import 'package:timedart/features/projects/project_form.dart';
import 'package:timedart/features/clients/client_form.dart';
import 'package:timedart/features/invoices/invoice_view.dart';
import 'package:timedart/features/invoices/editor_session.dart';
import 'package:timedart/features/invoices/profile_editor.dart';
import 'package:timedart/features/invoices/template_editor.dart';
import 'package:timedart/features/shell/settings_home.dart';
import 'package:timedart/widgets/confirm_dialog.dart';
import 'package:timedart/widgets/content_body.dart';
import 'package:timedart/widgets/sheet_grab_handle.dart';
import 'package:animations/animations.dart';

// What the detail pane is currently showing. One value instead of a pile of
// nullable flags, so the content is a single exhaustive switch.
sealed class _Detail {
  const _Detail();
}

class _Tracker extends _Detail {
  const _Tracker();
}

class _Invoice extends _Detail {
  final Project project;
  const _Invoice(this.project);
}

// App Settings home: the panel shows template/profile sections; the content
// pane is a placeholder until one is picked (see SettingsHome).
class _Settings extends _Detail {
  const _Settings();
}

// Editing (or creating, when the row is null) a template or profile in the content
// pane, with the settings panel still alongside.
class _TemplateEditorDetail extends _Detail {
  final InvoiceTemplate? template;
  final bool startEditing; // the 'e' shortcut skips straight past the view
  const _TemplateEditorDetail(this.template, {this.startEditing = false});
}

class _ProfileEditorDetail extends _Detail {
  final InvoiceProfile? profile;
  final bool startEditing;
  const _ProfileEditorDetail(this.profile, {this.startEditing = false});
}

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({
    super.key,
    required this.db,
    this.onRerunOnboarding,
    this.initialSelectedProjectId,
  });
  final AppDatabase db;
  // Settings → "Re-run setup": replays the first-run onboarding flow. Wired by
  // the root gate; null when the shell is mounted without one.
  final Future<void> Function()? onRerunOnboarding;
  // The project to select on the first frame. The root gate already resolves
  // the default project while bootstrapping, so passing it here avoids the
  // tracker painting an empty (no-selection) frame that then pops to content.
  final String? initialSelectedProjectId;
  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  String? _selectedProjectId; // the project the timer records against
  _Detail _detail = const _Tracker();
  // Narrow layout only: whether the project/settings list overlay is open. The
  // bottom bar's centre button toggles it; the bar stays live underneath.
  bool _panelOpen = false;
  double _sheetDragDy = 0; // accumulated downward drag on the sheet handle
  StreamSubscription<List<Project>>? _projectsSub;

  // The currently-mounted Template/Profile editor's lifecycle (dirty + save),
  // handed up by the editor itself via onSessionReady. Its `isDirty` gates every
  // _detail transition through _navigateTo, and `save()` runs the unsaved-changes
  // dialog's Save. Null outside those two editors.
  EditorSession? _activeEditor;

  // Settings mode swaps the side panel for the settings sections.
  bool get _inSettings =>
      _detail is _Settings ||
      _detail is _TemplateEditorDetail ||
      _detail is _ProfileEditorDetail;
  // Pages whose content stretches to the divider with a left-aligned header
  // logo — the settings pages plus the per-project invoice view (a preview page too).
  bool get _wideContentPage => _inSettings || _detail is _Invoice;

  // Content stretches to the divider only where a live invoice preview needs the
  // width — the two editors and the per-project invoice. The Settings home is a
  // centred placeholder, so it uses ContentBody's 800px column like the tracker.
  bool get _stretchContent =>
      _detail is _TemplateEditorDetail ||
      _detail is _ProfileEditorDetail ||
      _detail is _Invoice;

  // Keyboard-nav focus (wide layout only). The panel's row cursor lives here so
  // the shell can move focus *into* the panel; the tracker pane is a scope we
  // hand focus to (its own widgets take over from there — content-pane keymap
  // is a follow-up, see issue).
  final FocusNode _panelCursor = FocusNode(debugLabel: 'panelCursor');
  final FocusNode _settingsCursor = FocusNode(debugLabel: 'settingsCursor');
  final FocusScopeNode _trackerScope = FocusScopeNode(
    debugLabel: 'trackerScope',
  );
  // The tracker pane's own row cursor (its entry list). Owned here so the shell
  // can move focus straight onto it — mirrors _panelCursor. See TimerView.
  final FocusNode _trackerCursor = FocusNode(debugLabel: 'trackerCursor');
  // Panel search fields, owned here so `/` from any pane jumps into search —
  // one per pane (client/project tree vs Settings), picked by _inSettings.
  final FocusNode _panelSearch = FocusNode(debugLabel: 'panelSearch');
  final FocusNode _settingsSearch = FocusNode(debugLabel: 'settingsSearch');
  // Lets a global Space toggle the timer from any pane while it's in view.
  // DB-backed (Phase 3) — constructed with the db and recovered in initState.
  late final TimerController _timer;
  // Chord state for global sequences (the Ctrl-w window motion) when focus is
  // on a pane that bubbles them here (e.g. the content editors). The list panes
  // own their own detectors and forward focusTracker/focusPanel via callbacks.
  final ChordDetector _shellChords = ChordDetector();

  void _focusPanel() =>
      (_inSettings ? _settingsCursor : _panelCursor).requestFocus();
  void _focusTracker() => _trackerCursor.requestFocus();
  void _focusSearch() =>
      (_inSettings ? _settingsSearch : _panelSearch).requestFocus();

  // Is a text field currently focused? EditableText wraps its focusNode in a
  // Focus whose context sits under the EditableText widget, so the primary
  // focus resolves an EditableText ancestor exactly when we're typing.
  bool _isEditing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // "In the panel" means either its row cursor or its search field has focus —
  // otherwise Tab out of a focused search would wrongly jump to the tracker.
  void _togglePane() =>
      (_panelCursor.hasFocus ||
          _settingsCursor.hasFocus ||
          _panelSearch.hasFocus ||
          _settingsSearch.hasFocus)
      ? _focusTracker()
      : _focusPanel();

  // Global bindings live at the shell: Tab, Ctrl+←/→, Ctrl-h/l, the vim
  // Ctrl-w h/l chord, `?`/`/`/`t`/Space/Ctrl+,. Reached for events the focused
  // pane bubbles (a list pane owns pane-switching for its own focus, forwarding
  // via onFocusTracker/onFocusPanel; the content editors bubble to here).
  KeyEventResult _onShellKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Printable globals (`?`, `/`, Space, `t`, Tab) must stand down while a text
    // field is focused — those events still bubble up here as the field types.
    final r = Keymap.resolve(
      event,
      _shellChords,
      const {KeyScope.global},
      ctrlDown: HardwareKeyboard.instance.isControlPressed,
      shiftDown: HardwareKeyboard.instance.isShiftPressed,
      typing: _isEditing(),
    );
    switch (r) {
      case KeyPending():
        return KeyEventResult.handled;
      case KeyNone():
        return KeyEventResult.ignored;
      case KeyMatch(:final intent):
        if (event is KeyDownEvent) _handleGlobalIntent(intent);
        return KeyEventResult.handled;
    }
  }

  // Layout is tracker (left) | sidebar (right), so direction follows position:
  // left (focusTracker) → tracker, right (focusPanel) → panel.
  void _handleGlobalIntent(KeyIntent intent) {
    switch (intent) {
      case KeyIntent.showHelp:
        showShortcutsHelp(context);
      case KeyIntent.search:
        _focusSearch();
      case KeyIntent.openTracker:
        if (_detail is! _Tracker) _showTracker();
      case KeyIntent.toggleTimer:
        if (_detail is _Tracker) _timer.primary?.call();
      case KeyIntent.openSettings:
        _openSettings();
      case KeyIntent.focusTracker:
        _focusTracker();
      case KeyIntent.focusPanel:
        _focusPanel();
      case KeyIntent.switchPane:
        _togglePane();
      default:
        break; // non-global intents never resolve under the global scope
    }
  }

  // The single gate every _detail transition goes through, so an unsaved
  // change in the open Template/Profile editor can never be silently
  // discarded. No-ops if `next` targets the entity already open.
  Future<void> _navigateTo(_Detail next) async {
    final cur = _detail;
    final sameEntity = switch ((cur, next)) {
      (_TemplateEditorDetail c, _TemplateEditorDetail n) =>
        c.template?.id == n.template?.id,
      (_ProfileEditorDetail c, _ProfileEditorDetail n) =>
        c.profile?.id == n.profile?.id,
      _ => false,
    };
    if (sameEntity) return;
    if (_activeEditor?.isDirty ?? false) {
      final action = await confirmUnsavedChanges(context);
      if (action == null) return; // stay put, keep editing
      if (action == UnsavedChangesAction.save) {
        final ok = await _activeEditor?.save() ?? true;
        if (!ok) return; // validation failed; stay on the editor
      }
    }

    if (!mounted) return;
    final wasInSettings = _inSettings; // reads the *old* _detail
    setState(() {
      _detail = next;
      _activeEditor = null;
    });
    // The panel's PageTransitionSwitcher swaps only when _inSettings flips, and
    // that swap drops keyboard focus to the root scope (the outgoing panel holds
    // it through the crossfade, so the incoming panel's autofocus is lost).
    // Re-assert focus on the now-active panel so shell shortcuts (?, t, Space)
    // have a focused descendant to bubble from. Only on the boundary, so it
    // doesn't yank focus away from an editor opened within settings.
    if (_inSettings != wasInSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusPanel();
      });
    }
  }

  void _showTracker() => _navigateTo(const _Tracker());
  void _selectProject(String id) => setState(() {
    _selectedProjectId = id;
    _detail = const _Tracker(); // picking a project returns you to the timer
  });

  // Client/project editing are modals (like task/entry), so they open over the
  // content pane rather than replacing it.
  void _editProject(Project project) =>
      showProjectEditor(context, db: widget.db, project: project);
  Future<void> _addProject(String clientId) async {
    final createdProjectId = await showProjectEditor(
      context,
      db: widget.db,
      initialClientId: clientId,
    );
    // A freshly-created project becomes the selection so the timer switches to it.
    if (createdProjectId != null && mounted) _selectProject(createdProjectId);
  }

  void _editClient(Client c) =>
      showClientEditor(context, db: widget.db, client: c);
  void _addClient() => showClientEditor(context, db: widget.db);
  void _invoiceProject(Project project) =>
      setState(() => _detail = _Invoice(project));

  // Export the whole database to a portable JSON backup the user chooses a
  // location for (PRD #189, #190). Captures the messenger before the awaits so
  // it survives the async gap, and guards on `mounted` after.
  Future<void> _exportData() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await exportBackupBytes(
        widget.db,
        exportedAt: DateTime.now(),
      );
      final date = DateTime.now().toIso8601String().split('T').first;
      final saved = await saveBytes(
        bytes,
        suggestedName: 'timedart-backup-$date.json',
        typeLabel: 'JSON backup',
        extensions: const ['json'],
        mimeType: 'application/json',
      );
      if (!mounted) return;
      if (saved != null) {
        messenger.showSnackBar(const SnackBar(content: Text('Data exported.')));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  // Import a backup, replacing all data (PRD #189, #191). Pick → decode →
  // confirm (replace-all is destructive) → restore → reset to a safe view.
  Future<void> _importData() async {
    final messenger = ScaffoldMessenger.of(context);
    final PickedFile? picked;
    try {
      picked = await pickFileBytes(
        typeLabel: 'JSON backup',
        extensions: const ['json'],
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
      return;
    }
    if (picked == null) return; // cancelled
    if (!mounted) return;

    final Backup backup;
    try {
      backup = decodeBackup(picked.bytes);
    } on BackupFormatException catch (e) {
      await showInfoDialog(
        context,
        title: 'Invalid backup',
        message: "That file isn't a valid timedart backup.\n\n${e.message}",
      );
      return;
    }

    if (!mounted) return;
    final s = backup.snapshot;
    final confirmed = await confirmAction(
      context,
      title: 'Replace all data?',
      message:
          'Importing "${picked.name}" deletes everything currently in timedart '
          'and replaces it with the backup:\n\n'
          '• ${s.clients.length} clients\n'
          '• ${s.projects.length} projects\n'
          '• ${s.tasks.length} tasks\n'
          '• ${s.timeEntries.length} time entries\n\n'
          'This cannot be undone.',
      confirmLabel: 'Replace',
    );
    if (!confirmed || !mounted) return;

    final SnapshotRepair repair;
    try {
      repair = await restoreBackup(widget.db, backup);
    } on BackupIncompatibleException catch (e) {
      if (!mounted) return;
      await showInfoDialog(
        context,
        title: 'Newer backup',
        message:
            'This backup was made by a newer version of timedart '
            '(schema v${e.backupSchemaVersion}). Update the app, then import '
            'again.',
      );
      return;
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      return;
    }
    if (!mounted) return;
    // The selected project may no longer exist; drop it and return to the
    // tracker — the build re-defaults selection from the refreshed stream.
    setState(() => _selectedProjectId = null);
    _showTracker();
    final skipped = repair.isClean
        ? ''
        : ' Skipped ${repair.total} orphaned row(s) from earlier deleted '
              'projects.';
    messenger.showSnackBar(SnackBar(content: Text('Data imported.$skipped')));
  }

  // App Settings home.
  void _openSettings() => _navigateTo(const _Settings());
  void _showSettingsHome() => _navigateTo(const _Settings());
  void _addTemplate() => _navigateTo(const _TemplateEditorDetail(null));
  void _editTemplate(InvoiceTemplate t, {bool startEditing = false}) =>
      _navigateTo(_TemplateEditorDetail(t, startEditing: startEditing));
  void _addProfile() => _navigateTo(const _ProfileEditorDetail(null));
  void _editProfile(InvoiceProfile p, {bool startEditing = false}) =>
      _navigateTo(_ProfileEditorDetail(p, startEditing: startEditing));

  @override
  void initState() {
    super.initState();
    // DB-backed timer: build with the db and recover any persisted running
    // session so it survives a restart (PRD #189, Phase 3). If a session comes
    // back bound to a project, select it so the tracker opens on the work in
    // progress (the tracker then reveals the active task itself).
    _timer = TimerController(widget.db);
    _timer.recover().then((_) {
      if (!mounted) return;
      final pid = _timer.boundProjectId;
      if (pid != null) setState(() => _selectedProjectId = pid);
    });
    // Start with the gate-resolved selection so the tracker paints content on
    // its first frame; fall back to seeding a default only if none was passed.
    _selectedProjectId = widget.initialSelectedProjectId;
    widget.db.ensureDefaultProject().then((id) {
      if (mounted) {
        setState(() => _selectedProjectId ??= id); // default only if unset
      }
    });
    widget.db.ensureInvoiceDefaults(); // seed timedart theme/profile/template

    // Keep the selection honest when projects change: if the selected project is
    // deleted, fall back to the first remaining project (or none).
    _projectsSub = widget.db.watchProjects().listen((projects) {
      if (!mounted) return;
      final ids = projects.map((j) => j.id).toSet();
      final selected = _selectedProjectId;
      if (selected != null && !ids.contains(selected)) {
        setState(
          () => _selectedProjectId = projects.isNotEmpty
              ? projects.first.id
              : null,
        );
      }
    });
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    _panelCursor.dispose();
    _settingsCursor.dispose();
    _trackerScope.dispose();
    _trackerCursor.dispose();
    _panelSearch.dispose();
    _settingsSearch.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget detailView = switch (_detail) {
      _Tracker() => TimerView(
        db: widget.db,
        projectId: _selectedProjectId,
        onInvoice: _invoiceProject,
        // Keyboard cursor for the entry list; only ever focused in the wide
        // layout (Tab / Ctrl-h / Ctrl-w h), inert in the drawer.
        cursorFocusNode: _trackerCursor,
        controller: _timer,
        onFocusTracker: _focusTracker,
        onFocusPanel: _focusPanel,
      ),
      _Invoice(:final project) => InvoiceView(
        db: widget.db,
        project: project,
        onDone: _showTracker,
      ),
      _Settings() => const SettingsHome(),
      _TemplateEditorDetail(:final template, :final startEditing) =>
        TemplateEditor(
          key: ValueKey(('template', template?.id)),
          db: widget.db,
          initial: template,
          startEditing: startEditing,
          onDone: _showSettingsHome,
          onSessionReady: (s) => _activeEditor = s,
        ),
      _ProfileEditorDetail(:final profile, :final startEditing) =>
        ProfileEditor(
          key: ValueKey(('profile', profile?.id)),
          db: widget.db,
          initial: profile,
          startEditing: startEditing,
          onDone: _showSettingsHome,
          onSessionReady: (s) => _activeEditor = s,
        ),
    };
    // Cross-fade between content-pane pages on a _detail change. PageTransitionSwitcher
    // fires only when its child's Key changes, so key by the page *type* — switching
    // between two templates keeps the same key here and is handled by the editor's own
    // ValueKey below, rather than fading between two editors.
    final animatedDetail = PageTransitionSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        fillColor: Colors.transparent, // no flash of canvasColor between pages
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey(_detail.runtimeType),
        child: detailView,
      ),
    );
    // Preview pages (settings + per-project invoice) keep the left edge aligned with
    // the page header (same inset as the centred content column) but stretch
    // right to the panel divider so the preview + controls use the extra width.
    // Other pages stay centred within ContentBody's reading width.
    // Wide layout: stretch pages left-align under the header logo — margin centres
    // a notional content column, +spaceMd matches the logo inset (keep in sync
    // with page_header.dart). Narrow (mobile) has no left-aligned header logo, so
    // match the tracker's plain spaceLg inset on all sides; the extra spaceMd
    // otherwise reads as too much horizontal padding.
    Widget buildContent({required bool wide}) => _stretchContent
        ? LayoutBuilder(
            builder: (context, c) {
              final margin = wide
                  ? ((c.maxWidth - AppTokens.maxContentWidth) / 2).clamp(
                      0.0,
                      double.infinity,
                    )
                  : 0.0;
              final left = wide
                  ? margin + AppTokens.spaceLg + AppTokens.spaceMd
                  : AppTokens.spaceLg;
              return Padding(
                // Narrow: trim the bottom inset — the bottom nav bar below
                // already separates content from the chrome (matches
                // content_body.dart; keep the two in sync).
                padding: EdgeInsets.fromLTRB(
                  left,
                  AppTokens.spaceLg,
                  AppTokens.spaceLg,
                  wide ? AppTokens.spaceLg : AppTokens.spaceMd,
                ),
                child: animatedDetail,
              );
            },
          )
        : ContentBody(child: animatedDetail);

    // In the narrow layout the panel lives in a drawer, so every action must
    // close the drawer first to reveal the content pane it just changed.
    // `before` runs that pop; in the wide layout it's null (panel is persistent).
    Widget panel({
      VoidCallback? before,
      bool keyboardNav = false,
      bool showFooter = true,
    }) {
      void run(VoidCallback action) {
        before?.call();
        action();
      }

      // In Settings mode the right column is the settings panel instead of the
      // client/project tree; the content pane shows the matching preview.
      if (_inSettings) {
        final detail = _detail;
        return SettingsPanel(
          db: widget.db,
          selectedTemplateId: detail is _TemplateEditorDetail
              ? detail.template?.id
              : null,
          selectedProfileId: detail is _ProfileEditorDetail
              ? detail.profile?.id
              : null,
          onBack: () => run(_showTracker),
          onAddTemplate: () => run(_addTemplate),
          onEditTemplate: (t, {startEditing = false}) =>
              run(() => _editTemplate(t, startEditing: startEditing)),
          onAddProfile: () => run(_addProfile),
          onEditProfile: (p, {startEditing = false}) =>
              run(() => _editProfile(p, startEditing: startEditing)),
          onRerunOnboarding: widget.onRerunOnboarding,
          onExportData: () async => run(_exportData),
          onImportData: () async => run(_importData),
          // Same footer as the normal panel; Shortcuts only where keys are live.
          onShowHelp: keyboardNav ? () => showShortcutsHelp(context) : null,
          onOpenSettings: () => run(_openSettings),
          onOpenTracker: () => run(_showTracker),
          onFocusTracker: keyboardNav ? _focusTracker : null,
          onFocusPanel: keyboardNav ? _focusPanel : null,
          settingsActive: true,
          showFooter: showFooter,
          autofocus: keyboardNav,
          // Keyboard nav wired only where the panel is persistent (wide) —
          // mirrors SidePanel below, so Tab/Ctrl-h/Ctrl-l pane-switching can
          // actually reach this panel's row cursor instead of a focus node
          // nothing is listening on.
          cursorFocusNode: keyboardNav ? _settingsCursor : null,
          searchFocusNode: keyboardNav ? _settingsSearch : null,
        );
      }

      return SidePanel(
        db: widget.db,
        selectedProjectId: _selectedProjectId,
        onSelect: (id) => run(() => _selectProject(id)),
        onEditProject: (j) => run(() => _editProject(j)),
        onAddProject: (cid) => run(() => _addProject(cid)),
        onEditClient: (c) => run(() => _editClient(c)),
        onAddClient: () => run(_addClient),
        // Keyboard nav is wired only where the panel is persistent (wide).
        cursorFocusNode: keyboardNav ? _panelCursor : null,
        searchFocusNode: keyboardNav ? _panelSearch : null,
        onFocusTracker: keyboardNav ? _focusTracker : null,
        onFocusPanel: keyboardNav ? _focusPanel : null,
        // `?` while the panel is focused: the panel consumes `/`-family keys, so
        // it routes the help request back up rather than letting it bubble.
        onShowHelp: keyboardNav ? () => showShortcutsHelp(context) : null,
        onOpenSettings: () => run(_openSettings),
        onOpenTracker: () => run(_showTracker),
        settingsActive: false,
        showFooter: showFooter,
        autofocus: keyboardNav,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= AppTokens.breakpointMd) {
          return Scaffold(
            // Observes bubbled key events for pane-switching without stealing
            // primary focus from the pane widgets themselves.
            body: Focus(
              onKeyEvent: _onShellKey,
              canRequestFocus: false,
              skipTraversal: true,
              child: Row(
                children: [
                  // Logo bar sits atop the content pane, level with the panel's
                  // search field; the detail view fills the rest below it.
                  Expanded(
                    child: FocusScope(
                      node: _trackerScope,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Shortcuts + Settings live here (right of the bar,
                          // left of the panel divider), not in the panel footer.
                          PageHeader(
                            alignLogoStart: _wideContentPage,
                            onShowHelp: () => showShortcutsHelp(context),
                            onOpenSettings: _openSettings,
                            onOpenTracker: _showTracker,
                            settingsActive: _inSettings,
                          ),
                          Expanded(child: buildContent(wide: true)),
                        ],
                      ),
                    ),
                  ),

                  const VerticalDivider(
                    width: AppTokens.strokeThick,
                    color: AppTokens.colorBorder,
                  ),

                  // Footer suppressed: Shortcuts/Settings are in the header now.
                  SizedBox(
                    width: 320,
                    child: ClipRect(
                      child: PageTransitionSwitcher(
                        duration: const Duration(milliseconds: 300),
                        reverse: true,
                        transitionBuilder: (child, primary, secondary) =>
                            SharedAxisTransition(
                              animation: primary,
                              secondaryAnimation: secondary,
                              transitionType:
                                  SharedAxisTransitionType.horizontal,
                              fillColor: Colors.transparent,
                              child: child,
                            ),
                        child: KeyedSubtree(
                          key: ValueKey(_inSettings),
                          child: panel(keyboardNav: true, showFooter: false),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        // One mobile bottom-bar tab (icon over label), tinted by active state.
        // `icon` is built with the resolved foreground colour.
        Widget mobileTab({
          required bool active,
          required String label,
          required Widget Function(Color) icon,
          required VoidCallback onTap,
        }) {
          final fg = active ? scheme.primary : scheme.onSurfaceVariant;
          // Match the centre button's exact height (iconMd + spaceSm top/bottom
          // padding). All three are centred in the bar, so pinning icon→top and
          // label→bottom over this height lines the tab up with the button.
          const tabHeight = AppTokens.iconMd + AppTokens.spaceSm * 2;
          return InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 76,
              height: tabHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  icon(fg),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          // Same logo-bar style as the wide layout, but full-width with no
          // rounding; a gap above matches the search field's gap in the drawer.
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            // Flush to the top: only the SafeArea inset (status bar/notch) sits
            // above the logo bar — no extra margin, to reclaim vertical space.
            child: SafeArea(
              bottom: false,
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                color: scheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: AppTokens.spaceXs,
                ),
                // Logo centred now the hamburger is gone (nav is the bottom bar).
                child: Center(
                  child: SvgPicture.asset(
                    'assets/logo/timedart_logo_horizontal.svg',
                    height: 18,
                  ),
                ),
              ),
            ),
          ),
          // Bottom bar stays present while the panel is open: the centre button
          // toggles the project/settings list as an overlay above the content,
          // and the Tracker/Settings tabs remain tappable throughout.
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: AppTokens.strokeThin,
                color: AppTokens.colorBorder,
              ),
              SafeArea(
                top: false,
                child: Material(
                  color: scheme.surface,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        mobileTab(
                          active: !_inSettings,
                          label: 'Tracker',
                          // Nudged down by half the icon-size gap (iconLg−iconMd)
                          // so its centre lines up with the larger Settings gear.
                          icon: (c) => Padding(
                            padding: const EdgeInsets.only(
                              top: AppTokens.space4xs,
                            ),
                            child: SvgPicture.asset(
                              'assets/logo/timedart_symbol.svg',
                              height: AppTokens.iconMd,
                              colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                            ),
                          ),
                          onTap: _showTracker,
                        ),
                        // Pronounced centre button — opens/closes the list panel.
                        // Styled like the app's primary button: muted accent-dim
                        // fill + accent text at rest (drawer closed), flipping to
                        // the bright fill when open.
                        Material(
                          color: _panelOpen
                              ? AppTokens.colorAccentText
                              : AppTokens.colorAccentDim,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusButton,
                            ),
                            side: BorderSide(
                              color: AppTokens.colorBrandPrimary.withValues(
                                alpha: 0.30,
                              ),
                              width: AppTokens.strokeThin,
                            ),
                          ),
                          child: InkWell(
                            onTap: () =>
                                setState(() => _panelOpen = !_panelOpen),
                            child: Padding(
                              padding: const EdgeInsets.all(AppTokens.spaceSm),
                              child: Icon(
                                _panelOpen ? Icons.close : Icons.menu,
                                color: _panelOpen
                                    ? AppTokens.colorOnAccent
                                    : AppTokens.colorAccentText,
                                size: AppTokens.iconMd,
                              ),
                            ),
                          ),
                        ),
                        mobileTab(
                          active: _inSettings,
                          label: 'Settings',
                          // iconLg (not iconMd) so the Material gear's built-in
                          // glyph padding reads the same visual size as the
                          // edge-to-edge Tracker SVG at iconMd.
                          icon: (c) => Icon(
                            Icons.settings,
                            size: AppTokens.iconLg,
                            color: c,
                          ),
                          onTap: _openSettings,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(child: buildContent(wide: false)),
              // Scrim over the content (the bottom bar sits outside this Stack,
              // so it stays live). Fades with the sheet; ignores taps when closed.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_panelOpen,
                  child: AnimatedOpacity(
                    opacity: _panelOpen ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      onTap: () => setState(() => _panelOpen = false),
                      child: const ColoredBox(color: Colors.black54),
                    ),
                  ),
                ),
              ),
              // Project/settings list as a drawer-like sheet that slides up from
              // the bottom. A real Scaffold endDrawer would cover the bottom bar;
              // this body overlay keeps the bar live and toggleable.
              Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                  ignoring: !_panelOpen,
                  child: AnimatedSlide(
                    offset: _panelOpen ? Offset.zero : const Offset(0, 1),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: FractionallySizedBox(
                      heightFactor: 0.85,
                      child: Material(
                        color: scheme.surface,
                        clipBehavior: Clip.antiAlias,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppTokens.radiusLg),
                          ),
                          side: BorderSide(
                            color: AppTokens.colorBorder,
                            width: AppTokens.strokeThin,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Grab handle — drag it down to dismiss.
                            GestureDetector(
                              behavior: HitTestBehavior
                                  .opaque, // catch drags on the whole strip, not just the 4px bar
                              onVerticalDragUpdate: (d) =>
                                  _sheetDragDy += d.delta.dy,
                              onVerticalDragEnd: (d) {
                                final flungDown =
                                    (d.primaryVelocity ?? 0) > 300;
                                if (flungDown || _sheetDragDy > 60) {
                                  setState(() => _panelOpen = false);
                                }
                                _sheetDragDy = 0;
                              },
                              child: const SheetGrabHandle(),
                            ),
                            Expanded(
                              child: panel(
                                before: () =>
                                    setState(() => _panelOpen = false),
                                showFooter: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
