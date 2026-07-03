import 'dart:async';
import 'package:flutter/material.dart';
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget detailView = switch (_detail) {
      _Tracker() => TimerView(
        db: widget.db,
        jobId: _selectedJobId,
        onInvoice: _invoiceJob,
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
    SidePanel panel({VoidCallback? before}) {
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
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= AppTokens.breakpointMd) {
          return Scaffold(
            body: Row(
              children: [
                Expanded(child: content),

                const VerticalDivider(
                  width: AppTokens.strokeThick,
                  color: AppTokens.colorBorder,
                ),

                SizedBox(width: 320, child: panel()),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Time Tracker')),
          endDrawer: Drawer(child: panel(before: () => Navigator.pop(context))),

          body: content,
        );
      },
    );
  }
}
