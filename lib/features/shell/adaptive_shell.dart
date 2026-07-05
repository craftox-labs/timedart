import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/shell/page_header.dart';
import 'package:time_tracker/features/shell/shortcuts_help.dart';
import 'package:time_tracker/features/shell/side_panel.dart';
import 'package:time_tracker/features/shell/branding_panel.dart';
import 'package:time_tracker/features/tracker/timer_view.dart';
import 'package:time_tracker/features/jobs/job_form.dart';
import 'package:time_tracker/features/clients/client_form.dart';
import 'package:time_tracker/features/invoices/invoice_view.dart';
import 'package:time_tracker/features/invoices/branding_home.dart';
import 'package:time_tracker/features/invoices/theme_editor.dart';
import 'package:time_tracker/features/invoices/profile_editor.dart';
import 'package:time_tracker/features/invoices/template_editor.dart';
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
  final Job job;
  const _Invoice(this.job);
}

// App Settings → Branding: the panel shows theme/profile/template sections and
// the content pane previews the selected branding.
class _Branding extends _Detail {
  const _Branding();
}

// Editing (or creating, when the row is null) a branding entity in the content
// pane, with the branding panel still alongside.
class _ThemeEditorDetail extends _Detail {
  final InvoiceTheme? theme;
  const _ThemeEditorDetail(this.theme);
}

class _ProfileEditorDetail extends _Detail {
  final InvoiceProfile? profile;
  const _ProfileEditorDetail(this.profile);
}

