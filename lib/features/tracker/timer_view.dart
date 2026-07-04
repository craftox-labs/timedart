import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/tracker/timer_controls.dart';
import 'package:time_tracker/features/tracker/timer_session.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/tracker/task_rows.dart';
import 'package:time_tracker/features/tracker/task_list.dart';
import 'package:time_tracker/features/tracker/task_editor.dart';
import 'package:time_tracker/features/tracker/entry_form.dart';

/// Owns the running timer so it survives content-pane switches. Editing a
/// client/job or invoicing unmounts the tracker view, but the session and its
/// per-second ticker live here on the shell — so navigating away no longer
/// discards a running session. The view renders from this and listens for
/// repaints.
class TimerController extends ChangeNotifier {
  final _session = TimerSession();
  Timer? _ticker;
  // Optional description for the session in progress, becoming the finished
  // entry's description. Lives here so it survives content-pane switches.
  final description = TextEditingController();

  // Set by the mounted TimerView so a global Space can fire the primary action.
  // Null when no tracker is on screen.
  VoidCallback? primary;

  int get elapsed => _session.elapsed;
  bool get isRunning => _session.isRunning;
  bool get hasSession => _session.hasSession;
  int? get boundTaskId => _session.boundTaskId;

  void startOrResume(int? jobId, int? taskId) {
    if (_session.isRunning) return;
    _session.start(jobId, taskId, now: DateTime.now());
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _session.tick();
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _ticker?.cancel();
    _session.pause();
    notifyListeners();
  }

  /// Stop and return what to persist (or null when there's nothing). Does not
  /// clear, so a failed write can be retried against an intact session.
  FinishedSession? stop() {
    _ticker?.cancel();
    final result = _session.finish(now: DateTime.now());
    notifyListeners();
    return result;
  }

