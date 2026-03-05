import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'task_queue.dart';
import 'workmanager_task_processor.dart';

// Task identifier for WorkManager
const String pendingTasksSyncTask = 'pendingTasksSync';
const String pendingTasksSyncTaskName = 'pending_tasks_sync';
const String _workManagerLockerId = 'workmanager';

/// Top-level callback dispatcher for WorkManager
/// This function is called when WorkManager triggers our task,
/// even if the app has been terminated.
@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('[WorkManager] ========================================');
    print('[WorkManager] Callback triggered!');
    print('[WorkManager] Task: $task');
    print('[WorkManager] ========================================');

    // Enable platform channel access in background isolate
    DartPluginRegistrant.ensureInitialized();

    // Ensure Flutter bindings are initialized for SharedPreferences
    WidgetsFlutterBinding.ensureInitialized();

    // Create TaskQueue instance for this isolate
    final taskQueue = TaskQueue();

    // Try to acquire the processing lock
    final lockAcquired = await taskQueue.acquireProcessingLock(_workManagerLockerId);

    if (!lockAcquired) {
      print('[WorkManager] Could not acquire lock, another processor is running');
      print('[WorkManager] Exiting - will retry when lock is available');
      return Future.value(true); // Return true to not retry immediately
    }

    try {
      // Read pending tasks from SharedPreferences
      final pendingTasks = await taskQueue.getPendingTasks();
      print('[WorkManager] Found ${pendingTasks.length} pending tasks');

      if (pendingTasks.isEmpty) {
        print('[WorkManager] No pending tasks to process');
        return Future.value(true);
      }

      // Initialize notifications with tap action support
      final notificationsPlugin = await WorkManagerTaskProcessor.initializeNotifications();

      // Create and run the processor
      final processor = WorkManagerTaskProcessor(
        taskQueue: taskQueue,
        notificationsPlugin: notificationsPlugin,
      );

      // Process all tasks
      final processed = await processor.processAllTasks();
      print('[WorkManager] Processed $processed tasks');

    } finally {
      // Always release the lock when done
      await taskQueue.releaseProcessingLock(_workManagerLockerId);
    }

    print('[WorkManager] Callback completed successfully');
    return Future.value(true);
  });
}

/// Initialize WorkManager
/// Call this once in main() before runApp()
Future<void> initializeWorkManager() async {
  print('[WorkManager] Initializing...');

  await Workmanager().initialize(
    workmanagerCallbackDispatcher,
    isInDebugMode: true, // Set to false in production
  );

  print('[WorkManager] Initialized successfully');
}

/// Register a one-off task to sync pending tasks when network is available
/// This task will be triggered by Android WorkManager when:
/// 1. Network becomes available
/// 2. Even if the app has been terminated
Future<void> registerPendingTasksSync() async {
  print('[WorkManager] Registering pending tasks sync...');

  await Workmanager().registerOneOffTask(
    pendingTasksSyncTaskName, // Unique name
    pendingTasksSyncTask, // Task identifier (matches in callback)
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingWorkPolicy.keep, // Don't replace existing
  );

  print('[WorkManager] Pending tasks sync registered');
}

/// Cancel the pending tasks sync task
/// Call this when app takes over processing or queue is empty
Future<void> cancelPendingTasksSync() async {
  print('[WorkManager] Cancelling pending tasks sync...');
  await Workmanager().cancelByUniqueName(pendingTasksSyncTaskName);
  print('[WorkManager] Pending tasks sync cancelled');
}
