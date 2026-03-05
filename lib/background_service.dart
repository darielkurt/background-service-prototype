import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/task_queue.dart';
import 'models/task.dart';

// Initialize and configure the background service
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Create notification channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'background_service_channel',
    'Background Service',
    description: 'Shows progress of background work',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Configure the service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // Manual trigger only
      isForegroundMode: true, // Shows persistent notification
      notificationChannelId: 'background_service_channel',
      initialNotificationTitle: 'Background Work',
      initialNotificationContent: 'Initializing...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

// Background service entry point - runs in separate isolate
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // CRITICAL: Enable platform channel access in background isolate
  DartPluginRegistrant.ensureInitialized();

  print('[BackgroundService] Started');

  // Initialize notifications in the background isolate
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await notificationsPlugin.initialize(initializationSettings);

  // Create notification channel in background isolate
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'background_service_channel',
    'Background Service',
    description: 'Shows progress of background work',
    importance: Importance.low,
  );

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Flags for controlling the processing loop
  bool shouldStop = false;
  bool isHandoffRequested = false;

  // Listen for stop command from UI (immediate stop)
  service.on('stop').listen((event) {
    print('[BackgroundService] Stop command received');
    shouldStop = true;
  });

  // Listen for handoff request (graceful stop after current task)
  service.on('requestHandoff').listen((event) {
    print('[BackgroundService] Handoff requested - will stop after current task');
    isHandoffRequested = true;
    shouldStop = true;
  });

  // Create TaskQueue instance for this isolate
  final taskQueue = TaskQueue();

  // Process tasks from the queue
  await _processTasksLoop(
    service: service,
    taskQueue: taskQueue,
    notificationsPlugin: notificationsPlugin,
    shouldStopCallback: () => shouldStop,
    isHandoffRequestedCallback: () => isHandoffRequested,
  );
}

/// Main processing loop for background service
Future<void> _processTasksLoop({
  required ServiceInstance service,
  required TaskQueue taskQueue,
  required FlutterLocalNotificationsPlugin notificationsPlugin,
  required bool Function() shouldStopCallback,
  required bool Function() isHandoffRequestedCallback,
}) async {
  int totalProcessed = 0;

  while (true) {
    // Check if we should stop
    if (shouldStopCallback()) {
      print('[BackgroundService] Stop flag detected');

      if (isHandoffRequestedCallback()) {
        print('[BackgroundService] Emitting handoffReady signal');
        await _showNotification(
          notificationsPlugin,
          'Handing off...',
          'Transferring to foreground',
        );
        service.invoke('handoffReady', {
          'processedTasks': totalProcessed,
        });
      }

      await Future.delayed(const Duration(milliseconds: 500));
      print('[BackgroundService] Stopping service');
      service.stopSelf();
      return;
    }

    // Get pending tasks
    final pendingTasks = await taskQueue.getPendingTasks();

    if (pendingTasks.isEmpty) {
      print('[BackgroundService] No pending tasks, completing');
      await _showNotification(
        notificationsPlugin,
        'Work Complete!',
        'All $totalProcessed tasks finished',
      );
      service.invoke('workComplete', {
        'processedTasks': totalProcessed,
      });
      await Future.delayed(const Duration(seconds: 2));
      service.stopSelf();
      return;
    }

    final totalTasks = pendingTasks.length;
    print('[BackgroundService] Found $totalTasks pending tasks');

    // Process each task
    for (int i = 0; i < pendingTasks.length; i++) {
      // Check stop flag before each task
      if (shouldStopCallback()) {
        print('[BackgroundService] Stop requested, breaking loop');
        break;
      }

      final task = pendingTasks[i];
      print('[BackgroundService] Processing task ${i + 1}/$totalTasks (${task.id})');

      // Mark as processing
      await taskQueue.updateTaskStatus(task.id, TaskStatus.processing);

      // Update notification
      await _showNotification(
        notificationsPlugin,
        'Processing...',
        'Task ${i + 1}/$totalTasks',
        progress: ((i + 1) / totalTasks * 100).toInt(),
        maxProgress: 100,
      );

      // Notify UI of progress
      service.invoke('progress', {
        'current': i + 1,
        'total': totalTasks,
        'taskId': task.id,
      });

      // Simulate task work (3 seconds)
      await Future.delayed(const Duration(seconds: 3));

      // Check stop flag after work
      if (shouldStopCallback()) {
        // Mark current task as complete before stopping
        await taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
        totalProcessed++;
        print('[BackgroundService] Completed task before stopping');
        break;
      }

      // Mark as complete
      await taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
      totalProcessed++;
      print('[BackgroundService] Task ${task.id} completed');
    }

    // Small delay before checking for more tasks
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

// Helper to show/update notification
Future<void> _showNotification(
  FlutterLocalNotificationsPlugin plugin,
  String title,
  String body, {
  int? progress,
  int? maxProgress,
}) async {
  await plugin.show(
    888,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'background_service_channel',
        'Background Service',
        channelDescription: 'Shows progress of background work',
        importance: Importance.low,
        icon: '@mipmap/ic_launcher',
        ongoing: true,
        showProgress: progress != null && progress < 100,
        maxProgress: maxProgress ?? 100,
        progress: progress ?? 0,
      ),
    ),
  );
}
