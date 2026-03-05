/// Status of a task in the processing queue
enum TaskStatus {
  pending,    // Waiting to be processed
  processing, // Currently being processed
  complete,   // Successfully processed
}

/// Represents a task that can be processed either in foreground or background
class Task {
  final String id;
  TaskStatus status;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  Task({
    required this.id,
    this.status = TaskStatus.pending,
    this.data = const {},
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Create a copy with updated status
  Task copyWith({TaskStatus? status}) {
    return Task(
      id: id,
      status: status ?? this.status,
      data: data,
      createdAt: createdAt,
    );
  }

  /// Serialize to JSON for persistence
  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Deserialize from JSON
  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    status: TaskStatus.values.byName(json['status'] as String),
    data: (json['data'] as Map<String, dynamic>?) ?? {},
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  @override
  String toString() => 'Task(id: $id, status: ${status.name})';
}
