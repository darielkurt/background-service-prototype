import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import 'workmanager_service.dart';

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
  static const String _lockKey = 'processing_lock_v1';
  static const String _stopRequestKey = 'workmanager_stop_request';
  static const int _lockTimeoutMinutes = 5;

  /// Add a new task to the queue
  Future<void> addTask(Task task) async {
    final tasks = await getAllTasks();
    tasks.add(task);
    await _saveTasks(tasks);
    print('[TaskQueue] Added task ${task.id}, total: ${tasks.length}');

    // Auto-register WorkManager task when tasks are added
    await registerPendingTasksSync();
  }

  // ============================================================
  // PROCESSING LOCK - Prevents duplicate processing
  // ============================================================

  /// Try to acquire the processing lock
  /// Returns true if lock was acquired, false if another processor holds it
  Future<bool> acquireProcessingLock(String lockerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final lockJson = prefs.getString(_lockKey);

    if (lockJson != null) {
      try {
        final lock = jsonDecode(lockJson) as Map<String, dynamic>;
        final existingLockerId = lock['lockerId'] as String;
        final timestamp = DateTime.parse(lock['timestamp'] as String);
        final age = DateTime.now().difference(timestamp);

        // Check if lock is stale (older than timeout)
        if (age.inMinutes < _lockTimeoutMinutes) {
          print('[TaskQueue] Lock held by $existingLockerId (${age.inSeconds}s old)');
          return false;
        }
        print('[TaskQueue] Stale lock from $existingLockerId expired, taking over');
      } catch (e) {
        print('[TaskQueue] Error parsing lock, will overwrite: $e');
      }
    }

    // Acquire the lock
    final lockData = {
      'lockerId': lockerId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_lockKey, jsonEncode(lockData));
    print('[TaskQueue] Lock acquired by $lockerId');
    return true;
  }

  /// Release the processing lock (only if we own it)
  Future<void> releaseProcessingLock(String lockerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final lockJson = prefs.getString(_lockKey);

    if (lockJson != null) {
      try {
        final lock = jsonDecode(lockJson) as Map<String, dynamic>;
        final existingLockerId = lock['lockerId'] as String;

        if (existingLockerId == lockerId) {
          await prefs.remove(_lockKey);
          print('[TaskQueue] Lock released by $lockerId');
        } else {
          print('[TaskQueue] Cannot release lock - owned by $existingLockerId, not $lockerId');
        }
      } catch (e) {
        print('[TaskQueue] Error releasing lock: $e');
        await prefs.remove(_lockKey);
      }
    }
  }

  /// Get the current lock holder (or null if no lock)
  Future<String?> getProcessingLockHolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final lockJson = prefs.getString(_lockKey);

    if (lockJson == null) return null;

    try {
      final lock = jsonDecode(lockJson) as Map<String, dynamic>;
      return lock['lockerId'] as String?;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // STOP REQUEST - Allows app to signal WorkManager to stop
  // ============================================================

  /// Request WorkManager to stop processing
  Future<void> requestWorkManagerStop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stopRequestKey, true);
    print('[TaskQueue] WorkManager stop requested');
  }

  /// Check if a stop has been requested
  Future<bool> isStopRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(_stopRequestKey) ?? false;
  }

  /// Clear the stop request flag
  Future<void> clearStopRequest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stopRequestKey);
    print('[TaskQueue] Stop request cleared');
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
