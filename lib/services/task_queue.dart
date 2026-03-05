import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';

/// Manages the queue of tasks to be processed
///
/// Uses SharedPreferences for persistence so that:
/// 1. Tasks survive app restarts
/// 2. Background isolate can access the same queue as foreground
class TaskQueue {
  // Singleton pattern
  static final TaskQueue _instance = TaskQueue._internal();
  factory TaskQueue() => _instance;
  TaskQueue._internal();

  static const String _storageKey = 'task_queue_v1';

  /// Add a new task to the queue
  Future<void> addTask(Task task) async {
    final tasks = await getAllTasks();
    tasks.add(task);
    await _saveTasks(tasks);
    print('[TaskQueue] Added task ${task.id}, total: ${tasks.length}');
  }

  /// Get all tasks with pending status
  Future<List<Task>> getPendingTasks() async {
    final tasks = await getAllTasks();
    return tasks.where((t) => t.status == TaskStatus.pending).toList();
  }

  /// Get all tasks regardless of status
  ///
  /// IMPORTANT: Calls reload() to ensure we get fresh data from disk,
  /// not cached data. This is critical for cross-isolate consistency.
  Future<List<Task>> getAllTasks() async {
    final prefs = await SharedPreferences.getInstance();

    // CRITICAL: Reload to get fresh data from disk (not cached)
    // This ensures foreground sees background's updates and vice versa
    await prefs.reload();

    final json = prefs.getString(_storageKey);

    if (json == null || json.isEmpty) {
      return [];
    }

    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('[TaskQueue] Error loading tasks: $e');
      return [];
    }
  }

  /// Get a specific task by ID
  Future<Task?> getTask(String taskId) async {
    final tasks = await getAllTasks();
    try {
      return tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  /// Update the status of a task
  Future<void> updateTaskStatus(String taskId, TaskStatus status) async {
    final tasks = await getAllTasks();
    final index = tasks.indexWhere((t) => t.id == taskId);

    if (index != -1) {
      tasks[index].status = status;
      await _saveTasks(tasks);
      print('[TaskQueue] Task $taskId status -> ${status.name}');
    } else {
      print('[TaskQueue] WARNING: Task $taskId not found for status update');
    }
  }

  /// Remove all completed tasks
  Future<void> clearCompleted() async {
    final tasks = await getAllTasks();
    final before = tasks.length;
    tasks.removeWhere((t) => t.status == TaskStatus.complete);
    await _saveTasks(tasks);
    final removed = before - tasks.length;
    print('[TaskQueue] Cleared $removed completed tasks');
  }

  /// Remove all tasks
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    print('[TaskQueue] Cleared all tasks');
  }

  /// Get count of tasks by status
  Future<int> countByStatus(TaskStatus status) async {
    final tasks = await getAllTasks();
    return tasks.where((t) => t.status == status).length;
  }

  /// Get total task count
  Future<int> getTotalCount() async {
    final tasks = await getAllTasks();
    return tasks.length;
  }

  /// Save tasks to SharedPreferences
  Future<void> _saveTasks(List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }
}
