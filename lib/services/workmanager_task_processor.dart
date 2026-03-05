import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'task_queue.dart';
import '../models/task.dart';

// Notification IDs for WorkManager (different from background service 888)
const int _progressNotificationId = 889;
const int _completionNotificationId = 890;
const String _channelId = 'workmanager_channel';
const String _channelName = 'WorkManager Tasks';

/// Standalone task processor for WorkManager isolate
/// Does not depend on flutter_background_service
class WorkManagerTaskProcessor {
  final TaskQueue _taskQueue;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  bool _shouldStop = false;

  WorkManagerTaskProcessor({
    required TaskQueue taskQueue,
    required FlutterLocalNotificationsPlugin notificationsPlugin,
  })  : _taskQueue = taskQueue,
        _notificationsPlugin = notificationsPlugin;

  /// Request the processor to stop after the current task
  void requestStop() {
    print('[WorkManagerProcessor] Stop requested');
    _shouldStop = true;
  }

  /// Process all pending tasks
  /// Returns the number of tasks processed
  Future<int> processAllTasks() async {
    print('[WorkManagerProcessor] Starting task processing...');
    int totalProcessed = 0;

    while (!_shouldStop) {
      // Get pending tasks
      final pendingTasks = await _taskQueue.getPendingTasks();

      if (pendingTasks.isEmpty) {
        print('[WorkManagerProcessor] No more pending tasks');
        break;
      }

      final totalTasks = pendingTasks.length;
      print('[WorkManagerProcessor] Found $totalTasks pending tasks');

      // Process each task
      for (int i = 0; i < pendingTasks.length; i++) {
        if (_shouldStop) {
          print('[WorkManagerProcessor] Stop flag detected, breaking');
          break;
        }

        // Check if app requested stop (via SharedPreferences)
        final stopRequested = await _taskQueue.isStopRequested();
        if (stopRequested) {
          print('[WorkManagerProcessor] App requested stop, breaking');
          _shouldStop = true;
          break;
        }

        final task = pendingTasks[i];
        final progress = i + 1;

        print('[WorkManagerProcessor] Processing task $progress/$totalTasks (${task.id})');

        // Mark as processing
        await _taskQueue.updateTaskStatus(task.id, TaskStatus.processing);

        // Show progress notification (tappable to open app)
        await _showProgressNotification(
          current: progress,
          total: totalTasks,
          taskId: task.id,
        );

        // Simulate task work (3 seconds - same as other processors)
        await Future.delayed(const Duration(seconds: 3));

        // Check stop flag after work
        if (_shouldStop) {
          // Complete current task before stopping
          await _taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
          totalProcessed++;
          print('[WorkManagerProcessor] Completed task ${task.id} before stopping');
          break;
        }

        // Check if app requested stop after work
        final stopRequestedAfter = await _taskQueue.isStopRequested();
        if (stopRequestedAfter) {
          // Complete current task before stopping
          await _taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
          totalProcessed++;
          print('[WorkManagerProcessor] App requested stop after task, completed ${task.id}');
          _shouldStop = true;
          break;
        }

        // Mark as complete
        await _taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
        totalProcessed++;
        print('[WorkManagerProcessor] Task ${task.id} completed');
      }

      // Small delay before checking for more tasks
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Show completion notification (tappable to open app)
    if (totalProcessed > 0 && !_shouldStop) {
      await _showCompletionNotification(totalProcessed);
    } else if (_shouldStop) {
      // Cancel notifications when stopping for handoff
      await cancelNotifications();
    }

    print('[WorkManagerProcessor] Processing complete. Total: $totalProcessed');
    return totalProcessed;
  }

  /// Initialize the notifications plugin with tap action support
  static Future<FlutterLocalNotificationsPlugin> initializeNotifications() async {
    print('[WorkManagerProcessor] Initializing notifications...');

    final plugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    // Initialize with callback for notification tap
    // When notification is tapped, the app will be launched
    final initialized = await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('[WorkManagerProcessor] Notification tapped! Payload: ${response.payload}');
        // The app will be brought to foreground automatically
        // The ProcessingCoordinator will handle the handoff
      },
    );
    print('[WorkManagerProcessor] Notifications initialized: $initialized');

    // Create notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Shows progress of WorkManager tasks',
      importance: Importance.high,
    );

    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      print('[WorkManagerProcessor] Notification channel created: $_channelId');
    } else {
      print('[WorkManagerProcessor] WARNING: Could not get Android plugin implementation');
    }

    return plugin;
  }

  Future<void> _showProgressNotification({
    required int current,
    required int total,
    required String taskId,
  }) async {
    final progress = ((current / total) * 100).toInt();
    print('[WorkManagerProcessor] Showing progress notification: $current/$total');

    try {
      await _notificationsPlugin.show(
        _progressNotificationId,
        'Processing Tasks...',
        'Task $current of $total - Tap to open app',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Shows progress of WorkManager tasks',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: true,
            showProgress: true,
            maxProgress: 100,
            progress: progress,
            icon: '@mipmap/ic_launcher',
            // These settings ensure the notification opens the app when tapped
            autoCancel: false,
            playSound: false,
            enableVibration: false,
          ),
        ),
        payload: 'progress_$taskId', // Payload for identifying the tap
      );
      print('[WorkManagerProcessor] Progress notification shown');
    } catch (e) {
      print('[WorkManagerProcessor] ERROR showing notification: $e');
    }
  }

  Future<void> _showCompletionNotification(int tasksCompleted) async {
    print('[WorkManagerProcessor] Showing completion notification: $tasksCompleted tasks');

    try {
      // Cancel the progress notification first
      await _notificationsPlugin.cancel(_progressNotificationId);

      await _notificationsPlugin.show(
        _completionNotificationId,
        'Tasks Complete!',
        '$tasksCompleted task${tasksCompleted > 1 ? 's' : ''} completed - Tap to open app',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Shows progress of WorkManager tasks',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: false,
            icon: '@mipmap/ic_launcher',
            // Allow auto-cancel when tapped
            autoCancel: true,
          ),
        ),
        payload: 'complete_$tasksCompleted', // Payload for identifying the tap
      );
      print('[WorkManagerProcessor] Completion notification shown');
    } catch (e) {
      print('[WorkManagerProcessor] ERROR showing completion notification: $e');
    }
  }

  /// Cancel all notifications from this processor
  Future<void> cancelNotifications() async {
    await _notificationsPlugin.cancel(_progressNotificationId);
    await _notificationsPlugin.cancel(_completionNotificationId);
    print('[WorkManagerProcessor] Notifications cancelled');
  }
}
