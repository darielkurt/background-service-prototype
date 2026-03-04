import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background service
  await initializeBackgroundService();

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

class _BackgroundWorkDemoState extends State<BackgroundWorkDemo> {
  final FlutterBackgroundService _service = FlutterBackgroundService();

  String _status = 'Ready';
  int _currentTask = 0;
  int _totalTasks = 10;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _listenToService();
  }

  void _listenToService() {
    // Listen for progress updates
    _service.on('progress').listen((event) {
      if (mounted && event != null) {
        setState(() {
          _currentTask = event['current'] ?? 0;
          _totalTasks = event['total'] ?? 10;
          _status = 'Processing task $_currentTask/$_totalTasks';
        });
      }
    });

    // Listen for completion
    _service.on('workComplete').listen((event) {
      if (mounted) {
        setState(() {
          _status = 'Work complete!';
          _isWorking = false;
        });
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    final FlutterLocalNotificationsPlugin notificationsPlugin =
        FlutterLocalNotificationsPlugin();

    // Request notification permission for Android 13+
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final bool? granted = await androidImplementation?.requestNotificationsPermission();

    if (granted == false) {
      if (mounted) {
        setState(() {
          _status = 'Notification permission denied';
        });
      }
    }
  }

  Future<void> _startBackgroundWork() async {
    // Request notification permission first
    await _requestNotificationPermission();

    final isRunning = await _service.isRunning();

    if (!isRunning) {
      await _service.startService();
      setState(() {
        _isWorking = true;
        _status = 'Starting background work...';
        _currentTask = 0;
      });
    }
  }

  Future<void> _stopBackgroundWork() async {
    _service.invoke('stop');
    setState(() {
      _isWorking = false;
      _status = 'Stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalTasks > 0 ? _currentTask / _totalTasks : 0.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Background Work POC'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Background Processing Demo',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

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

              const SizedBox(height: 40),

              // Start button
              ElevatedButton.icon(
                onPressed: _isWorking ? null : _startBackgroundWork,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Background Work'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Stop button
              if (_isWorking)
                OutlinedButton.icon(
                  onPressed: _stopBackgroundWork,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),

              const SizedBox(height: 40),

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
                    Text('1. Tap "Start Background Work"'),
                    Text('2. Background the app (press home)'),
                    Text('3. Check notification - it should keep updating!'),
                    Text('4. Work continues even if app is closed'),
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
