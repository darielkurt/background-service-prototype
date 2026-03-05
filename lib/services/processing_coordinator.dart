import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'foreground_task_processor.dart';
import 'task_queue.dart';

/// Processing modes for task execution
enum ProcessingMode {
  idle,       // No processing happening
  foreground, // Processing in main isolate (app visible)
  background, // Processing in background service (app hidden)
}

/// Coordinates task processing between foreground and background modes
///
/// Responsibilities:
/// - Decide which mode to use based on app state
/// - Handle lifecycle changes and trigger handoffs
/// - Prevent duplicate processing
/// - Orchestrate transitions between modes
class ProcessingCoordinator {
  // Singleton pattern
  static final ProcessingCoordinator _instance = ProcessingCoordinator._internal();
  factory ProcessingCoordinator() => _instance;
  ProcessingCoordinator._internal();

  final ForegroundTaskProcessor _foregroundProcessor = ForegroundTaskProcessor();
  final FlutterBackgroundService _backgroundService = FlutterBackgroundService();
  final TaskQueue _taskQueue = TaskQueue();

  ProcessingMode _currentMode = ProcessingMode.idle;
  StreamSubscription? _handoffSubscription;
  bool _isInitialized = false;

  // Prevent duplicate handoff attempts
  bool _isHandoffInProgress = false;

  // Public getters
  ProcessingMode get currentMode => _currentMode;
  bool get isProcessing => _currentMode != ProcessingMode.idle;
  ForegroundTaskProcessor get foregroundProcessor => _foregroundProcessor;

  /// Initialize the coordinator
  Future<void> initialize() async {
    if (_isInitialized) {
      print('[Coordinator] Already initialized');
      return;
    }

    print('[Coordinator] Initializing...');

    // Listen to foreground processor completion
    _foregroundProcessor.progressStream.listen((event) {
      if (event['type'] == 'complete' || event['type'] == 'stopped') {
        print('[Coordinator] Foreground processor finished');
        _setMode(ProcessingMode.idle);
      }
    });

    // Listen to background service completion
    _backgroundService.on('workComplete').listen((event) {
      print('[Coordinator] Background service completed');
      _setMode(ProcessingMode.idle);
    });

    _isInitialized = true;
    print('[Coordinator] Initialized');
  }

