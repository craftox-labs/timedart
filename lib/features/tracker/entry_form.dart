import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/app_date_picker.dart';
import 'package:timedart/widgets/dropdown_field.dart';
import 'package:timedart/widgets/entity_editor.dart';
import 'package:timedart/features/deletions.dart';

// Add/edit/delete a time entry, in the shared adaptive entity-editor shell.
// Time is entered as a start date-time plus a duration; end + seconds are
// derived on save.
Future<void> showEntryEditor(
  BuildContext context, {
  required AppDatabase db,
  required String projectId,
  TimeEntry? entry,
  String? initialTaskId, // preselect the task when adding under a specific one
}) => showEntityEditor<void>(
  context,
  builder: (ctx) => EntryForm(
    db: db,
    projectId: projectId,
    entry: entry,
    initialTaskId: initialTaskId,
  ),
);

class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.db,
    required this.projectId,
    this.entry,
    this.initialTaskId,
  });
  final AppDatabase db;
  final String projectId;
  final TimeEntry? entry; // null = create, set = edit
  final String? initialTaskId; // preselected task when adding

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  // Which task this entry belongs to, chosen from a dropdown of the project's tasks.
  late String? _selectedTaskId = widget.entry?.taskId ?? widget.initialTaskId;
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
    // Load the project's tasks for the dropdown (they don't change mid-dialog).
    widget.db.watchTasksForProject(widget.projectId).first.then((tasks) {
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
    final date = await showAppDatePicker(
      context,
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
          projectId: widget.projectId,
          taskId: taskId!,
          description: desc.isEmpty ? null : desc,
          startedAt: _start,
          endedAt: endedAt,
          seconds: seconds,
        );
      } else {
        await widget.db.addEntry(
          projectId: widget.projectId,
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
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final deleted = await confirmDeleteEntry(context, widget.db, widget.entry!);
    if (deleted && mounted) Navigator.pop(context);
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

    return EntityForm(
      title: _isEdit ? 'Edit entry' : 'New entry',
      isEdit: _isEdit,
      submitLabel: _isEdit ? 'Save' : 'Add',
      onSubmit: _submit,
      onCancel: () => Navigator.pop(context),
      onDelete: _isEdit ? _confirmDelete : null,
      fields: [
        DropdownButtonFormField<String>(
          initialValue: _selectedTaskId,
          isExpanded: true,
          icon: kDropdownChevron,
          borderRadius: kDropdownMenuRadius,
          decoration: InputDecoration(
            label: requiredLabel(context, 'Task'),
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
            decoration: InputDecoration(label: requiredLabel(context, 'Start')),
            child: Text(startLabel),
          ),
        ),
        const SizedBox(height: AppTokens.spaceXl),
        // One bordered "Duration" box; the h/m fields inside are borderless
        // (a thin divider separates them) so there's a single frame, not two.
        InputDecorator(
          decoration: InputDecoration(
            label: requiredLabel(context, 'Duration'),
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
                Expanded(child: _durationField(_minutes, _minutesFocus, 'mins')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
