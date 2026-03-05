import 'dart:async';
import 'task_queue.dart';
import '../models/task.dart';

/// Processes tasks in the main isolate when app is in foreground
///
/// Mirrors the background service processing logic but:
/// - Runs in main isolate (not separate isolate)
/// - No notifications (user can see UI)
/// - Emits progress via StreamController
/// - Can be stopped gracefully
class ForegroundTaskProcessor {
  // Singleton pattern
  static final ForegroundTaskProcessor _instance = ForegroundTaskProcessor._internal();
  factory ForegroundTaskProcessor() => _instance;
  ForegroundTaskProcessor._internal();

  final TaskQueue _taskQueue = TaskQueue();
  final StreamController<Map<String, dynamic>> _progressController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isProcessing = false;
  bool _shouldStop = false;
  String? _currentTaskId;

  // Public getters
  bool get isProcessing => _isProcessing;
  String? get currentTaskId => _currentTaskId;
  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  /// Start processing pending tasks in foreground
  Future<void> startProcessing() async {
    if (_isProcessing) {
      print('[ForegroundProcessor] Already processing, ignoring start request');
      return;
    }

    print('[ForegroundProcessor] Starting foreground processing...');
    _isProcessing = true;
    _shouldStop = false;

    await _processLoop();

    _isProcessing = false;
    _currentTaskId = null;
    print('[ForegroundProcessor] Foreground processing stopped');
  }

  /// Stop processing after current task completes
  Future<void> stopProcessing() async {
    if (!_isProcessing) {
      print('[ForegroundProcessor] Not processing, ignoring stop request');
      return;
    }

    print('[ForegroundProcessor] Stop requested, will finish current task...');
    _shouldStop = true;
  }

  /// Main processing loop - mirrors background service logic
  Future<void> _processLoop() async {
    int totalCompletedCount = 0;

    // Keep processing until no more pending tasks or stop requested
    while (true) {
      // Check if stop requested
      if (_shouldStop) {
        print('[ForegroundProcessor] Stop flag set, exiting loop');
        _emitEvent('stopped', {'completed': totalCompletedCount});
        break;
      }

      // Get pending tasks on each iteration
      final pendingTasks = await _taskQueue.getPendingTasks();
      print('[ForegroundProcessor] Found ${pendingTasks.length} pending tasks');

      if (pendingTasks.isEmpty) {
        print('[ForegroundProcessor] No pending tasks, finishing up');
        break;
      }

      final batchSize = pendingTasks.length;
      print('[ForegroundProcessor] Processing batch of $batchSize tasks');

      // Process each task in this batch sequentially
      for (int i = 0; i < pendingTasks.length; i++) {
        // Check stop flag before each task
        if (_shouldStop) {
          print('[ForegroundProcessor] Stop requested during batch, exiting');
          _emitEvent('stopped', {'completed': totalCompletedCount});
          return;
        }

        final task = pendingTasks[i];
        _currentTaskId = task.id;
        print('[ForegroundProcessor] Processing task ${i + 1}/$batchSize (ID: ${task.id})');

        // Update status to processing
        await _taskQueue.updateTaskStatus(task.id, TaskStatus.processing);
        print('[ForegroundProcessor] Task ${task.id} marked as processing');

        // Emit progress event to UI
        _emitEvent('progress', {
          'current': i + 1,
          'total': batchSize,
          'taskId': task.id,
          'totalCompleted': totalCompletedCount,
        });

        // Simulate task work (3 seconds delay)
        // In production, this would be actual API calls or processing
        print('[ForegroundProcessor] Starting 3-second work simulation...');
        await Future.delayed(const Duration(seconds: 3));

        // Check stop flag after work
        if (_shouldStop) {
          print('[ForegroundProcessor] Stop requested after task work, marking complete and exiting');
          await _taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
          totalCompletedCount++;
          _emitEvent('stopped', {'completed': totalCompletedCount});
          return;
        }

        // Mark as complete
        await _taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
        totalCompletedCount++;
        print('[ForegroundProcessor] Task ${task.id} completed (${i + 1}/$batchSize in batch, $totalCompletedCount total)');
      }

      print('[ForegroundProcessor] Batch complete, checking for more tasks...');
    }

    // All tasks complete
    print('[ForegroundProcessor] All tasks processed! Total: $totalCompletedCount');
    _emitEvent('complete', {
      'completed': totalCompletedCount,
    });
  }

  /// Emit progress event to listeners
  void _emitEvent(String type, Map<String, dynamic> data) {
    if (!_progressController.isClosed) {
      _progressController.add({
        'type': type,
        ...data,
      });
    }
  }

  /// Cleanup - close stream controller
  void dispose() {
    _progressController.close();
  }
}
