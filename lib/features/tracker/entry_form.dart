import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/deletions.dart';

// Add/edit/delete a time entry. Presented adaptively — a modal dialog on wide
// windows, a bottom sheet on narrow — by [showEntryEditor]. Time is entered as
// a start date-time plus a duration; end + seconds are derived on save.
Future<void> showEntryEditor(
  BuildContext context, {
  required AppDatabase db,
  required int jobId,
  TimeEntry? entry,
  int? initialTaskId, // preselect the task when adding under a specific one
}) {
  final wide = MediaQuery.sizeOf(context).width >= AppTokens.breakpointMd;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: EntryForm(
              db: db,
              jobId: jobId,
              entry: entry,
              initialTaskId: initialTaskId,
              onClose: () => Navigator.pop(ctx),
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // so it grows above the keyboard
    builder: (ctx) => Padding(
      // Lift the sheet clear of the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: EntryForm(
          db: db,
          jobId: jobId,
          entry: entry,
          initialTaskId: initialTaskId,
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    ),
  );
}

class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.db,
    required this.jobId,
    this.entry,
    this.initialTaskId,
    required this.onClose,
  });
  final AppDatabase db;
  final int jobId;
  final TimeEntry? entry; // null = create, set = edit
  final int? initialTaskId; // preselected task when adding
  final VoidCallback onClose; // pop the dialog/sheet (save, delete, or cancel)

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  // Which task this entry belongs to, chosen from a dropdown of the job's tasks.
  late int? _selectedTaskId = widget.entry?.taskId ?? widget.initialTaskId;
  List<Task> _tasks = const [];
  late final _description = TextEditingController(
    text: widget.entry?.description ?? '',
  );
  late DateTime _start = widget.entry?.startedAt ?? DateTime.now();
  // Empty (with a '0' hint) when adding; prefilled from the entry when editing.
  late final _hours = TextEditingController(
    text: widget.entry == null ? '' : '${widget.entry!.seconds ~/ 3600}',
  );
  late final _minutes = TextEditingController(
    text: widget.entry == null ? '' : '${(widget.entry!.seconds % 3600) ~/ 60}',
  );
  final _hoursFocus = FocusNode();
  final _minutesFocus = FocusNode();
  String? _taskError;
  String? _durationError;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    // Focusing a duration field selects its contents so typing overwrites
    // rather than appending (e.g. avoids "0" + "20" → "020").
    _selectAllOnFocus(_hoursFocus, _hours);
    _selectAllOnFocus(_minutesFocus, _minutes);
    // Load the job's tasks for the dropdown (they don't change mid-dialog).
    widget.db.watchTasksForJob(widget.jobId).first.then((tasks) {
      if (mounted) setState(() => _tasks = tasks);
    });
  }

  void _selectAllOnFocus(FocusNode node, TextEditingController c) {
    node.addListener(() {
      if (node.hasFocus) {
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    });
  }

  @override
  void dispose() {
    _description.dispose();
    _hours.dispose();
    _minutes.dispose();
    _hoursFocus.dispose();
    _minutesFocus.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final taskId = _selectedTaskId;
    final desc = _description.text.trim();
    // Empty means zero for that unit (validation still catches 0h 0m below).
    final hText = _hours.text.trim();
    final mText = _minutes.text.trim();
    final h = hText.isEmpty ? 0 : int.tryParse(hText);
    final m = mText.isEmpty ? 0 : int.tryParse(mText);

    // The form edits whole minutes only; keep the original sub-minute seconds
    // when editing so re-saving a timer entry doesn't truncate its duration —
    // and so a sub-minute entry (which shows as 0h 0m here) stays valid when
    // you edit only its description/task.
    final remainder = _isEdit ? widget.entry!.seconds % 60 : 0;
    var seconds = 0;
    String? durationError;
    if (h == null || h < 0 || m == null || m < 0 || m > 59) {
      durationError = 'Enter a valid duration';
    } else {
      seconds = (h * 60 + m) * 60 + remainder;
      // Validate the *total* (including retained seconds), so a sub-minute
      // entry isn't rejected on an edit that leaves 0h 0m untouched.
      if (seconds <= 0) durationError = 'Duration must be more than zero';
    }

    setState(() {
      _taskError = taskId == null ? 'Pick a task' : null;
      _durationError = durationError;
    });
    if (_taskError != null || durationError != null) return;
    final endedAt = _start.add(Duration(seconds: seconds));
    try {
      if (_isEdit) {
        await widget.db.updateEntry(
          id: widget.entry!.id,
          taskId: taskId!,
          description: desc.isEmpty ? null : desc,
          startedAt: _start,
          endedAt: endedAt,
          seconds: seconds,
        );
      } else {
        await widget.db.addEntry(
          jobId: widget.jobId,
          taskId: taskId!,
          description: desc.isEmpty ? null : desc,
          startedAt: _start,
          endedAt: endedAt,
          seconds: seconds,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save entry: $e')));
      }
      return;
    }
    if (mounted) widget.onClose();
  }

  Future<void> _confirmDelete() async {
    final deleted = await confirmDeleteEntry(context, widget.db, widget.entry!);
    if (deleted && mounted) widget.onClose();
  }

  // A borderless number field for the Duration box (hours or minutes).
  // The unit is a static trailing Text, not suffixText: InputDecoration's
  // suffixText is only opaque once the label floats (field focused or
  // non-empty), so an empty unfocused field would hide the unit entirely.
  Widget _durationField(
    TextEditingController c,
    FocusNode f,
    String unit,
  ) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: c,
          focusNode: f,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: '0',
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      const SizedBox(width: AppTokens.spaceXs),
      Text(
        unit,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final startLabel =
        '${loc.formatMediumDate(_start)} · '
        '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(_start))}';

    final form = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit ? 'Edit entry' : 'New entry',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppTokens.spaceXl),
          DropdownButtonFormField<int>(
            initialValue: _selectedTaskId,
            isExpanded: true,
            // Inset the arrow so it isn't flush against the field's edge.
            icon: const Padding(
              padding: EdgeInsets.only(right: AppTokens.spaceXs),
              child: Icon(Icons.arrow_drop_down),
            ),
            decoration: InputDecoration(
              labelText: 'Task',
              errorText: _taskError,
            ),
            items: [
              for (final t in _tasks)
                DropdownMenuItem(value: t.id, child: Text(t.title)),
            ],
            onChanged: (v) => setState(() => _selectedTaskId = v),
          ),
          const SizedBox(height: AppTokens.spaceXl),
          TextField(
            controller: _description,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'e.g. fixed the login bug',
            ),
          ),
          const SizedBox(height: AppTokens.spaceXl),
          // Start date-time — tap to pick date then time.
          InkWell(
            onTap: _pickStart,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Start'),
              child: Text(startLabel),
            ),
          ),
          const SizedBox(height: AppTokens.spaceXl),
          // One bordered "Duration" box; the h/m fields inside are borderless
          // (a thin divider separates them) so there's a single frame, not two.
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Duration',
              errorText: _durationError,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMd,
                vertical: AppTokens.spaceXs,
              ),
            ),
            child: SizedBox(
              height: AppTokens.iconLg,
              child: Row(
                children: [
                  Expanded(child: _durationField(_hours, _hoursFocus, 'hrs')),
                  const VerticalDivider(width: AppTokens.spaceLg),
                  Expanded(
                    child: _durationField(_minutes, _minutesFocus, 'mins'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceXl),
          Row(
            children: [
              if (_isEdit)
                TextButton(
                  onPressed: _confirmDelete,
                  child: const Text('Delete'),
                ),
              const Spacer(),
              OutlinedButton(
                onPressed: widget.onClose,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              FilledButton(
                onPressed: _submit,
                child: Text(_isEdit ? 'Save' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );

    // In edit mode, `d` triggers Delete (a focused field eats it while typing).
    return _isEdit
        ? DeleteHotkey(onDelete: _confirmDelete, child: form)
        : form;
  }
}
