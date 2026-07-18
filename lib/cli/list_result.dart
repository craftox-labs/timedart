/// A row in `list projects` — a live project with its stable UUID, human code
/// and title, and owning client.
class ProjectListItem {
  final String id;
  final String code;
  final String title;
  final String clientId;
  final String? clientName;
  final double? rate;
  final bool archived;

  const ProjectListItem({
    required this.id,
    required this.code,
    required this.title,
    required this.clientId,
    this.clientName,
    this.rate,
    this.archived = false,
  });
}

/// A row in `list clients` — a live client with its stable UUID, name, the
/// default rate its projects inherit, and its archived state.
class ClientListItem {
  final String id;
  final String name;
  final double defaultRate;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? abn;
  final bool archived;

  const ClientListItem({
    required this.id,
    required this.name,
    required this.defaultRate,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.abn,
    this.archived = false,
  });
}

/// A row in `list entries` — a live time entry with its UUID, tracked duration,
/// start/end timestamps, owning project/task and description. Entries have no
/// human name; the UUID is the only selector `entry edit`/`entry delete` accept.
class EntryListItem {
  final String id;
  final String projectId;
  final String? projectCode;
  final String? projectTitle;
  final String? taskId;
  final String? taskTitle;
  final String? description;
  final int seconds;
  final DateTime startedAt;
  final DateTime endedAt;

  const EntryListItem({
    required this.id,
    required this.projectId,
    this.projectCode,
    this.projectTitle,
    this.taskId,
    this.taskTitle,
    this.description,
    required this.seconds,
    required this.startedAt,
    required this.endedAt,
  });
}

/// A row in `list tasks` — a live task with its UUID, title, and owning project.
class TaskListItem {
  final String id;
  final String title;
  final String projectId;
  final String? projectCode;
  final String? projectTitle;
  final double? rate; // own rate; null = inherits the project's

  const TaskListItem({
    required this.id,
    required this.title,
    required this.projectId,
    this.projectCode,
    this.projectTitle,
    this.rate,
  });
}
