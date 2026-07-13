import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/shell/keymap.dart';
import 'package:timedart/features/tracker/timer_controls.dart';
import 'package:timedart/features/tracker/timer_session.dart';
import 'package:timedart/features/tracker/timer_store.dart';
import 'package:timedart/constants/format.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/tracker/task_rows.dart';
import 'package:timedart/features/tracker/task_list.dart';
import 'package:timedart/features/tracker/task_editor.dart';
import 'package:timedart/features/tracker/entry_form.dart';
import 'package:timedart/widgets/tap_target.dart';

/// Owns the running timer so it survives content-pane switches. Editing a
/// client/project or invoicing unmounts the tracker view, but the session and its
/// per-second ticker live here on the shell — so navigating away no longer
/// discards a running session. The view renders from this and listens for
/// repaints.
class TimerController extends ChangeNotifier {
  TimerController(AppDatabase db) : _store = TimerStore(db);

  // The DB-backed timer store (PRD #189, Phase 3) — owns the pure state machine
  // plus persistence of the active-timer row, so a running timer survives a
  // restart and (once sync lands) travels across devices.
  final TimerStore _store;
  Timer? _ticker;
  // Optional description for the session in progress, becoming the finished
  // entry's description. Lives here so it survives content-pane switches.
  final description = TextEditingController();

  // Set by the mounted TimerView so a global Space can fire the primary action.
  // Null when no tracker is on screen.
  VoidCallback? primary;

  int get elapsed => _store.session.elapsed;
  bool get isRunning => _store.session.isRunning;
  bool get hasSession => _store.session.hasSession;
  String? get boundProjectId => _store.session.boundProjectId;
  String? get boundTaskId => _store.session.boundTaskId;

  /// Recover a persisted timer on startup and resume its ticker if it was
  /// running. Called once by the shell after construction.
  Future<void> recover() async {
    await _store.recover(now: DateTime.now());
    // Restore the session note into the field so a recovered timer shows it.
    final note = _store.recoveredDescription;
    if (note != null) description.text = note;
    if (_store.session.isRunning) _startTicker();
    notifyListeners();
  }

  String? get _note {
    final t = description.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> startOrResume(String? projectId, String? taskId) async {
    if (_store.session.isRunning) return;
    // _store.start runs the state-machine transition synchronously before its
    // first await, so the session is running by the time the ticker fires. The
    // current note rides along so it survives a restart.
    final persisted = _store.start(
      projectId,
      taskId,
      now: DateTime.now(),
      description: _note,
    );
    _startTicker();
    notifyListeners();
    await persisted;
  }

  Future<void> pause() async {
    _ticker?.cancel();
    final persisted = _store.pause(now: DateTime.now(), description: _note);
    notifyListeners();
    await persisted;
  }

  /// Stop: persist the finished span as a TimeEntry, tombstone the active-timer
  /// row, reset, and clear the description. Returns what was saved (null when
  /// there's nothing to record). Rethrows a write failure with the session
  /// intact so the user can retry.
  Future<FinishedSession?> finish() async {
    _ticker?.cancel();
    final result = await _store.finish(now: DateTime.now(), description: _note);
    description.clear();
    notifyListeners();
    return result;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _store.tick();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    description.dispose();
    super.dispose();
  }
}

class TimerView extends StatefulWidget {
  const TimerView({
    super.key,
    required this.db,
    required this.projectId,
    required this.onInvoice,
    this.cursorFocusNode,
    this.controller,
    this.onFocusTracker,
    this.onFocusPanel,
  });
  final AppDatabase db;
  final String? projectId;
  final void Function(Project)
  onInvoice; // open the invoice view for this project
  // Keyboard cursor for the entry list (wide layout). When null, the pane has
  // no keymap — used by the narrow drawer layout, which is mouse-first.
  final FocusNode? cursorFocusNode;
  // Lets the shell trigger the primary action for a global Space binding.
  final TimerController? controller;
  // Pane-switch intents, forwarded to the shell's focus methods (Ctrl-h/l and
  // the Ctrl-w chord). The tracker sits on the left, so focusPanel leaves right.
  final VoidCallback? onFocusTracker;
  final VoidCallback? onFocusPanel;

  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  // The session lives in the controller so it survives pane switches. When no
  // controller is supplied (standalone use) an internal one stands in.
  TimerController? _internalController;
  TimerController get _c =>
      widget.controller ??
      (_internalController ??= TimerController(widget.db)..recover());
  Stream<List<TimeEntry>>? _entriesStream; // entries for the selected project
  Stream<List<Task>>? _tasksStream; // tasks for the selected project
  Stream<(Project, Client)?>? _projectStream;

