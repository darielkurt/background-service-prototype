// Task status enum
enum TaskStatus {
  pending,
  processing,
  complete,
  failed;

  // Serialize to string for JSON
  String toJson() => name;

  // Deserialize from string
  static TaskStatus fromJson(String value) {
    return TaskStatus.values.firstWhere((e) => e.name == value);
  }
}

// Task model
class Task {
  final String id;
  final TaskStatus status;
  final DateTime createdAt;
  final Map<String, dynamic>? data;

  Task({
    required this.id,
    required this.status,
    required this.createdAt,
    this.data,
  });

  // Factory constructor for creating new pending tasks
  factory Task.create({Map<String, dynamic>? data}) {
    return Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      data: data,
    );
  }

  // Copy with method for updating status
  Task copyWith({
    String? id,
    TaskStatus? status,
    DateTime? createdAt,
    Map<String, dynamic>? data,
  }) {
    return Task(
      id: id ?? this.id,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      data: data ?? this.data,
    );
  }

  // Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'data': data,
    };
  }

  // Deserialize from JSON
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      status: TaskStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}
