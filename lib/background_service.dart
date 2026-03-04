import 'dart:async';
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

  // Request notification permission for Android 13+
  final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImplementation?.requestNotificationsPermission();

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
  // Initialize notifications in the background isolate
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // IMPORTANT: Initialize the notification plugin in the background isolate
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

  // Listen for stop command from UI
  service.on('stop').listen((event) {
    service.stopSelf();
  });

  print('[BackgroundService] onStart called - service is starting!');

  // Initialize TaskQueue in background isolate
  final taskQueue = TaskQueue();
  print('[BackgroundService] TaskQueue initialized');

  int totalCompletedCount = 0;

  // Keep processing until no more pending tasks
  while (true) {
    // Get pending tasks on each iteration
    final pendingTasks = await taskQueue.getPendingTasks();
    print('[BackgroundService] Found ${pendingTasks.length} pending tasks');

    if (pendingTasks.isEmpty) {
      // No more tasks to process
      print('[BackgroundService] No pending tasks, finishing up');
      break;
    }

    final batchSize = pendingTasks.length;
    print('[BackgroundService] Processing batch of $batchSize tasks');

    // Process each task in this batch sequentially
    for (int i = 0; i < pendingTasks.length; i++) {
      final task = pendingTasks[i];
      print('[BackgroundService] Processing task ${i + 1}/$batchSize (ID: ${task.id})');

      // Update status to processing
      await taskQueue.updateTaskStatus(task.id, TaskStatus.processing);
      print('[BackgroundService] Task ${task.id} marked as processing');

      // Update notification - show current progress
      await _showNotification(
        notificationsPlugin,
        'Processing tasks...',
        'Task ${i + 1}/$batchSize',
        progress: ((i + 1) / batchSize * 100).toInt(),
      );
      print('[BackgroundService] Notification updated for task ${i + 1}/$batchSize');

      // Notify UI of progress
      service.invoke('progress', {
        'current': i + 1,
        'total': batchSize,
      });

      // Simulate task work (3 seconds delay)
      print('[BackgroundService] Starting 3-second work simulation...');
      await Future.delayed(const Duration(seconds: 3));

      // Mark as complete
      await taskQueue.updateTaskStatus(task.id, TaskStatus.complete);
      totalCompletedCount++;
      print('[BackgroundService] Task ${task.id} completed (${i + 1}/$batchSize in this batch, $totalCompletedCount total)');
    }

    print('[BackgroundService] Batch complete, checking for more tasks...');
  }

  // All tasks complete
  print('[BackgroundService] All tasks processed! Total: $totalCompletedCount');
  await _showNotification(
    notificationsPlugin,
    'All tasks complete!',
    '$totalCompletedCount tasks processed',
    progress: 100,
  );
  print('[BackgroundService] Completion notification shown');

  service.invoke('workComplete', {
    'completed': totalCompletedCount,
  });
  print('[BackgroundService] Notified UI of completion');

  // Wait 2 seconds then stop service
  await Future.delayed(const Duration(seconds: 2));
  print('[BackgroundService] Stopping service...');
  service.stopSelf();
}

// Helper to show/update notification
Future<void> _showNotification(
  FlutterLocalNotificationsPlugin plugin,
  String title,
  String body, {
  int? progress,
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
        ongoing: true, // Can't be dismissed while working
        showProgress: progress != null && progress < 100,
        maxProgress: 100,
        progress: progress ?? 0,
      ),
    ),
  );
}
