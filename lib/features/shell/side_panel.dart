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
  });
  final AppDatabase db;
  final int? selectedJobId;
  final void Function(int)? onSelect; // select a job for the timer
  final void Function(Job) onEditJob;
  final void Function(int clientId) onAddJob; // add a job under this client
  final void Function(Client) onEditClient;
  final VoidCallback onAddClient;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();
  late final Stream<List<Job>> _jobsStream = widget.db.watchJobs();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchHeader(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v),
          onClear: _query.isEmpty ? null : _clearSearch,
          onAddClient: widget.onAddClient,
        ),
        Expanded(
          child: StreamBuilder<List<Client>>(
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
                    query: _query,
                    selectedJobId: widget.selectedJobId,
                    onSelectJob: widget.onSelect,
                    onEditJob: widget.onEditJob,
                    onAddJob: widget.onAddJob,
                    onEditClient: widget.onEditClient,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- Search field + Add-client button, pinned to the top of the panel ---
class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear; // null when there's nothing to clear
  final VoidCallback onAddClient;

  const _SearchHeader({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onAddClient,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Square left corners so the field sits flush to the panel border;
    // rounded on the right only.
    const fieldRadius = BorderRadius.horizontal(
      right: Radius.circular(AppTokens.radiusSm),
    );
    return Padding(
      // Left flush to the border; right inset matches the rows so the
      // Add-client + lands in the edit-button column. Top matches the content
      // pane's spaceLg inset so both panes start at the same height.
      padding: const EdgeInsets.fromLTRB(
        0,
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceXs,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: AppTokens.fontSizeSm),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                // Filled, no stroke: the fill gives the flush-left /
                // rounded-right shape, so there's no left border to leave a
                // hair against the panel edge.
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                // Icon aligned with the client chevron (~spaceMd from edge).
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(
                    left: AppTokens.spaceMd,
                    right: AppTokens.spaceXs,
                  ),
                  child: Icon(Icons.search, size: AppTokens.iconSm),
                ),
                prefixIconConstraints: const BoxConstraints(minHeight: 36),
                // Same cap as the prefix so the field height doesn't jump when
                // the clear button appears on input.
                suffixIconConstraints: const BoxConstraints(minHeight: 36),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: fieldRadius,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: fieldRadius,
                  borderSide: BorderSide.none,
                ),
                suffixIcon: onClear == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: AppTokens.iconSm),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Clear search',
                        onPressed: onClear,
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          // Tight, like the row edit buttons, so centres align in a column.
          IconButton(
            icon: const Icon(Icons.add),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Add client',
            onPressed: onAddClient,
          ),
        ],
      ),
    );
  }
}

// --- Extracted Layout & List Logic ---
class _SidePanelListView extends StatelessWidget {
  final List<Client> clients;
  final List<Job> jobs;
  final String query;
  final int? selectedJobId;
  final void Function(int)? onSelectJob;
  final void Function(Job) onEditJob;
  final void Function(int clientId) onAddJob;
  final void Function(Client) onEditClient;

  const _SidePanelListView({
    required this.clients,
    required this.jobs,
    required this.query,
    required this.selectedJobId,
    required this.onSelectJob,
    required this.onEditJob,
    required this.onAddJob,
    required this.onEditClient,
  });

