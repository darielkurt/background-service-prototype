import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'task_queue.dart';

class NetworkListener {
  final Connectivity _connectivity = Connectivity();
  final TaskQueue _taskQueue = TaskQueue();
  final FlutterBackgroundService _service = FlutterBackgroundService();

  StreamSubscription<ConnectivityResult>? _subscription;
  bool _isListening = false;

  // Start listening for network changes
  Future<void> startListening() async {
    if (_isListening) return;

    _isListening = true;

    // Check immediately on start
    await _checkAndStartService();

    // Listen for connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) async {
        await _onConnectivityChanged(result);
      },
    );
  }

  // Stop listening
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }

  // Handle connectivity changes
  Future<void> _onConnectivityChanged(ConnectivityResult result) async {
    print('[NetworkListener] Connectivity changed: $result');
    // Check if connection is available (wifi or mobile)
    final hasConnection = result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile;

    print('[NetworkListener] Has connection: $hasConnection');
    if (hasConnection) {
      await _checkAndStartService();
    }
  }

  // Check for pending tasks and start service if needed
  Future<void> _checkAndStartService() async {
    print('[NetworkListener] Checking if should start service...');

    // Check if service is already running
    final isRunning = await _service.isRunning();
    print('[NetworkListener] Service running: $isRunning');
    if (isRunning) {
      print('[NetworkListener] Service already running, skipping');
      return; // Don't start if already running
    }

    // Check if there are pending tasks
    final pendingTasks = await _taskQueue.getPendingTasks();
    print('[NetworkListener] Found ${pendingTasks.length} pending tasks');
    if (pendingTasks.isEmpty) {
      print('[NetworkListener] No pending tasks, skipping');
      return; // No tasks to process
    }

    // Start the background service
    print('[NetworkListener] Starting background service...');
    await _service.startService();
    print('[NetworkListener] Service started!');
  }

  // Manual trigger (for testing or UI button)
  Future<void> triggerServiceIfNeeded() async {
    await _checkAndStartService();
  }
}
