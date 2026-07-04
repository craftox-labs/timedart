import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/tracker/timer_controls.dart';
import 'package:time_tracker/features/tracker/timer_session.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/tracker/time_entry_list.dart';
import 'package:time_tracker/features/tracker/entry_form.dart';

/// Owns the running timer so it survives content-pane switches. Editing a
/// client/job or invoicing unmounts the tracker view, but the session and its
/// per-second ticker live here on the shell — so navigating away no longer
/// discards a running session. The view renders from this and listens for
/// repaints.
class TimerController extends ChangeNotifier {
  final _session = TimerSession();
  Timer? _ticker;
  // In-progress task title; kept here so a running session holds its label even
  // while the tracker is off-screen.
  final task = TextEditingController();

  // Set by the mounted TimerView so a global Space can fire the primary action
  // (with its focus-nudge). Null when no tracker is on screen.
  VoidCallback? primary;

  int get elapsed => _session.elapsed;
  bool get isRunning => _session.isRunning;
  bool get hasSession => _session.hasSession;

  void startOrResume(int? jobId) {
    if (_session.isRunning) return;
    _session.start(jobId, now: DateTime.now());
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
    task.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    task.dispose();
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
  final _taskFocus = FocusNode(debugLabel: 'taskField');
  Stream<List<TimeEntry>>? _entriesStream; // entries for the selected job
  Stream<(Job, Client)?>? _jobStream;

  // Keyboard cursor over the entry list. _entries mirrors the latest stream
  // emission so the key handler can index into it outside of build.
  List<TimeEntry> _entries = const [];
  StreamSubscription<List<TimeEntry>>? _entriesSub;
  int _cursor = 0;
  final _cursorKey = GlobalKey(); // rides the focused row for ensureVisible
  final _scroll = ScrollController();
  static const _estRowHeight = 64.0; // rough row height for off-screen jumps
  bool _pendingG = false; // saw a bare 'g', awaiting the second for gg

  FocusNode? get _cursorNode => widget.cursorFocusNode;
  bool get _cursorActive => _cursorNode?.hasPrimaryFocus ?? false;

  @override
  void initState() {
    super.initState();
    _updateJobStream();
    _cursorNode?.addListener(_onFocusChanged);
    _c.addListener(_onTimerChanged);
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
      prev?.removeListener(_onTimerChanged);
      if (prev?.primary == _primaryAction) prev?.primary = null;
      _c.addListener(_onTimerChanged);
      _c.primary = _primaryAction;
    }
  }

  @override
  void dispose() {
    _taskFocus.dispose();
    _entriesSub?.cancel();
    _scroll.dispose();
    _cursorNode?.removeListener(_onFocusChanged);
    _c.removeListener(_onTimerChanged);
    if (_c.primary == _primaryAction) _c.primary = null;
    // Only the internal fallback is ours to dispose; a shell-owned controller
    // outlives this view (that's the whole point).
    _internalController?.dispose();
    super.dispose();
  }

  // Repaint the focus ring when the cursor gains/loses focus.
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  // The controller drives per-second repaints and start/pause/finish state.
  void _onTimerChanged() {
    if (mounted) setState(() {});
  }

  void _updateJobStream() {
    final id = widget.jobId;
    _jobStream = id == null ? null : widget.db.watchJobWithClient(id);
    _entriesStream = id == null ? null : widget.db.watchEntriesForJob(id);

    // Cache entries so the keyboard cursor can index them. Clamp the cursor as
    // the list grows/shrinks (e.g. after a delete or a new finished session).
    _entriesSub?.cancel();
    _entries = const [];
    _cursor = 0;
    _entriesSub = _entriesStream?.listen((rows) {
      if (!mounted) return;
      setState(() {
        _entries = rows;
        if (_cursor >= _entries.length) {
          _cursor = _entries.isEmpty ? 0 : _entries.length - 1;
        }
      });
    });
  }

  void _startOrResume() => _c.startOrResume(widget.jobId);

  void _pause() => _c.pause();

