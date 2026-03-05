import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'task_queue.dart';
import 'processing_coordinator.dart';

/// Monitors network connectivity and triggers processing when connection restored
///
/// Milestone 3: Auto-trigger coordinator when network restores
class NetworkMonitor {
  // Singleton pattern
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;
  NetworkMonitor._internal();

  final Connectivity _connectivity = Connectivity();
  final TaskQueue _taskQueue = TaskQueue();
  final ProcessingCoordinator _coordinator = ProcessingCoordinator();

  StreamSubscription<ConnectivityResult>? _subscription;
  bool _wasDisconnected = false;
  bool _isInitialized = false;
  bool _isInForeground = true; // Assume foreground at start

  /// Initialize network monitoring
  Future<void> initialize() async {
    if (_isInitialized) {
      print('[NetworkMonitor] Already initialized');
      return;
    }

    print('[NetworkMonitor] Initializing...');

    // Check initial connectivity state
    final initialResult = await _connectivity.checkConnectivity();
    _wasDisconnected = !_hasConnection(initialResult);
    print('[NetworkMonitor] Initial state: ${_wasDisconnected ? "disconnected" : "connected"} ($initialResult)');

    // Subscribe to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    _isInitialized = true;
    print('[NetworkMonitor] Initialized');
  }

  /// Update the foreground state (called from lifecycle observer)
  void setForegroundState(bool isInForeground) {
    _isInForeground = isInForeground;
    print('[NetworkMonitor] Foreground state: $isInForeground');
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(ConnectivityResult result) {
    final hasConnection = _hasConnection(result);
    print('[NetworkMonitor] Connectivity changed: ${result.name}');

    if (hasConnection && _wasDisconnected) {
      // Connection restored!
      print('[NetworkMonitor] Connection RESTORED');
      _onConnectionRestored();
    } else if (!hasConnection && !_wasDisconnected) {
      print('[NetworkMonitor] Connection LOST');
    }

    _wasDisconnected = !hasConnection;
  }

  /// Check if the result indicates a connection
  bool _hasConnection(ConnectivityResult result) {
    return result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet;
  }

  /// Called when connection is restored after being disconnected
  Future<void> _onConnectionRestored() async {
    print('[NetworkMonitor] === CONNECTION RESTORED ===');

    // Check if there are pending tasks
    final pendingTasks = await _taskQueue.getPendingTasks();

    if (pendingTasks.isEmpty) {
      print('[NetworkMonitor] No pending tasks, nothing to trigger');
      return;
    }

    print('[NetworkMonitor] Found ${pendingTasks.length} pending tasks, triggering coordinator');

    // Trigger processing via coordinator
    // The coordinator will decide foreground vs background based on current state
    await _coordinator.startProcessingIfNeeded(isInForeground: _isInForeground);
  }

  /// Check current connectivity (useful for pre-flight checks)
  Future<bool> hasConnection() async {
    final result = await _connectivity.checkConnectivity();
    return _hasConnection(result);
  }

  /// Cleanup
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
    print('[NetworkMonitor] Disposed');
  }
}
