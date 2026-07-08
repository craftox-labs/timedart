import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/shell/page_header.dart';
import 'package:time_tracker/features/shell/shortcuts_help.dart';
import 'package:time_tracker/features/shell/side_panel.dart';
import 'package:time_tracker/features/shell/settings_panel.dart';
import 'package:time_tracker/features/tracker/timer_view.dart';
import 'package:time_tracker/features/projects/project_form.dart';
import 'package:time_tracker/features/clients/client_form.dart';
import 'package:time_tracker/features/invoices/invoice_view.dart';
import 'package:time_tracker/features/invoices/profile_editor.dart';
import 'package:time_tracker/features/invoices/template_editor.dart';
import 'package:time_tracker/features/shell/settings_home.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';
import 'package:time_tracker/widgets/content_body.dart';

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
class _Branding extends _Detail {
  const _Branding();
}

// Editing (or creating, when the row is null) a branding entity in the content
// pane, with the branding panel still alongside.
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
  const AdaptiveShell({super.key, required this.db});
  final AppDatabase db;
  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int? _selectedProjectId; // the project the timer records against
  _Detail _detail = const _Tracker();
  StreamSubscription<List<Project>>? _projectsSub;

  // Whether the currently-mounted Template/Profile editor has unsaved changes,
  // and a handle to trigger its save — both supplied by the editor itself
  // (see onDirtyChanged/onSaveHandleReady). Gates every _detail transition
  // via _navigateTo. Always false/null outside those two editors.
  bool _editorDirty = false;
  Future<bool> Function()? _currentEditorSave;

  // Branding mode swaps the side panel for the branding sections.
  bool get _inBranding =>
      _detail is _Branding ||
      _detail is _TemplateEditorDetail ||
      _detail is _ProfileEditorDetail;
  // Pages whose content stretches to the divider with a left-aligned header
  // logo — the branding pages plus the per-project invoice view (a preview page too).
  bool get _wideContentPage => _inBranding || _detail is _Invoice;

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
  final FocusScopeNode _trackerScope = FocusScopeNode(
    debugLabel: 'trackerScope',
  );
  // The tracker pane's own row cursor (its entry list). Owned here so the shell
  // can move focus straight onto it — mirrors _panelCursor. See TimerView.
  final FocusNode _trackerCursor = FocusNode(debugLabel: 'trackerCursor');
  // Panel search field, owned here so `/` from any pane jumps into search.
  final FocusNode _panelSearch = FocusNode(debugLabel: 'panelSearch');
  // Lets a global Space toggle the timer from any pane while it's in view.
  final TimerController _timer = TimerController();
  bool _pendingCtrlW = false; // saw Ctrl-w, awaiting an h/l

  void _focusPanel() => _panelCursor.requestFocus();
  void _focusTracker() => _trackerCursor.requestFocus();
  void _focusSearch() => _panelSearch.requestFocus();

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
  void _togglePane() => (_panelCursor.hasFocus || _panelSearch.hasFocus)
      ? _focusTracker()
      : _focusPanel();

  // Pane-switching lives at the shell: Tab, Ctrl+←/→, Ctrl-h/l, and the vim
  // Ctrl-w h/l chord. Row navigation is the panel's own concern.
  // Layout is tracker (left) | sidebar (right), so direction follows position:
  // left (h/←) → tracker, right (l/→) → panel.
  KeyEventResult _onShellKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    // Global single-key bindings (`?`, `/`, Space) must stand down while a text
    // field is focused — printable-key events still bubble up here even as the
    // field is receiving them, so without this guard they'd double-fire.
    final editing = _isEditing();

    // `?` (Shift+/) is global: open the shortcuts help. Matched by character,
    // not logical key — a shifted `/` doesn't report LogicalKeyboardKey.slash.
    // Reaches here whenever the focused pane doesn't consume it (the panel
    // routes it via onShowHelp).
    if (!ctrl && !editing && event.character == '?') {
      if (event is KeyDownEvent) showShortcutsHelp(context);
      return KeyEventResult.handled;
    }

    // `/` is global: focus the panel search from whichever pane has focus.
    if (!ctrl && !editing && key == LogicalKeyboardKey.slash) {
      _focusSearch();
      return KeyEventResult.handled;
    }

    // Space is global while the tracker is in view: toggle start/pause/resume
    // from any pane. Fires once per press (repeats are swallowed, not repeated).
    if (!ctrl &&
        !editing &&
        key == LogicalKeyboardKey.space &&
        _detail is _Tracker) {
      if (event is KeyDownEvent) _timer.primary?.call();
      return KeyEventResult.handled;
    }

    final left =
        key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.arrowLeft;
    final right =
        key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.arrowRight;

    // Ctrl+, opens App Settings (Branding) from anywhere.
    if (ctrl && key == LogicalKeyboardKey.comma) {
      if (event is KeyDownEvent) _openBranding();
      return KeyEventResult.handled;
    }

    // Ctrl-w begins a window-motion chord.
    if (ctrl && key == LogicalKeyboardKey.keyW) {
      _pendingCtrlW = true;
      return KeyEventResult.handled;
    }
    if (_pendingCtrlW) {
      _pendingCtrlW = false;
      if (left) {
        _focusTracker();
        return KeyEventResult.handled;
      }
      if (right) {
        _focusPanel();
        return KeyEventResult.handled;
      }
      // any other key just cancels the chord, falls through
    }

    if (ctrl && left) {
      _focusTracker();
      return KeyEventResult.handled;
    }
    if (ctrl && right) {
      _focusPanel();
      return KeyEventResult.handled;
    }
    // Tab/Shift+Tab switch panes — but while a form field is focused, they
    // should cycle to the next/previous field instead (Flutter's default
    // focus traversal), so stand down and let the key bubble to it.
    if (!editing && key == LogicalKeyboardKey.tab) {
      _togglePane();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    if (_editorDirty) {
      final action = await confirmUnsavedChanges(context);
      if (action == null) return; // stay put, keep editing
      if (action == UnsavedChangesAction.save) {
        final ok = await _currentEditorSave?.call() ?? true;
        if (!ok) return; // validation failed; stay on the editor
      }
    }
    if (!mounted) return;
    setState(() {
      _detail = next;
      _editorDirty = false;
      _currentEditorSave = null;
    });
  }

  void _showTracker() => _navigateTo(const _Tracker());
  void _selectProject(int id) => setState(() {
    _selectedProjectId = id;
    _detail = const _Tracker(); // picking a project returns you to the timer
  });

  // Client/project editing are modals (like task/entry), so they open over the
  // content pane rather than replacing it.
  void _editProject(Project project) =>
      showProjectEditor(context, db: widget.db, project: project);
  Future<void> _addProject(int clientId) async {
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

  // App Settings home.
  void _openBranding() => _navigateTo(const _Branding());
  void _showBrandingHome() => _navigateTo(const _Branding());
  void _addTemplate() => _navigateTo(const _TemplateEditorDetail(null));
  void _editTemplate(InvoiceTemplate t, {bool startEditing = false}) =>
      _navigateTo(_TemplateEditorDetail(t, startEditing: startEditing));
  void _addProfile() => _navigateTo(const _ProfileEditorDetail(null));
  void _editProfile(InvoiceProfile p, {bool startEditing = false}) =>
      _navigateTo(_ProfileEditorDetail(p, startEditing: startEditing));

  @override
  void initState() {
    super.initState();
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
    _trackerScope.dispose();
    _trackerCursor.dispose();
    _panelSearch.dispose();
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
      ),
      _Invoice(:final project) => InvoiceView(
        db: widget.db,
        project: project,
        onDone: _showTracker,
      ),
      _Branding() => const SettingsHome(),
      _TemplateEditorDetail(:final template, :final startEditing) =>
        TemplateEditor(
          key: ValueKey(('template', template?.id)),
          db: widget.db,
          initial: template,
          startEditing: startEditing,
          onDone: _showBrandingHome,
          onDirtyChanged: (d) => setState(() => _editorDirty = d),
          onSaveHandleReady: (save) => _currentEditorSave = save,
        ),
      _ProfileEditorDetail(:final profile, :final startEditing) =>
        ProfileEditor(
          key: ValueKey(('profile', profile?.id)),
          db: widget.db,
          initial: profile,
          startEditing: startEditing,
          onDone: _showBrandingHome,
          onDirtyChanged: (d) => setState(() => _editorDirty = d),
          onSaveHandleReady: (save) => _currentEditorSave = save,
        ),
    };
    // Preview pages (branding + per-project invoice) keep the left edge aligned with
    // the page header (same inset as the centred content column) but stretch
    // right to the panel divider so the preview + controls use the extra width.
    // Other pages stay centred within ContentBody's reading width.
    final Widget content = _stretchContent
        ? LayoutBuilder(
            builder: (context, c) {
              final margin = ((c.maxWidth - AppTokens.maxContentWidth) / 2)
                  .clamp(0.0, double.infinity);
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  margin + AppTokens.spaceLg,
                  AppTokens.spaceLg,
                  AppTokens.spaceLg,
                  AppTokens.spaceLg,
                ),
                child: detailView,
              );
            },
          )
        : ContentBody(child: detailView);

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

      // In Branding mode the right column is the branding panel instead of the
      // client/project tree; the content pane shows the matching preview.
      if (_inBranding) {
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
          // Same footer as the normal panel; Shortcuts only where keys are live.
          onShowHelp: keyboardNav ? () => showShortcutsHelp(context) : null,
          onOpenSettings: () => run(_openBranding),
          showFooter: showFooter,
          autofocus: keyboardNav,
          // Keyboard nav wired only where the panel is persistent (wide) —
          // mirrors SidePanel below, so Tab/Ctrl-h/Ctrl-l pane-switching can
          // actually reach this panel's row cursor instead of a focus node
          // nothing is listening on.
          cursorFocusNode: keyboardNav ? _panelCursor : null,
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
        onExitToTracker: keyboardNav ? _focusTracker : null,
        // `?` while the panel is focused: the panel consumes `/`-family keys, so
        // it routes the help request back up rather than letting it bubble.
        onShowHelp: keyboardNav ? () => showShortcutsHelp(context) : null,
        onOpenSettings: () => run(_openBranding),
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
                            onOpenSettings: _openBranding,
                          ),
                          Expanded(child: content),
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
                    child: panel(keyboardNav: true, showFooter: false),
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
            preferredSize: const Size.fromHeight(AppTokens.spaceLg + 44),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceLg),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceXs,
                  ),
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/logo/timedart_logo_horizontal.svg',
                        height: 18,
                      ),
                      const Spacer(),
                      Builder(
                        builder: (context) => IconButton(
                          icon: const Icon(Icons.menu),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Menu',
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          endDrawer: Drawer(child: panel(before: () => Navigator.pop(context))),
          body: content,
        );
      },
    );
  }
}