  // The task the timer will track against (armed by selecting it in the list).
  // The Start action is gated on this; a running session binds its task at
  // start, so changing this mid-run only affects the next session.
  String? _selectedTaskId;
  final _descFocus = FocusNode(debugLabel: 'sessionDescription');

  // The cursor navigates a flattened task/entry row list (mirrors the side
  // panel). _tasks/_entries mirror the latest stream emissions; _rows is
  // rebuilt each build and cached so the key handler can index it outside build.
  List<Task> _tasks = const [];
  List<TimeEntry> _entries = const [];
  StreamSubscription<List<Task>>? _tasksSub;
  StreamSubscription<List<TimeEntry>>? _entriesSub;
  final Set<String> _expanded = {}; // expanded task ids
  List<TaskListRow> _rows = const [];
  int _cursor = 0;
  // One-shot: on first load with a recovered/running session, move the cursor to
  // the active task and scroll it into view (once its row is present).
  bool _revealedActiveTask = false;
  final _cursorKey = GlobalKey(); // rides the focused row for ensureVisible
  final _scroll = ScrollController();
  static const _estRowHeight = 56.0; // rough row height for off-screen jumps
  final _chords = ChordDetector(); // gg / Ctrl-w window-motion sequence state

  FocusNode? get _cursorNode => widget.cursorFocusNode;
  bool get _cursorActive => _cursorNode?.hasPrimaryFocus ?? false;

  @override
  void initState() {
    super.initState();
    _updateProjectStream();
    _cursorNode?.addListener(_onFocusChanged);
    _c.primary = _primaryAction;
  }

  @override
  void didUpdateWidget(TimerView old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) _updateProjectStream();
    if (old.cursorFocusNode != widget.cursorFocusNode) {
      old.cursorFocusNode?.removeListener(_onFocusChanged);
      _cursorNode?.addListener(_onFocusChanged);
    }
    if (old.controller != widget.controller) {
      final prev = old.controller ?? _internalController;
      if (prev?.primary == _primaryAction) prev?.primary = null;
      _c.primary = _primaryAction;
    }
  }

  @override
  void dispose() {
    _descFocus.dispose();
    _entriesSub?.cancel();
    _tasksSub?.cancel();
    _scroll.dispose();
    _cursorNode?.removeListener(_onFocusChanged);
    if (_c.primary == _primaryAction) _c.primary = null;
    // Only the internal fallback is ours to dispose; a shell-owned controller
    // outlives this view (that's the whole point).
    _internalController?.dispose();
    super.dispose();
  }

  // Repaint the focus ring when the cursor gains/loses focus. A focus excursion
  // (into the task field, out to another pane) also abandons a half-typed gg.
  void _onFocusChanged() {
    _chords.reset();
    if (mounted) setState(() {});
  }

  void _updateProjectStream() {
    final id = widget.projectId;
    _projectStream = id == null ? null : widget.db.watchProjectWithClient(id);
    _entriesStream = id == null ? null : widget.db.watchEntriesForProject(id);
    _tasksStream = id == null ? null : widget.db.watchTasksForProject(id);

    // Cache tasks + entries so the key handler can index the flattened rows
    // (rebuilt in build()). The cursor is clamped there against _rows.
    _entriesSub?.cancel();
    _tasksSub?.cancel();
    _entries = const [];
    _tasks = const [];
    _expanded.clear();
    _selectedTaskId = null; // a different project means a different task set
    _cursor = 0;
    _entriesSub = _entriesStream?.listen((rows) {
      if (mounted) setState(() => _entries = rows);
    });
    _tasksSub = _tasksStream?.listen((rows) {
      if (!mounted) return;
      setState(() {
        _tasks = rows;
        final ids = rows.map((t) => t.id).toSet();
        _expanded.removeWhere((id) => !ids.contains(id)); // drop deleted tasks
        // Disarm a task that no longer exists.
        if (_selectedTaskId != null && !ids.contains(_selectedTaskId)) {
          _selectedTaskId = null;
        }
      });
    });
  }