  Future<void> _finish() async {
    final result = _c.stop();

    // Nothing to record (empty session, or no job was ever bound).
    if (result == null) {
      _c.reset();
      return;
    }

    final text = _c.task.text.trim();
    try {
      // Await the write so a failure is caught rather than silently lost.
      await widget.db.addEntry(
        jobId: result.jobId,
        task: text.isEmpty ? 'Untitled session' : text,
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

  // Open the add/edit-entry editor (adaptive modal/sheet). entry == null adds.
  void _openEntryEditor(TimeEntry? entry) {
    final jobId = widget.jobId;
    if (jobId == null) return;
    showEntryEditor(context, db: widget.db, jobId: jobId, entry: entry);
  }

  // The Space action mirrors the primary button (start/resume ⇄ pause) with one
  // extra guard: a *fresh* keyboard start needs a task, so Space can't quietly
  // create an "Untitled session". Pause/resume of an existing session is fine.
  // (The Start button itself is intentionally not gated — Space only.)
  void _primaryAction() {
    if (widget.jobId == null) return;
    if (_c.isRunning) {
      _pause();
      return;
    }
    if (!_c.hasSession && _c.task.text.trim().isEmpty) {
      _focusTask(); // nudge into the field instead of starting untitled
      return;
    }
    _startOrResume();
  }

  // --- Entry-list keyboard cursor (wide layout) ---

  void _moveCursor(int delta) {
    if (_entries.isEmpty) return;
    final next = (_cursor + delta).clamp(0, _entries.length - 1);
    if (next != _cursor) {
      setState(() => _cursor = next);
      _ensureVisible();
    }
  }

  void _jumpTo(int index) {
    if (_entries.isEmpty) return;
    final next = index.clamp(0, _entries.length - 1);
    if (next != _cursor) {
      setState(() => _cursor = next);
      _ensureVisible();
    }
  }

  void _openCursorEntry() {
    if (_cursor < _entries.length) _openEntryEditor(_entries[_cursor]);
  }

  void _focusTask() => _taskFocus.requestFocus();
  void _blurToCursor() => _cursorNode?.requestFocus();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    // While typing in the task field, keys belong to it. Esc is handled by the
    // CallbackShortcuts wrapping the field (reliable, like the panel's search).
    if (_taskFocus.hasFocus) return KeyEventResult.ignored;

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
        _jumpTo(_entries.length - 1);
      } else if (_pendingG) {
        _pendingG = false;
        _jumpTo(0);
      } else {
        _pendingG = true;
      }
      return KeyEventResult.handled;
    }
    _pendingG = false; // any other key breaks a half-typed gg

    // Open the focused entry: Enter / l / →.
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.arrowRight) {
      _openCursorEntry();
      return KeyEventResult.handled;
    }
    // Space is handled globally at the shell (works from any pane while the
    // tracker is in view), so it isn't bound here — it bubbles up.
    if (key == LogicalKeyboardKey.keyF) {
      if (_c.hasSession) _finish();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      _focusTask();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _openEntryEditor(null);
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
    final layout = LayoutBuilder(
      builder: (context, constraints) {
        // Size the counter to the content area (not the whole window), so it
        // isn't oversized next to the side panel.
        final counterSize = (constraints.maxWidth * 0.16).clamp(72.0, 128.0);
        return _body(context, counterSize);
      },
    );
    // Wide layout: hang the pane keymap off the shell-owned cursor node. Narrow
    // (drawer) has no cursor node, so the pane stays mouse-first.
    final node = _cursorNode;
    if (node == null) return layout;
    return Focus(focusNode: node, onKeyEvent: _onKey, child: layout);
  }

  Widget _body(BuildContext context, double counterSize) {
    return Column(
      children: [
        Column(
          children: [
            // 1. Extracted Job Stream Element
            JobHeader(jobStream: _jobStream),
            const SizedBox(height: AppTokens.spaceSm),
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
            const SizedBox(height: AppTokens.spaceMd),
            TimerControls(
              running: _c.isRunning,
              hasSession: _c.hasSession,
              counter: _c.elapsed,
              // No job selected → disable start so time can't be tracked
              // against nothing (and later silently discarded).
              onPrimary: widget.jobId == null
                  ? null
                  : (_c.isRunning ? _pause : _startOrResume),
              onFinish: _c.hasSession ? _finish : null,
            ),
            const SizedBox(height: AppTokens.space2xl), // match input→history
            if (widget.jobId == null) ...[
              Text(
                'Select a job to start tracking',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            // Esc blurs the field back to the entry cursor (mirrors the panel).
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _blurToCursor,
              },
              child: TextField(
                controller: _c.task,
                focusNode: _taskFocus,
                decoration: const InputDecoration(
                  hintText: 'What are you working on?',
                  labelText: 'Task',
                ),
                textInputAction: TextInputAction.done,
                // Return starts (if idle) and hands focus back to the entry
                // cursor, so Space immediately pauses/resumes from there.
                onSubmitted: (_) {
                  if (!_c.isRunning) _startOrResume();
                  _blurToCursor();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space2xl),
        // 2. Entries section: header (with the per-job Invoice action) + list
        if (widget.jobId != null) ...[
          _EntriesHeader(
            jobStream: _jobStream,
            onInvoice: widget.onInvoice,
            onAddEntry: () => _openEntryEditor(null),
          ),
          const Divider(),
        ],
        Expanded(
          child: EntryHistoryList(
            entries: _entries,
            jobStream: _jobStream,
            onEditEntry: _openEntryEditor,
            cursor: _cursor,
            cursorActive: _cursorActive,
            cursorKey: _cursorKey,
            scrollController: _scroll,
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

// --- Entries section header: label + per-job Invoice action ---
class _EntriesHeader extends StatelessWidget {
  final Stream<(Job, Client)?>? jobStream;
  final void Function(Job) onInvoice;
  final VoidCallback onAddEntry;

  const _EntriesHeader({
    required this.jobStream,
    required this.onInvoice,
    required this.onAddEntry,
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
              Text('Entries', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: onAddEntry,
                icon: const Icon(Icons.add, size: AppTokens.iconSm),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Add entry',
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

// --- Component 2: Isolated Entries List ---
class EntryHistoryList extends StatelessWidget {
  final List<TimeEntry> entries; // cached by TimerView (drives the key cursor)
  final Stream<(Job, Client)?>? jobStream; // for the effective rate
  final void Function(TimeEntry) onEditEntry;
  final int cursor; // index of the keyboard cursor
  final bool cursorActive; // whether the cursor's focus ring should show
  final Key? cursorKey; // rides the cursor row for ensureVisible
  final ScrollController? scrollController;

  const EntryHistoryList({
    super.key,
    required this.entries,
    required this.jobStream,
    required this.onEditEntry,
    this.cursor = 0,
    this.cursorActive = false,
    this.cursorKey,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<(Job, Client)?>(
      stream: jobStream,
      builder: (context, jobSnap) {
        final data = jobSnap.data;
        // Effective rate: the job's own rate, else the client default.
        final rate = data == null ? null : (data.$1.rate ?? data.$2.defaultRate);
        return TimeEntryList(
          entries: entries,
          rate: rate,
          onEditEntry: onEditEntry,
          cursor: cursor,
          cursorActive: cursorActive,
          cursorKey: cursorKey,
          scrollController: scrollController,
        );
      },
    );
  }
}