  /// Handle app lifecycle state changes and trigger handoffs if needed
  Future<void> handleAppLifecycleChange(AppLifecycleState state) async {
    print('[Coordinator] Lifecycle changed: $state (current mode: $_currentMode)');

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground
        await _handleAppResumed();
        break;

      case AppLifecycleState.paused:
        // App is fully backgrounded - this is the ONLY state we handle for backgrounding
        // (ignore inactive and hidden to prevent duplicate handoffs)
        await _handleAppBackgrounded();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Ignore these states - only act on 'paused' for backgrounding
        print('[Coordinator] Ignoring $state (waiting for paused or resumed)');
        break;
    }
  }

  /// Start processing if there are pending tasks
  /// Chooses foreground or background mode based on isInForeground parameter
  Future<void> startProcessingIfNeeded({required bool isInForeground}) async {
    print('[Coordinator] startProcessingIfNeeded (isInForeground: $isInForeground)');

    // Check if already processing
    if (_currentMode != ProcessingMode.idle) {
      print('[Coordinator] Already processing in $_currentMode mode, ignoring');
      return;
    }

    // Check if there are pending tasks
    final pendingTasks = await _taskQueue.getPendingTasks();
    if (pendingTasks.isEmpty) {
      print('[Coordinator] No pending tasks, nothing to do');
      return;
    }

    print('[Coordinator] Found ${pendingTasks.length} pending tasks');

    // Choose mode based on app state
    if (isInForeground) {
      print('[Coordinator] Starting foreground processing');
      await _startForegroundProcessing();
    } else {
      print('[Coordinator] Starting background processing');
      await _startBackgroundProcessing();
    }
  }

  /// Handle app coming to foreground
  Future<void> _handleAppResumed() async {
    print('[Coordinator] App resumed (mode: $_currentMode)');

    // Reset handoff flag
    _isHandoffInProgress = false;

    if (_currentMode == ProcessingMode.background) {
      // Background is running, need to handoff to foreground
      print('[Coordinator] Background is running, initiating handoff to foreground');
      await _handoffToForeground();
    } else if (_currentMode == ProcessingMode.idle) {
      // Nothing running, check if there are pending tasks to start
      final pendingTasks = await _taskQueue.getPendingTasks();
      if (pendingTasks.isNotEmpty) {
        print('[Coordinator] Idle with pending tasks, starting foreground processing');
        await _startForegroundProcessing();
      } else {
        print('[Coordinator] Idle with no pending tasks');
      }
    }
    // If foreground is already running, do nothing
  }

  /// Handle app going to background
  Future<void> _handleAppBackgrounded() async {
    print('[Coordinator] App backgrounded (mode: $_currentMode)');

    // Prevent duplicate handoff attempts
    if (_isHandoffInProgress) {
      print('[Coordinator] Handoff already in progress, ignoring');
      return;
    }

    if (_currentMode == ProcessingMode.foreground) {
      // Foreground is running, need to handoff to background
      print('[Coordinator] Foreground is running, initiating handoff to background');
      _isHandoffInProgress = true;
      await _handoffToBackground();
      _isHandoffInProgress = false;
    }
    // If background is already running or idle, do nothing
  }

  /// Start foreground processing
  Future<void> _startForegroundProcessing() async {
    print('[Coordinator] Starting foreground processor...');

    // Safety check: ensure background service is not running
    final bgRunning = await _backgroundService.isRunning();
    if (bgRunning) {
      print('[Coordinator] ERROR: Cannot start foreground while background is running!');
      return;
    }

    // Safety check: don't start if already processing in foreground
    if (_foregroundProcessor.isProcessing) {
      print('[Coordinator] Foreground processor already running');
      return;
    }

    _setMode(ProcessingMode.foreground);

    // Start processing in foreground (non-blocking)
    _foregroundProcessor.startProcessing().catchError((error) {
      print('[Coordinator] Foreground processor error: $error');
      _setMode(ProcessingMode.idle);
    });
  }

  /// Start background processing
  Future<void> _startBackgroundProcessing() async {
    print('[Coordinator] Starting background service...');

    // Check if service is already running
    final isRunning = await _backgroundService.isRunning();
    if (isRunning) {
      print('[Coordinator] Background service already running');
      _setMode(ProcessingMode.background);
      return;
    }

    // Start the service
    await _backgroundService.startService();
    _setMode(ProcessingMode.background);
    print('[Coordinator] Background service started');
  }

  /// Handoff from foreground to background (immediate transfer)
  Future<void> _handoffToBackground() async {
    print('[Coordinator] === Handoff: Foreground → Background ===');

    // Stop foreground processor
    print('[Coordinator] Stopping foreground processor...');
    await _foregroundProcessor.stopProcessing();

    // Wait briefly for foreground to stop
    await Future.delayed(const Duration(milliseconds: 500));

    // Start background service to pick up remaining tasks
    print('[Coordinator] Starting background service...');
    await _startBackgroundProcessing();

    print('[Coordinator] === Handoff complete: Now in background mode ===');
  }

  /// Handoff from background to foreground (let background finish current task)
  Future<void> _handoffToForeground() async {
    print('[Coordinator] === Handoff: Background → Foreground ===');

    // Check if background service is actually running
    final isRunning = await _backgroundService.isRunning();
    if (!isRunning) {
      print('[Coordinator] Background service not running, starting foreground directly');
      _setMode(ProcessingMode.idle); // Reset mode first
      await _startForegroundProcessing();
      return;
    }

    // Request background service to stop after current task
    print('[Coordinator] Requesting background to stop after current task...');
    _backgroundService.invoke('requestHandoff', {});

    // Wait for handoff ready signal or timeout
    try {
      print('[Coordinator] Waiting for background handoff ready signal...');
      await _backgroundService
          .on('handoffReady')
          .first
          .timeout(const Duration(seconds: 10));
      print('[Coordinator] Background signaled handoff ready');
    } catch (e) {
      print('[Coordinator] Timeout waiting for handoff ready, proceeding anyway: $e');
    }

    // CRITICAL: Wait for background service to ACTUALLY stop before starting foreground
    print('[Coordinator] Waiting for background service to fully stop...');
    int attempts = 0;
    while (await _backgroundService.isRunning() && attempts < 20) {
      print('[Coordinator] Background still running, waiting... (attempt ${attempts + 1}/20)');
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
    }

    final stillRunning = await _backgroundService.isRunning();
    if (stillRunning) {
      print('[Coordinator] WARNING: Background service still running after 10 seconds!');
    } else {
      print('[Coordinator] Background service stopped successfully');
    }

    // Reset mode to idle before starting foreground
    _setMode(ProcessingMode.idle);

    // Start foreground processing
    print('[Coordinator] Starting foreground processor...');
    await _startForegroundProcessing();

    print('[Coordinator] === Handoff complete: Now in foreground mode ===');
  }

  /// Set the current mode and log the change
  void _setMode(ProcessingMode newMode) {
    if (_currentMode != newMode) {
      print('[Coordinator] Mode change: $_currentMode → $newMode');
      _currentMode = newMode;
    }
  }

  /// Cleanup
  void dispose() {
    _handoffSubscription?.cancel();
    _foregroundProcessor.dispose();
  }
}