  @override
  Widget build(BuildContext context) {
    final jobsByClient = <int, List<Job>>{};
    for (final j in jobs) {
      jobsByClient.putIfAbsent(j.clientId, () => []).add(j);
    }

    final q = query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    bool jobMatches(Job j) => '${j.code} ${j.title}'.toLowerCase().contains(q);

    // A client shows if its name matches, or any of its jobs do. On a name
    // hit we keep all its jobs; otherwise only the jobs that match.
    final visible = <(Client, List<Job>)>[];
    for (final c in clients) {
      final clientJobs = jobsByClient[c.id] ?? const <Job>[];
      if (!searching) {
        visible.add((c, clientJobs));
        continue;
      }
      final nameHit = c.name.toLowerCase().contains(q);
      final matched = clientJobs.where(jobMatches).toList();
      if (nameHit || matched.isNotEmpty) {
        visible.add((c, nameHit ? clientJobs : matched));
      }
    }

    if (clients.isEmpty) {
      return const _EmptyNote('No clients yet — add one above.');
    }
    if (visible.isEmpty) {
      return _EmptyNote('No matches for "${query.trim()}".');
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space4xs),
      children: [
        for (final (c, clientJobs) in visible)
          () {
            // Auto-expand while searching, and for the client that owns the
            // selected job — so a just-added (now-selected) job is visible
            // even if its client was collapsed.
            final hasSelected = clientJobs.any((j) => j.id == selectedJobId);
            final expanded = searching || hasSelected;
            return ClientGroupTile(
              // Key encodes the expansion drivers so a change rebuilds the
              // tile with the right initial state.
              key: PageStorageKey('${c.id}:$expanded'),
              client: c,
              clientJobs: clientJobs,
              initiallyExpanded: expanded,
              selectedJobId: selectedJobId,
              onSelectJob: onSelectJob,
              onEditJob: onEditJob,
              onAddJob: onAddJob,
              onEditClient: onEditClient,
            );
          }(),
      ],
    );
  }
}

// --- Small centred note for empty / no-match states ---
class _EmptyNote extends StatelessWidget {
  final String message;
  const _EmptyNote(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceXs,
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

// --- Extracted Parent Widget ---
class ClientGroupTile extends StatefulWidget {
  final Client client;
  final List<Job> clientJobs;
  final bool initiallyExpanded;
  final int? selectedJobId;
  final void Function(int)? onSelectJob;
  final void Function(Job) onEditJob;
  final void Function(int clientId) onAddJob;
  final void Function(Client) onEditClient;

  const ClientGroupTile({
    super.key,
    required this.client,
    required this.clientJobs,
    this.initiallyExpanded = false,
    required this.selectedJobId,
    required this.onSelectJob,
    required this.onEditJob,
    required this.onAddJob,
    required this.onEditClient,
  });

  @override
  State<ClientGroupTile> createState() => _ClientGroupTileState();
}

class _ClientGroupTileState extends State<ClientGroupTile> {
  late bool _isExpanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        dividerColor: AppTokens.colorBorder,
        splashColor: Colors.transparent,
        expansionTileTheme: const ExpansionTileThemeData(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        expansionAnimationStyle: AnimationStyle.noAnimation,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: 0,
        ),
        dense: true,
        minTileHeight: 36, // tighter client header (default is ~48)
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
              fontWeight: FontWeight.w400,
              color: theme.colorScheme.onSurface,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add),
                iconSize: AppTokens.iconMd,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Add job',
                onPressed: () => widget.onAddJob(widget.client.id),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              // Edit sits rightmost, aligning with the job rows' edit icon.
              IconButton(
                icon: const Icon(Icons.edit_note),
                iconSize: AppTokens.iconMd,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Edit client',
                onPressed: () => widget.onEditClient(widget.client),
              ),
            ],
          ),
        ),
        children: [
          for (final j in widget.clientJobs)
            JobRowItem(
              job: j,
              isSelected: j.id == widget.selectedJobId,
              onTap: () => widget.onSelectJob?.call(j.id),
              onEdit: () => widget.onEditJob(j),
            ),
          // Breathing space after the last job, before the client divider.
          const SizedBox(height: AppTokens.spaceSm),
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

  const JobRowItem({
    super.key,
    required this.job,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      selected: isSelected,
      // Left indent under the client; right inset matches the client header
      // (spaceMd) so the action icons line up in a column. Tight vertical
      // padding keeps job rows close together.
      contentPadding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.space3xs,
        AppTokens.spaceMd,
        AppTokens.space3xs,
      ),
      title: Text(
        '${job.code} - ${job.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: AppTokens.fontSizeXs,
          fontWeight: FontWeight.w300,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_note),
        iconSize: AppTokens.iconMd,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: 'Edit job',
        onPressed: onEdit,
      ),
      onTap: onTap,
    );
  }
}
