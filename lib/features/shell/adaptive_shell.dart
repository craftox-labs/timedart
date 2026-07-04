import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/shell/side_panel.dart';
import 'package:time_tracker/features/tracker/timer_view.dart';
import 'package:time_tracker/features/jobs/job_form.dart';
import 'package:time_tracker/features/clients/client_form.dart';
import 'package:time_tracker/features/invoices/invoice_view.dart';
import 'package:time_tracker/widgets/content_body.dart';

// What the detail pane is currently showing. One value instead of a pile of
// nullable flags, so the content is a single exhaustive switch.
sealed class _Detail {
  const _Detail();
}

class _Tracker extends _Detail {
  const _Tracker();
}

class _EditJob extends _Detail {
  final Job? job; // null = adding
  final int? clientId; // preselected client when adding under one
  const _EditJob({this.job, this.clientId});
}

class _EditClient extends _Detail {
  final Client? client; // null = adding
  const _EditClient({this.client});
}

class _Invoice extends _Detail {
  final Job job;
  const _Invoice(this.job);
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

  // Keyboard-nav focus (wide layout only). The panel's row cursor lives here so
  // the shell can move focus *into* the panel; the tracker pane is a scope we
  // hand focus to (its own widgets take over from there — content-pane keymap
  // is a follow-up, see issue).
  final FocusNode _panelCursor = FocusNode(debugLabel: 'panelCursor');
  final FocusScopeNode _trackerScope = FocusScopeNode(debugLabel: 'trackerScope');
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
  void _togglePane() =>
      _panelCursor.hasFocus ? _focusTracker() : _focusPanel();

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

    // Global single-key bindings (`/`, Space) must stand down while a text
    // field is focused — printable-key events still bubble up here even as the
    // field is receiving them, so without this guard they'd double-fire.
    final editing = _isEditing();

    // `/` is global: focus the panel search from whichever pane has focus.
    if (!ctrl && !editing && key == LogicalKeyboardKey.slash) {
      _focusSearch();
      return KeyEventResult.handled;
    }

    // Space is global while the tracker is in view: toggle start/pause/resume
    // from any pane. Fires once per press (repeats are swallowed, not repeated).
    if (!ctrl && !editing && key == LogicalKeyboardKey.space && _detail is _Tracker) {
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
  void _editJob(Job job) => setState(() => _detail = _EditJob(job: job));
  void _addJob(int clientId) =>
      setState(() => _detail = _EditJob(clientId: clientId));
  void _editClient(Client c) =>
      setState(() => _detail = _EditClient(client: c));
  void _addClient() => setState(() => _detail = const _EditClient());
  void _invoiceJob(Job job) => setState(() => _detail = _Invoice(job));

  @override
  void initState() {
    super.initState();
    widget.db.ensureDefaultJob().then((id) {
      if (mounted) {
        setState(() => _selectedJobId ??= id); // default only if unset
      }
    });

    // Keep selection and any open job editor honest when jobs change:
    // if the selected/edited job is deleted, fall back gracefully.
    _jobsSub = widget.db.watchJobs().listen((jobs) {
      if (!mounted) return;
      final ids = jobs.map((j) => j.id).toSet();
      var selected = _selectedJobId;
      var detail = _detail;

      if (selected != null && !ids.contains(selected)) {
        selected = jobs.isNotEmpty ? jobs.first.id : null;
      }
      if (detail is _EditJob &&
          detail.job != null &&
          !ids.contains(detail.job!.id)) {
        detail = const _Tracker();
      }
      if (selected != _selectedJobId || !identical(detail, _detail)) {
        setState(() {
          _selectedJobId = selected;
          _detail = detail;
        });
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
      _EditJob(:final job, :final clientId) => JobForm(
        db: widget.db,
        initial: job,
        initialClientId: clientId,
        // A freshly-created job becomes the selection so the timer switches
        // to it; edit/delete/cancel just return to the tracker.
        onDone: (createdJobId) =>
            createdJobId == null ? _showTracker() : _selectJob(createdJobId),
      ),
      _EditClient(:final client) => ClientForm(
        db: widget.db,
        initial: client,
        onDone: _showTracker,
      ),
      _Invoice(:final job) => InvoiceView(
        db: widget.db,
        job: job,
        onDone: _showTracker,
      ),
    };
    final content = ContentBody(child: detailView);

    // In the narrow layout the panel lives in a drawer, so every action must
    // close the drawer first to reveal the content pane it just changed.
    // `before` runs that pop; in the wide layout it's null (panel is persistent).
    SidePanel panel({VoidCallback? before, bool keyboardNav = false}) {
      void run(VoidCallback action) {
        before?.call();
        action();
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
                  Expanded(child: FocusScope(node: _trackerScope, child: content)),

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
          appBar: AppBar(
            title: const Text('Time Tracker'),
            // Explicit menu button (replacing the auto one) padded to sit at
            // the same right inset as the content below.
            actions: [
              Builder(
                builder: (context) => Padding(
                  padding: const EdgeInsets.only(right: AppTokens.spaceLg),
                  child: IconButton(
                    icon: const Icon(Icons.menu),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Menu',
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
              ),
            ],
          ),
          endDrawer: Drawer(child: panel(before: () => Navigator.pop(context))),
          body: content,
        );
      },
    );
  }
}