  void reset() {
    _session.reset();
    description.clear();
    notifyListeners();
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
    required this.jobId,
    required this.onInvoice,
    this.cursorFocusNode,
    this.controller,
  });
  final AppDatabase db;
  final int? jobId;
  final void Function(Job) onInvoice; // open the invoice view for this job
  // Keyboard cursor for the entry list (wide layout). When null, the pane has
  // no keymap — used by the narrow drawer layout, which is mouse-first.
  final FocusNode? cursorFocusNode;
  // Lets the shell trigger the primary action for a global Space binding.
  final TimerController? controller;

  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  // The session lives in the controller so it survives pane switches. When no
  // controller is supplied (standalone use) an internal one stands in.
  TimerController? _internalController;
  TimerController get _c =>
      widget.controller ?? (_internalController ??= TimerController());
  Stream<List<TimeEntry>>? _entriesStream; // entries for the selected job
  Stream<List<Task>>? _tasksStream; // tasks for the selected job
  Stream<(Job, Client)?>? _jobStream;

  // The task the timer will track against (armed by selecting it in the list).
  // The Start action is gated on this; a running session binds its task at
  // start, so changing this mid-run only affects the next session.
  int? _selectedTaskId;
  final _descFocus = FocusNode(debugLabel: 'sessionDescription');

  // The cursor navigates a flattened task/entry row list (mirrors the side
  // panel). _tasks/_entries mirror the latest stream emissions; _rows is
  // rebuilt each build and cached so the key handler can index it outside build.
  List<Task> _tasks = const [];
  List<TimeEntry> _entries = const [];
  StreamSubscription<List<Task>>? _tasksSub;
  StreamSubscription<List<TimeEntry>>? _entriesSub;
  final Set<int> _expanded = {}; // expanded task ids
  List<TaskListRow> _rows = const [];
  int _cursor = 0;
  final _cursorKey = GlobalKey(); // rides the focused row for ensureVisible
  final _scroll = ScrollController();
  static const _estRowHeight = 56.0; // rough row height for off-screen jumps
  bool _pendingG = false; // saw a bare 'g', awaiting the second for gg

  FocusNode? get _cursorNode => widget.cursorFocusNode;
  bool get _cursorActive => _cursorNode?.hasPrimaryFocus ?? false;

  @override
  void initState() {
    super.initState();
    _updateJobStream();
    _cursorNode?.addListener(_onFocusChanged);
    _c.primary = _primaryAction;
  }

  @override
  void didUpdateWidget(TimerView old) {
    super.didUpdateWidget(old);
    if (old.jobId != widget.jobId) _updateJobStream();
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
    _pendingG = false;
    if (mounted) setState(() {});
  }

  void _updateJobStream() {
    final id = widget.jobId;
    _jobStream = id == null ? null : widget.db.watchJobWithClient(id);
    _entriesStream = id == null ? null : widget.db.watchEntriesForJob(id);
    _tasksStream = id == null ? null : widget.db.watchTasksForJob(id);

    // Cache tasks + entries so the key handler can index the flattened rows
    // (rebuilt in build()). The cursor is clamped there against _rows.
    _entriesSub?.cancel();
    _tasksSub?.cancel();
    _entries = const [];
    _tasks = const [];
    _expanded.clear();
    _selectedTaskId = null; // a different job means a different task set
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

  void _selectTask(int taskId) =>
      setState(() => _selectedTaskId = taskId); // arm for the timer

  void _startOrResume() => _c.startOrResume(widget.jobId, _selectedTaskId);

  void _pause() => _c.pause();

  Future<void> _finish() async {
    final result = _c.stop();

    // Nothing to record (empty session, or no job/task was ever bound).
    if (result == null) {
      _c.reset();
      return;
    }

    final desc = _c.description.text.trim();
    try {
      // Await the write so a failure is caught rather than silently lost.
      await widget.db.addEntry(
        jobId: result.jobId,
        taskId: result.taskId,
        description: desc.isEmpty ? null : desc,
        startedAt: result.startedAt,
        endedAt: result.endedAt,
        seconds: result.seconds,
      );
      _c.reset();
    } catch (e) {
      // Keep the session intact so the user can retry instead of losing time.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save entry: $e')));
      }
    }
  }

  // Open the add/edit-entry editor (adaptive modal/sheet). entry == null adds;
  // taskId preselects the task when adding under a specific one.
  void _openEntryEditor(TimeEntry? entry, {int? taskId}) {
    final jobId = widget.jobId;
    if (jobId == null) return;
    showEntryEditor(
      context,
      db: widget.db,
      jobId: jobId,
      entry: entry,
      initialTaskId: taskId,
    );
  }

  // Open the add/edit-task editor. task == null adds.
  void _openTaskEditor(Task? task) {
    final jobId = widget.jobId;
    if (jobId == null) return;
    showTaskEditor(context, db: widget.db, jobId: jobId, task: task);
  }

  // Whether Start/Space can fire: pause/resume of an existing session is always
  // allowed; a fresh start needs a job and an armed task.
  bool get _canPrimary =>
      _c.isRunning ||
      _c.hasSession ||
      (widget.jobId != null && _selectedTaskId != null);

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

  void _toggleTask(int taskId) {
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    // While typing in the description field, keys belong to it — printable keys
    // bubble up here otherwise (e would fire edit, Enter would arm the cursor).
    // Esc is handled by the CallbackShortcuts wrapping the field.
    if (_descFocus.hasFocus) return KeyEventResult.ignored;

    final key = event.logicalKey;
    // Ctrl-combos (pane switching, Ctrl-w chord) are the shell's job — bubble.
    if (HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }

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

    // Tree nav: l/→ expand-or-open, h/← collapse-or-parent, Enter activate.
    if (key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.arrowRight) {
      _expandOrOpen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.arrowLeft) {
      _collapseOrParent();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activateCursor();
      return KeyEventResult.handled;
    }
    // Space is handled globally at the shell (works from any pane while the
    // tracker is in view), so it isn't bound here — it bubbles up.
    if (key == LogicalKeyboardKey.keyF) {
      if (_c.hasSession) _finish();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      _focusDescription(); // jump into the session description field
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyE) {
      _editCursor();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _openTaskEditor(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

  Task? _taskById(int? id) {
    if (id == null) return null;
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  // Which task the timer is (or would be) tracking: the live session's bound
  // task, else the armed selection.
  int? get _activeTaskId => _c.hasSession ? _c.boundTaskId : _selectedTaskId;

  Widget _armedLabel(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.jobId == null) {
      return Text(
        'Select a job to start tracking',
        style: theme.textTheme.bodySmall,
      );
    }
    final task = _taskById(_activeTaskId);
    if (task == null) {
      return Text(
        'Pick a task below to start tracking',
        style: theme.textTheme.bodySmall,
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
            // 1. Extracted Job Stream Element
            JobHeader(jobStream: _jobStream),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                Duration(seconds: _c.elapsed).hms,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: counterSize,
                  fontWeight: FontWeight.w300,
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
        const SizedBox(height: AppTokens.space2xl),
        // 2. Tasks section: header (add task + per-job Invoice action) + list
        if (widget.jobId != null) ...[
          _TasksHeader(
            jobStream: _jobStream,
            onInvoice: widget.onInvoice,
            onAddTask: () => _openTaskEditor(null),
          ),
          const Divider(),
        ],
        Expanded(
          child: StreamBuilder<(Job, Client)?>(
            stream: _jobStream,
            builder: (context, snap) {
              final data = snap.data;
              // Effective job/client rate; a task may override it per-row.
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

// --- Component 1: Job Meta Header ---
class JobHeader extends StatelessWidget {
  final Stream<(Job, Client)?>? jobStream;

  const JobHeader({super.key, required this.jobStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<(Job, Client)?>(
      stream: jobStream,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final (job, client) = data;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            Text(
              '${client.name} : ${job.code}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              job.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
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

// --- Tasks section header: label + add-task + per-job Invoice action ---
class _TasksHeader extends StatelessWidget {
  final Stream<(Job, Client)?>? jobStream;
  final void Function(Job) onInvoice;
  final VoidCallback onAddTask;

  const _TasksHeader({
    required this.jobStream,
    required this.onInvoice,
    required this.onAddTask,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<(Job, Client)?>(
      stream: jobStream,
      builder: (context, snap) {
        final job = snap.data?.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
          child: Row(
            children: [
              Text('Tasks', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: onAddTask,
                icon: const Icon(Icons.add, size: AppTokens.iconSm),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Add task',
              ),
              const SizedBox(width: AppTokens.spaceMd),
              TextButton.icon(
                // Disabled until the job has loaded.
                onPressed: job == null ? null : () => onInvoice(job),
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