  void _selectTask(String taskId) =>
      setState(() => _selectedTaskId = taskId); // arm for the timer

  void _startOrResume() => _c.startOrResume(widget.projectId, _selectedTaskId);

  void _pause() => _c.pause();

  Future<void> _finish() async {
    try {
      // The controller/store persists the entry, tombstones the active-timer
      // row, and resets; await so a write failure is caught (session left
      // intact for a retry) rather than silently lost.
      await _c.finish();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save entry: $e')));
      }
    }
  }

  // Open the add/edit-entry editor (adaptive modal/sheet). entry == null adds;
  // taskId preselects the task when adding under a specific one.
  void _openEntryEditor(TimeEntry? entry, {String? taskId}) {
    final projectId = widget.projectId;
    if (projectId == null) return;
    showEntryEditor(
      context,
      db: widget.db,
      projectId: projectId,
      entry: entry,
      initialTaskId: taskId,
    );
  }

  // Open the add/edit-task editor. task == null adds.
  void _openTaskEditor(Task? task) {
    final projectId = widget.projectId;
    if (projectId == null) return;
    showTaskEditor(context, db: widget.db, projectId: projectId, task: task);
  }

  // Whether Start/Space can fire: pause/resume of an existing session is always
  // allowed; a fresh start needs a project and an armed task.
  bool get _canPrimary =>
      _c.isRunning ||
      _c.hasSession ||
      (widget.projectId != null && _selectedTaskId != null);

  // Start/resume ⇄ pause, mirroring the primary button.
  void _primaryAction() {
    if (!_canPrimary) return;
    _c.isRunning ? _pause() : _startOrResume();
  }

  // --- Task/entry row cursor (wide layout) ---

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

  void _toggleTask(String taskId) {
    setState(() {
      if (!_expanded.remove(taskId)) _expanded.add(taskId);
    });
  }

  // l / → : expand a collapsed task (or step into its entries); open an entry.
  void _expandOrOpen() {
    if (_cursor >= _rows.length) return;
    switch (_rows[_cursor]) {
      case TaskHeaderRow(:final taskId, :final expanded, :final entryCount):
        if (!expanded && entryCount > 0) {
          setState(() => _expanded.add(taskId));
        } else if (expanded) {
          _moveCursor(1); // into the first entry
        }
      case TaskEntryRow(:final entry):
        _openEntryEditor(entry);
    }
  }

  // h / ← : collapse an expanded task; from an entry, jump to its task header.
  void _collapseOrParent() {
    if (_cursor >= _rows.length) return;
    switch (_rows[_cursor]) {
      case TaskHeaderRow(:final taskId, :final expanded):
        if (expanded) setState(() => _expanded.remove(taskId));
      case TaskEntryRow(:final task):
        final i = _rows.indexWhere(
          (r) => r is TaskHeaderRow && r.taskId == task.id,
        );
        if (i >= 0) _jumpTo(i);
    }
  }

  // Enter : arm a task for the timer; open an entry for editing.
  void _activateCursor() {
    if (_cursor >= _rows.length) return;
    switch (_rows[_cursor]) {
      case TaskHeaderRow(:final taskId):
        _selectTask(taskId);
      case TaskEntryRow(:final entry):
        _openEntryEditor(entry);
    }
  }

  void _focusDescription() => _descFocus.requestFocus();
  void _blurToCursor() => _cursorNode?.requestFocus();

  // e : edit the focused row (task or entry).
  void _editCursor() {
    if (_cursor >= _rows.length) return;
    switch (_rows[_cursor]) {
      case TaskHeaderRow(:final task):
        _openTaskEditor(task);
      case TaskEntryRow(:final entry):
        _openEntryEditor(entry);
    }
  }

  // Tracker scope = list nav + tracker actions + the global pane-switch
  // bindings. Owning the Ctrl-w chord here (the tracker owns the h/l keys that
  // complete it) closes the same silent gap the settings pane had. Space/t/`?`/
  // `/`/Tab/Ctrl-, bubble to the shell.
  static const _scopes = {KeyScope.list, KeyScope.tracker, KeyScope.global};

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    // While typing in the description field, keys belong to it — printable keys
    // bubble up here otherwise (e would fire edit, Enter would arm the cursor).
    // Esc is handled by the CallbackShortcuts wrapping the field.
    if (_descFocus.hasFocus) return KeyEventResult.ignored;

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
        _expandOrOpen();
      case KeyIntent.activate:
        _activateCursor();
      case KeyIntent.collapseOrParent:
        _collapseOrParent();
      case KeyIntent.editItem:
        _editCursor();
      case KeyIntent.addTask:
        _openTaskEditor(null);
      case KeyIntent.addEntry:
        _addEntryToCursor();
      case KeyIntent.finishSession:
        if (_c.hasSession) _finish();
      case KeyIntent.focusDescription:
        _focusDescription();
      case KeyIntent.focusTracker:
        widget.onFocusTracker?.call();
      case KeyIntent.focusPanel:
        widget.onFocusPanel?.call();
      default:
        // Space (toggleTimer), t, ?, /, Tab, Ctrl-, are the shell's — bubble.
        return false;
    }
    return true;
  }

  // A : add an entry to the focused row's task (task header or one of its
  // entries).
  void _addEntryToCursor() {
    if (_cursor >= _rows.length) return;
    switch (_rows[_cursor]) {
      case TaskHeaderRow(:final taskId):
        _openEntryEditor(null, taskId: taskId);
      case TaskEntryRow(:final task):
        _openEntryEditor(null, taskId: task.id);
    }
  }

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
      // Row isn't laid out (ListView.builder skips off-screen items) — e.g. a
      // gg/G jump. Approximate the offset, then refine once the row is built.
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

  @override
  Widget build(BuildContext context) {
    // Rebuild on every controller change (per-second tick, start/pause/finish).
    // Subscribing here in build — rather than a manual addListener in initState
    // — keeps the binding declarative and survives hot reload.
    // Flatten tasks + entries into the visible rows and keep the cursor valid.
    // Computed here (not in a stream builder) so the key handler can index it.
    _rows = buildTaskRows(
      tasks: _tasks,
      entries: _entries,
      isExpanded: _expanded.contains,
    );
    if (_cursor >= _rows.length) {
      _cursor = _rows.isEmpty ? 0 : _rows.length - 1;
    }

    // Reveal the in-progress task once its row is available (after recovery has
    // rebuilt the session and this project's tasks have loaded). Post-frame so
    // we don't setState mid-build; guarded to fire only once.
    if (!_revealedActiveTask && _c.hasSession) {
      final i = _rows.indexWhere(
        (r) => r is TaskHeaderRow && r.taskId == _c.boundTaskId,
      );
      if (i >= 0) {
        _revealedActiveTask = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpTo(i);
        });
      }
    }

    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final layout = LayoutBuilder(
          builder: (context, constraints) {
            // Size the counter to the content area (not the whole window), so
            // it isn't oversized next to the side panel.
            final counterSize = (constraints.maxWidth * 0.16).clamp(
              72.0,
              128.0,
            );
            return _body(context, counterSize);
          },
        );
        // Wide layout: hang the pane keymap off the shell-owned cursor node.
        // Narrow (drawer) has no cursor node, so the pane stays mouse-first.
        final node = _cursorNode;
        if (node == null) return layout;
        return Focus(focusNode: node, onKeyEvent: _onKey, child: layout);
      },
    );
  }

  Task? _taskById(String? id) {
    if (id == null) return null;
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  // Which task the timer is (or would be) tracking: the live session's bound
  // task, else the armed selection.
  String? get _activeTaskId => _c.hasSession ? _c.boundTaskId : _selectedTaskId;

  Widget _armedLabel(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.projectId == null) {
      return Text(
        'Select a project to start tracking',
        style: theme.textTheme.bodySmall,
      );
    }
    final task = _taskById(_activeTaskId);
    if (task == null) {
      return Text(
        'Pick or add a task below to start tracking.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      );
    }
    final label = _c.hasSession ? 'Tracking' : 'Ready';
    return Text.rich(
      TextSpan(
        children: [
          // Bold label + colon, then the task name at normal weight.
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: task.title,
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
        ],
      ),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _body(BuildContext context, double counterSize) {
    return Column(
      children: [
        Column(
          children: [
            // 1. Extracted Project Stream Element
            ProjectHeader(projectStream: _projectStream),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                Duration(seconds: _c.elapsed).hms,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: counterSize,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            TimerControls(
              running: _c.isRunning,
              hasSession: _c.hasSession,
              counter: _c.elapsed,
              // Gated on an armed task (except pause/resume of a live session),
              // so time is always tracked against a chosen task.
              onPrimary: _canPrimary
                  ? (_c.isRunning ? _pause : _startOrResume)
                  : null,
              onFinish: _c.hasSession ? _finish : null,
            ),
            const SizedBox(height: AppTokens.spaceLg),
            _armedLabel(context),
            const SizedBox(height: AppTokens.spaceLg),
            // Optional note for this session; becomes the entry's description on
            // finish. Esc returns to the row cursor; Enter starts if armed.
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _blurToCursor,
              },
              child: TextField(
                controller: _c.description,
                focusNode: _descFocus,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'What are you working on?',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_c.isRunning && _canPrimary) _startOrResume();
                  _blurToCursor();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceXl),
        // 2. Tasks section: header (add task + per-project Invoice action) + list
        if (widget.projectId != null) ...[
          _TasksHeader(
            projectStream: _projectStream,
            onInvoice: widget.onInvoice,
            onAddTask: () => _openTaskEditor(null),
          ),
          const Divider(),
        ],
        Expanded(
          child: StreamBuilder<(Project, Client)?>(
            stream: _projectStream,
            builder: (context, snap) {
              final data = snap.data;
              // Effective project/client rate; a task may override it per-row.
              final rate = data == null
                  ? null
                  : (data.$1.rate ?? data.$2.defaultRate);
              return TaskList(
                rows: _rows,
                rate: rate,
                selectedTaskId: _activeTaskId,
                cursor: _cursor,
                cursorActive: _cursorActive,
                cursorKey: _cursorKey,
                scrollController: _scroll,
                onSelectTask: _selectTask,
                onToggle: _toggleTask,
                onAddEntryToTask: (taskId) =>
                    _openEntryEditor(null, taskId: taskId),
                onEditTask: _openTaskEditor,
                onEditEntry: _openEntryEditor,
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- Component 1: Project Meta Header ---
class ProjectHeader extends StatelessWidget {
  final Stream<(Project, Client)?>? projectStream;

  const ProjectHeader({super.key, required this.projectStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<(Project, Client)?>(
      stream: projectStream,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final (project, client) = data;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            Text(
              '${client.name} : ${project.code}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              project.title,
              // Kept in Mona (not the Raleway titleLarge) — a running-timer
              // label, not a screen/dialog title.
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: AppTokens.fontFamily,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w300,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        );
      },
    );
  }
}

// --- Tasks section header: label + add-task + per-project Invoice action ---
class _TasksHeader extends StatelessWidget {
  final Stream<(Project, Client)?>? projectStream;
  final void Function(Project) onInvoice;
  final VoidCallback onAddTask;

  const _TasksHeader({
    required this.projectStream,
    required this.onInvoice,
    required this.onAddTask,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<(Project, Client)?>(
      stream: projectStream,
      builder: (context, snap) {
        final project = snap.data?.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
          child: Row(
            children: [
              Text('Tasks', style: theme.textTheme.titleMedium),
              const Spacer(),
              appIconButton(
                icon: Icons.add,
                iconSize: AppTokens.iconMd,
                tooltip: 'Add task (a)',
                onPressed: onAddTask,
              ),
              const SizedBox(width: AppTokens.spaceMd),
              TextButton.icon(
                // Disabled until the project has loaded.
                onPressed: project == null ? null : () => onInvoice(project),
                icon: const Icon(Icons.receipt_long, size: AppTokens.iconSm),
                label: const Text('Invoice'),
                // Strip padding so the label sits flush to the right edge.
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
