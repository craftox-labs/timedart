import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

// Add/edit/delete a time entry. Presented adaptively — a modal dialog on wide
// windows, a bottom sheet on narrow — by [showEntryEditor]. Time is entered as
// a start date-time plus a duration; end + seconds are derived on save.
Future<void> showEntryEditor(
  BuildContext context, {
  required AppDatabase db,
  required int jobId,
  TimeEntry? entry,
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
    required this.onClose,
  });
  final AppDatabase db;
  final int jobId;
  final TimeEntry? entry; // null = create, set = edit
  final VoidCallback onClose; // pop the dialog/sheet (save, delete, or cancel)

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  late final _task = TextEditingController(text: widget.entry?.task ?? '');
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
    _task.dispose();
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
    final task = _task.text.trim();
    // Empty means zero for that unit (validation still catches 0h 0m below).
    final hText = _hours.text.trim();
    final mText = _minutes.text.trim();
    final h = hText.isEmpty ? 0 : int.tryParse(hText);
    final m = mText.isEmpty ? 0 : int.tryParse(mText);

    setState(() {
      _taskError = task.isEmpty ? 'Enter a task' : null;
      if (h == null || h < 0 || m == null || m < 0 || m > 59) {
        _durationError = 'Enter a valid duration';
      } else if (h == 0 && m == 0) {
        _durationError = 'Duration must be more than zero';
      } else {
        _durationError = null;
      }
    });
    if (_taskError != null || _durationError != null) return;

    // The form edits whole minutes only; keep the original sub-minute seconds
    // when editing so renaming a timer entry doesn't truncate its duration.
    final remainder = _isEdit ? widget.entry!.seconds % 60 : 0;
    final seconds = (h! * 60 + m!) * 60 + remainder;
    final endedAt = _start.add(Duration(seconds: seconds));
    try {
      if (_isEdit) {
        await widget.db.updateEntry(
          id: widget.entry!.id,
          task: task,
          startedAt: _start,
          endedAt: endedAt,
          seconds: seconds,
        );
      } else {
        await widget.db.addEntry(
          jobId: widget.jobId,
          task: task,
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
    final ok = await confirmDelete(
      context,
      title: 'Delete entry?',
      message: '"${widget.entry!.task}" will be removed.',
    );
    if (!ok) return;
    try {
      await widget.db.deleteEntry(widget.entry!.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete entry: $e')));
      }
      return;
    }
    if (mounted) widget.onClose();
  }

  // A borderless number field for the Duration box (hours or minutes).
  Widget _durationField(
    TextEditingController c,
    FocusNode f,
    String suffix,
  ) => TextField(
    controller: c,
    focusNode: f,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      hintText: '0',
      suffixText: suffix,
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final startLabel =
        '${loc.formatMediumDate(_start)} · '
        '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(_start))}';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit ? 'Edit entry' : 'New entry',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppTokens.spaceXl),
          TextField(
            controller: _task,
            autofocus: !_isEdit,
            decoration: InputDecoration(
              labelText: 'Task',
              errorText: _taskError,
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
  }
}
