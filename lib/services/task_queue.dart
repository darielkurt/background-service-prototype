import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';

class TaskQueue {
  static const String _tasksKey = 'background_tasks';

  // Singleton pattern - ensures same instance across app
  static final TaskQueue _instance = TaskQueue._internal();
  factory TaskQueue() => _instance;
  TaskQueue._internal();

  // Add a new task
  Future<void> addTask(Task task) async {
    print('[TaskQueue] Adding task ${task.id}');
    final prefs = await SharedPreferences.getInstance();
    final tasks = await _loadTasks(prefs);
    tasks.add(task);
    await _saveTasks(prefs, tasks);
    print('[TaskQueue] Task ${task.id} saved. Total tasks: ${tasks.length}');
  }

  // Get all tasks
  Future<List<Task>> getAllTasks() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadTasks(prefs);
  }

  // Get only pending tasks
  Future<List<Task>> getPendingTasks() async {
    final tasks = await getAllTasks();
    final pending = tasks.where((t) => t.status == TaskStatus.pending).toList();
    print('[TaskQueue] getPendingTasks: ${pending.length} pending out of ${tasks.length} total');
    return pending;
  }

  // Update task status by ID
  Future<void> updateTaskStatus(String taskId, TaskStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    final tasks = await _loadTasks(prefs);

    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      tasks[index] = tasks[index].copyWith(status: status);
      await _saveTasks(prefs, tasks);
    }
  }

  // Get task count by status
  Future<int> getTaskCountByStatus(TaskStatus status) async {
    final tasks = await getAllTasks();
    return tasks.where((t) => t.status == status).length;
  }

  // Clear completed tasks
  Future<void> clearCompletedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasks = await _loadTasks(prefs);
    final activeTasks = tasks
        .where((t) =>
            t.status != TaskStatus.complete && t.status != TaskStatus.failed)
        .toList();
    await _saveTasks(prefs, activeTasks);
  }

  // Clear all tasks (for testing)
  Future<void> clearAllTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tasksKey);
  }

  // Private: Load tasks from shared_preferences
  Future<List<Task>> _loadTasks(SharedPreferences prefs) async {
    final String? tasksJson = prefs.getString(_tasksKey);
    if (tasksJson == null || tasksJson.isEmpty) {
      return [];
    }

    final List<dynamic> tasksList = jsonDecode(tasksJson);
    return tasksList.map((json) => Task.fromJson(json)).toList();
  }

  // Private: Save tasks to shared_preferences
  Future<void> _saveTasks(SharedPreferences prefs, List<Task> tasks) async {
    final tasksJson = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_tasksKey, tasksJson);
  }
}