class _TemplateEditorDetail extends _Detail {
  final InvoiceTemplate? template;
  const _TemplateEditorDetail(this.template);
}

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key, required this.db});
  final AppDatabase db;
  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int? _selectedJobId; // the job the timer records against
  _Detail _detail = const _Tracker();
  StreamSubscription<List<Job>>? _jobsSub;

  // Branding-mode preview selection (null → the default theme/profile). Picking
  // a template sets both at once.
  int? _brandingThemeId;
  int? _brandingProfileId;
  // Branding mode swaps the side panel for the branding sections.
  bool get _inBranding =>
      _detail is _Branding ||
      _detail is _ThemeEditorDetail ||
      _detail is _ProfileEditorDetail ||
      _detail is _TemplateEditorDetail;
  // Pages whose content stretches to the divider with a left-aligned header
  // logo — the branding pages plus the per-job invoice view (a preview page too).
  bool get _wideContentPage => _inBranding || _detail is _Invoice;

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
    if (key == LogicalKeyboardKey.tab) {
      _togglePane();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showTracker() => setState(() => _detail = const _Tracker());
  void _selectJob(int id) => setState(() {
    _selectedJobId = id;
    _detail = const _Tracker(); // picking a job returns you to the timer
  });

  // Client/job editing are modals (like task/entry), so they open over the
  // content pane rather than replacing it.
  void _editJob(Job job) => showJobEditor(context, db: widget.db, job: job);
  Future<void> _addJob(int clientId) async {
    final createdJobId = await showJobEditor(
      context,
      db: widget.db,
      initialClientId: clientId,
    );
    // A freshly-created job becomes the selection so the timer switches to it.
    if (createdJobId != null && mounted) _selectJob(createdJobId);
  }

  void _editClient(Client c) =>
      showClientEditor(context, db: widget.db, client: c);
  void _addClient() => showClientEditor(context, db: widget.db);
  void _invoiceJob(Job job) => setState(() => _detail = _Invoice(job));

  // App Settings → Branding mode. Starts on the default theme/profile.
  void _openBranding() => setState(() {
    _brandingThemeId = null;
    _brandingProfileId = null;
    _detail = const _Branding();
  });
  void _selectBrandingTheme(int id) => setState(() => _brandingThemeId = id);
  void _selectBrandingProfile(int id) =>
      setState(() => _brandingProfileId = id);
  void _selectBrandingTemplate(InvoiceTemplate t) => setState(() {
    _brandingThemeId = t.themeId;
    _brandingProfileId = t.profileId;
  });
  void _showBrandingHome() => setState(() => _detail = const _Branding());
  void _addTheme() => setState(() => _detail = const _ThemeEditorDetail(null));
  void _editTheme(InvoiceTheme t) =>
      setState(() => _detail = _ThemeEditorDetail(t));
  void _addProfile() =>
      setState(() => _detail = const _ProfileEditorDetail(null));
  void _editProfile(InvoiceProfile p) =>
      setState(() => _detail = _ProfileEditorDetail(p));
  void _addTemplate() =>
      setState(() => _detail = const _TemplateEditorDetail(null));
  void _editTemplate(InvoiceTemplate t) =>
      setState(() => _detail = _TemplateEditorDetail(t));

  @override
  void initState() {
    super.initState();
    widget.db.ensureDefaultJob().then((id) {
      if (mounted) {
        setState(() => _selectedJobId ??= id); // default only if unset
      }
    });
    widget.db.ensureInvoiceDefaults(); // seed timedart theme/profile/template

    // Keep the selection honest when jobs change: if the selected job is
    // deleted, fall back to the first remaining job (or none).
    _jobsSub = widget.db.watchJobs().listen((jobs) {
      if (!mounted) return;
      final ids = jobs.map((j) => j.id).toSet();
      final selected = _selectedJobId;
      if (selected != null && !ids.contains(selected)) {
        setState(() => _selectedJobId = jobs.isNotEmpty ? jobs.first.id : null);
      }
    });
  }

  @override
  void dispose() {
    _jobsSub?.cancel();
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
        jobId: _selectedJobId,
        onInvoice: _invoiceJob,
        // Keyboard cursor for the entry list; only ever focused in the wide
        // layout (Tab / Ctrl-h / Ctrl-w h), inert in the drawer.
        cursorFocusNode: _trackerCursor,
        controller: _timer,
      ),
      _Invoice(:final job) => InvoiceView(
        db: widget.db,
        job: job,
        onDone: _showTracker,
      ),
      _Branding() => BrandingHome(
        db: widget.db,
        selectedThemeId: _brandingThemeId,
        selectedProfileId: _brandingProfileId,
      ),
      _ThemeEditorDetail(:final theme) => ThemeEditor(
        db: widget.db,
        initial: theme,
        onDone: _showBrandingHome,
      ),
      _ProfileEditorDetail(:final profile) => ProfileEditor(
        db: widget.db,
        initial: profile,
        onDone: _showBrandingHome,
      ),
      _TemplateEditorDetail(:final template) => TemplateEditor(
        db: widget.db,
        initial: template,
        onDone: _showBrandingHome,
      ),
    };
    // Preview pages (branding + per-job invoice) keep the left edge aligned with
    // the page header (same inset as the centred content column) but stretch
    // right to the panel divider so the preview + controls use the extra width.
    // Other pages stay centred within ContentBody's reading width.
    final Widget content = _wideContentPage
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
    Widget panel({VoidCallback? before, bool keyboardNav = false}) {
      void run(VoidCallback action) {
        before?.call();
        action();
      }

      // In Branding mode the right column is the branding panel instead of the
      // client/job tree; the content pane shows the matching preview.
      if (_inBranding) {
        return BrandingPanel(
          db: widget.db,
          onSelectTheme: (id) => run(() => _selectBrandingTheme(id)),
          onSelectProfile: (id) => run(() => _selectBrandingProfile(id)),
          onSelectTemplate: (t) => run(() => _selectBrandingTemplate(t)),
          onBack: () => run(_showTracker),
          onAddTheme: () => run(_addTheme),
          onEditTheme: (t) => run(() => _editTheme(t)),
          onAddProfile: () => run(_addProfile),
          onEditProfile: (p) => run(() => _editProfile(p)),
          onAddTemplate: () => run(_addTemplate),
          onEditTemplate: (t) => run(() => _editTemplate(t)),
          // Same footer as the normal panel; Shortcuts only where keys are live.
          onShowHelp: keyboardNav ? () => showShortcutsHelp(context) : null,
          onOpenSettings: () => run(_openBranding),
          autofocus: keyboardNav,
        );
      }

      return SidePanel(
        db: widget.db,
        selectedJobId: _selectedJobId,
        onSelect: (id) => run(() => _selectJob(id)),
        onEditJob: (j) => run(() => _editJob(j)),
        onAddJob: (cid) => run(() => _addJob(cid)),
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
                          PageHeader(alignLogoStart: _wideContentPage),
                          Expanded(child: content),
                        ],
                      ),
                    ),
                  ),

                  const VerticalDivider(
                    width: AppTokens.strokeThick,
                    color: AppTokens.colorBorder,
                  ),

                  SizedBox(width: 320, child: panel(keyboardNav: true)),
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
