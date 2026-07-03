import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';

class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.db,
    this.selectedJobId,
    this.onSelect,
    required this.onEditJob,
    required this.onAddJob,
    required this.onEditClient,
    required this.onAddClient,
    required this.onInvoiceJob,
  });
  final AppDatabase db;
  final int? selectedJobId;
  final void Function(int)? onSelect; // select a job for the timer
  final void Function(Job) onEditJob;
  final void Function(int clientId) onAddJob; // add a job under this client
  final void Function(Client) onEditClient;
  final VoidCallback onAddClient;
  final void Function(Job) onInvoiceJob; // invoice a single job

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();
  late final Stream<List<Job>> _jobsStream = widget.db.watchJobs();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Client>>(
      stream: _clientsStream,
      builder: (context, clientSnap) {
        final clients = clientSnap.data ?? [];
        return StreamBuilder<List<Job>>(
          stream: _jobsStream,
          builder: (context, jobSnap) {
            final jobs = jobSnap.data ?? [];
            return _SidePanelListView(
              clients: clients,
              jobs: jobs,
              selectedJobId: widget.selectedJobId,
              onSelectJob: widget.onSelect,
              onEditJob: widget.onEditJob,
              onAddJob: widget.onAddJob,
              onEditClient: widget.onEditClient,
              onAddClient: widget.onAddClient,
              onInvoiceJob: widget.onInvoiceJob,
            );
          },
        );
      },
    );
  }
}

// --- Extracted Layout & List Logic ---
class _SidePanelListView extends StatelessWidget {
  final List<Client> clients;
  final List<Job> jobs;
  final int? selectedJobId;
  final void Function(int)? onSelectJob;
  final void Function(Job) onEditJob;
  final void Function(int clientId) onAddJob;
  final void Function(Client) onEditClient;
  final VoidCallback onAddClient;
  final void Function(Job) onInvoiceJob;

  const _SidePanelListView({
    required this.clients,
    required this.jobs,
    required this.selectedJobId,
    required this.onSelectJob,
    required this.onEditJob,
    required this.onAddJob,
    required this.onEditClient,
    required this.onAddClient,
    required this.onInvoiceJob,
  });

  @override
  Widget build(BuildContext context) {
    final jobsByClient = <int, List<Job>>{};
    for (final j in jobs) {
      jobsByClient.putIfAbsent(j.clientId, () => []).add(j);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space4xs),
      children: [
        if (clients.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceXs,
            ),
            child: Text(
              'No clients yet — add one below.',
              style: TextStyle(fontSize: AppTokens.fontSizeXs),
            ),
          ),
        for (final c in clients)
          ClientGroupTile(
            client: c,
            clientJobs: jobsByClient[c.id] ?? const <Job>[],
            selectedJobId: selectedJobId,
            onSelectJob: onSelectJob,
            onEditJob: onEditJob,
            onAddJob: onAddJob,
            onEditClient: onEditClient,
            onInvoiceJob: onInvoiceJob,
          ),
        const SizedBox(height: AppTokens.space2xs),
        AddClientButton(onTap: onAddClient),
      ],
    );
  }
}

// --- Extracted Add Client Button ---
class AddClientButton extends StatelessWidget {
  final VoidCallback onTap;

  const AddClientButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      contentPadding: const EdgeInsets.all(AppTokens.spaceMd),
      leading: const Icon(Icons.add, size: AppTokens.iconSm),
      horizontalTitleGap: AppTokens.spaceXs,
      title: const Text(
        'Add client',
        style: TextStyle(fontSize: AppTokens.fontSizeXs),
      ),
      onTap: onTap,
    );
  }
}

// --- Extracted Parent Widget ---
class ClientGroupTile extends StatefulWidget {
  final Client client;
  final List<Job> clientJobs;
  final int? selectedJobId;
  final void Function(int)? onSelectJob;
  final void Function(Job) onEditJob;
  final void Function(int clientId) onAddJob;
  final void Function(Client) onEditClient;
  final void Function(Job) onInvoiceJob;

  const ClientGroupTile({
    super.key,
    required this.client,
    required this.clientJobs,
    required this.selectedJobId,
    required this.onSelectJob,
    required this.onEditJob,
    required this.onAddJob,
    required this.onEditClient,
    required this.onInvoiceJob,
  });

  @override
  State<ClientGroupTile> createState() => _ClientGroupTileState();
}

class _ClientGroupTileState extends State<ClientGroupTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        dividerColor: theme.colorScheme.surfaceContainerHighest,
        splashColor: Colors.transparent,
        expansionTileTheme: const ExpansionTileThemeData(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
        ),
      ),
      child: ExpansionTile(
        key: PageStorageKey(widget.client.id),
        expansionAnimationStyle: AnimationStyle.noAnimation,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: 0,
        ),
        dense: true,
        showTrailingIcon: false,
        onExpansionChanged: (isExpanded) {
          setState(() {
            _isExpanded = isExpanded;
          });
        },
        title: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -4),
          contentPadding: EdgeInsets.zero,
          horizontalTitleGap: AppTokens.space2xs,
          leading: Icon(
            _isExpanded ? Icons.expand_more : Icons.chevron_right,
            size: AppTokens.iconSm,
            color: _isExpanded
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            widget.client.name,
            style: TextStyle(
              fontSize: AppTokens.fontSizeSm,
              fontWeight: FontWeight.w300,
              color: theme.colorScheme.onSurface,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_note),
            iconSize: AppTokens.iconSm,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit client',
            onPressed: () => widget.onEditClient(widget.client),
          ),
        ),
        children: [
          for (final j in widget.clientJobs)
            JobRowItem(
              job: j,
              isSelected: j.id == widget.selectedJobId,
              onTap: () => widget.onSelectJob?.call(j.id),
              onEdit: () => widget.onEditJob(j),
              onInvoice: () => widget.onInvoiceJob(j),
            ),
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -4),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceXs,
            ),
            leading: const Icon(Icons.add, size: AppTokens.iconXs),
            horizontalTitleGap: AppTokens.space2xs,
            title: const Text(
              'Add job',
              style: TextStyle(fontSize: AppTokens.fontSizeXs),
            ),
            onTap: () => widget.onAddJob(widget.client.id),
          ),
          const SizedBox(height: AppTokens.spaceXs),
        ],
      ),
    );
  }
}

// --- Extracted Child Widget ---
class JobRowItem extends StatelessWidget {
  final Job job;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onInvoice;

  const JobRowItem({
    super.key,
    required this.job,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onInvoice,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      selected: isSelected,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceXs,
      ),
      title: Text(
        '${job.code} - ${job.title}',
        style: const TextStyle(fontSize: AppTokens.fontSizeXs),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            iconSize: AppTokens.iconSm,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Invoice job',
            onPressed: onInvoice,
          ),
          const SizedBox(width: AppTokens.space3xs),
          IconButton(
            icon: const Icon(Icons.edit_note),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit job',
            onPressed: onEdit,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
