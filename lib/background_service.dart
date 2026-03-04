import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  // Simulate 10 tasks with 3-second delays
  int currentTask = 0;
  const int totalTasks = 10;

  Timer.periodic(const Duration(seconds: 3), (timer) async {
    if (currentTask >= totalTasks) {
      // Work complete!
      await _showNotification(
        notificationsPlugin,
        'Work Complete!',
        'All tasks finished',
        progress: 100,
      );

      // Notify UI
      service.invoke('workComplete');

      // Stop the service
      timer.cancel();
      await Future.delayed(const Duration(seconds: 2));
      service.stopSelf();
      return;
    }

    currentTask++;

    // Update notification
    await _showNotification(
      notificationsPlugin,
      'Processing...',
      'Task $currentTask/$totalTasks',
      progress: (currentTask / totalTasks * 100).toInt(),
    );

    // Notify UI of progress
    service.invoke('progress', {
      'current': currentTask,
      'total': totalTasks,
    });
  });
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
