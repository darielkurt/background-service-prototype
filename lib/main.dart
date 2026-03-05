import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'background_service.dart';
import 'services/processing_coordinator.dart';
import 'services/task_queue.dart';
import 'services/network_monitor.dart';
import 'models/task.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background service
  await initializeBackgroundService();

  // Initialize processing coordinator
  await ProcessingCoordinator().initialize();

  // Initialize network monitor
  await NetworkMonitor().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Work POC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BackgroundWorkDemo(),
    );
  }
}

class BackgroundWorkDemo extends StatefulWidget {
  const BackgroundWorkDemo({super.key});

  @override
  State<BackgroundWorkDemo> createState() => _BackgroundWorkDemoState();
}

class _BackgroundWorkDemoState extends State<BackgroundWorkDemo>
    with WidgetsBindingObserver {
  final FlutterBackgroundService _service = FlutterBackgroundService();
  final ProcessingCoordinator _coordinator = ProcessingCoordinator();
  final TaskQueue _taskQueue = TaskQueue();
  final NetworkMonitor _networkMonitor = NetworkMonitor();

  String _status = 'Ready';
  int _currentTask = 0;
  int _totalTasks = 0;
  bool _isWorking = false;
  int _pendingCount = 0;
  int _taskIdCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToService();
    _listenToForegroundProcessor();
    _updateQueueStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[Main] App lifecycle changed: $state');
    _coordinator.handleAppLifecycleChange(state);

    // Update network monitor's foreground state
    final isInForeground = state == AppLifecycleState.resumed;
    _networkMonitor.setForegroundState(isInForeground);

    // Update UI when app resumes
    if (state == AppLifecycleState.resumed) {
      _updateQueueStatus();
      _updateProcessingState();
    }
  }

  void _listenToService() {
    // Listen for background service progress updates
    _service.on('progress').listen((event) {
      if (mounted && event != null) {
        setState(() {
          _currentTask = event['current'] ?? 0;
          _totalTasks = event['total'] ?? 10;
          _status = 'Background: Task $_currentTask/$_totalTasks';
          _isWorking = true;
        });
      }
    });

    // Listen for background service completion
    _service.on('workComplete').listen((event) {
      if (mounted) {
        setState(() {
          _status = 'Background work complete!';
          _isWorking = false;
        });
        _updateQueueStatus();
      }
    });
  }

  void _listenToForegroundProcessor() {
    // Listen for foreground processor progress updates
    _coordinator.foregroundProcessor.progressStream.listen((event) {
      if (mounted) {
        final type = event['type'];
        if (type == 'progress') {
          setState(() {
            _currentTask = event['current'] ?? 0;
            _totalTasks = event['total'] ?? 0;
            _status = 'Foreground: Task $_currentTask/$_totalTasks';
            _isWorking = true;
          });
        } else if (type == 'complete') {
          setState(() {
            _status = 'Foreground work complete!';
            _isWorking = false;
          });
          _updateQueueStatus();
        } else if (type == 'stopped') {
          setState(() {
            _status = 'Foreground stopped (handoff)';
            _isWorking = false;
          });
        }
      }
    });
  }

  Future<void> _updateQueueStatus() async {
    final pending = await _taskQueue.getPendingTasks();
    if (mounted) {
      setState(() {
        _pendingCount = pending.length;
      });
    }
  }

  void _updateProcessingState() {
    setState(() {
      _isWorking = _coordinator.isProcessing;
    });
  }

  Future<void> _requestNotificationPermission() async {
    final FlutterLocalNotificationsPlugin notificationsPlugin =
        FlutterLocalNotificationsPlugin();

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final bool? granted =
        await androidImplementation?.requestNotificationsPermission();

    if (granted == false) {
      if (mounted) {
        setState(() {
          _status = 'Notification permission denied';
        });
      }
    }
  }

  Future<void> _addTask() async {
    _taskIdCounter++;
    final task = Task(id: 'task_$_taskIdCounter');
    await _taskQueue.addTask(task);
    await _updateQueueStatus();
    if (mounted) {
      setState(() {
        _status = 'Added task ${task.id}';
      });
    }
  }

  Future<void> _addMultipleTasks() async {
    for (int i = 0; i < 5; i++) {
      _taskIdCounter++;
      final task = Task(id: 'task_$_taskIdCounter');
      await _taskQueue.addTask(task);
    }
    await _updateQueueStatus();
    if (mounted) {
      setState(() {
        _status = 'Added 5 tasks';
      });
    }
  }

  Future<void> _startProcessing() async {
    await _requestNotificationPermission();

    if (_coordinator.isProcessing) {
      setState(() {
        _status = 'Already processing';
      });
      return;
    }

    setState(() {
      _status = 'Starting processing...';
      _isWorking = true;
    });

    // Start processing in foreground (app is visible)
    await _coordinator.startProcessingIfNeeded(isInForeground: true);
  }

  Future<void> _stopProcessing() async {
    if (_coordinator.currentMode == ProcessingMode.foreground) {
      await _coordinator.foregroundProcessor.stopProcessing();
    } else if (_coordinator.currentMode == ProcessingMode.background) {
      _service.invoke('stop');
    }
    setState(() {
      _isWorking = false;
      _status = 'Stopped';
    });
  }

  Future<void> _clearTasks() async {
    await _taskQueue.clearAll();
    await _updateQueueStatus();
    setState(() {
      _status = 'Cleared all tasks';
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        _totalTasks > 0 ? _currentTask / _totalTasks : 0.0;
    final modeText = _coordinator.currentMode.name;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Background Work POC'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Phase 2: Coordinator Demo',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Queue Status
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Column(
                  children: [
                    Text(
                      'Pending Tasks: $_pendingCount',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Mode: $modeText'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Add Task Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addTask,
                      icon: const Icon(Icons.add),
                      label: const Text('Add 1 Task'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addMultipleTasks,
                      icon: const Icon(Icons.add_box),
                      label: const Text('Add 5 Tasks'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _clearTasks,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear All Tasks'),
              ),
              const SizedBox(height: 24),

              // Status
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      'Status: $_status',
                      style: const TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    if (_isWorking) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text(
                        '${(progress * 100).toInt()}% complete',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Start/Stop Buttons
              ElevatedButton.icon(
                onPressed: _isWorking ? null : _startProcessing,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Processing'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_isWorking)
                OutlinedButton.icon(
                  onPressed: _stopProcessing,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              const SizedBox(height: 24),

              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Instructions:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('1. Add tasks using the buttons above'),
                    Text('2. Tap "Start Processing"'),
                    Text('3. Watch foreground processing in the UI'),
                    Text('4. Background the app - should handoff'),
                    Text('5. Return to app - should handoff back'),
                    SizedBox(height: 8),
                    Text(
                      'Note: Background still uses simulated tasks. '
                      'Foreground uses the task queue.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
