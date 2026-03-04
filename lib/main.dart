import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'background_service.dart';
import 'services/task_queue.dart';
import 'services/network_listener.dart';
import 'models/task.dart';

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

class _BackgroundWorkDemoState extends State<BackgroundWorkDemo>
    with WidgetsBindingObserver {
  final FlutterBackgroundService _service = FlutterBackgroundService();
  final TaskQueue _taskQueue = TaskQueue();
  final NetworkListener _networkListener = NetworkListener();

  List<Task> _allTasks = [];
  int _pendingCount = 0;
  int _completedCount = 0;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToService();
    _startNetworkListener();
    _loadTasks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkListener.stopListening();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[UI] App lifecycle changed: $state');
    if (state == AppLifecycleState.resumed) {
      print('[UI] App resumed - reloading tasks');
      _loadTasks();
    }
  }

  void _listenToService() {
    // Listen for progress updates
    _service.on('progress').listen((event) {
      if (mounted) {
        // Reload tasks to show updated statuses
        _loadTasks();
      }
    });

    // Listen for completion
    _service.on('workComplete').listen((event) {
      if (mounted) {
        _loadTasks();
      }
    });
  }

  // Start network listener
  Future<void> _startNetworkListener() async {
    await _networkListener.startListening();

    // Check initial connectivity status
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile;
    });

    // Listen for connectivity changes in UI
    Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(() {
          _isOnline = result == ConnectivityResult.wifi ||
              result == ConnectivityResult.mobile;
        });
      }
    });
  }

  // Load tasks from storage
  Future<void> _loadTasks() async {
    print('[UI] Loading tasks from storage...');
    final tasks = await _taskQueue.getAllTasks();
    final pending = tasks.where((t) => t.status == TaskStatus.pending).length;
    final completed =
        tasks.where((t) => t.status == TaskStatus.complete).length;

    print('[UI] Loaded ${tasks.length} tasks: $pending pending, $completed completed');

    if (mounted) {
      setState(() {
        // Reverse so newest tasks appear first
        _allTasks = tasks.reversed.toList();
        _pendingCount = pending;
        _completedCount = completed;
      });
    }
  }

  // Queue a new task
  Future<void> _queueTask() async {
    print('[UI] Queueing new task...');
    final newTask = Task.create(
      data: {'index': _allTasks.length + 1},
    );

    await _taskQueue.addTask(newTask);
    print('[UI] Task added to queue');
    await _loadTasks();
    print('[UI] Tasks reloaded, isOnline: $_isOnline');

    // If online, trigger service immediately
    if (_isOnline) {
      print('[UI] Device is online, triggering service...');
      await _networkListener.triggerServiceIfNeeded();
      print('[UI] Service trigger completed');
    } else {
      print('[UI] Device is offline, waiting for network');
    }
  }

  // Clear completed tasks
  Future<void> _clearCompleted() async {
    await _taskQueue.clearCompletedTasks();
    await _loadTasks();
  }

  // Debug: Force start service
  Future<void> _forceStartService() async {
    print('[UI] FORCE STARTING SERVICE (debug)');
    await _service.startService();
    print('[UI] Force start completed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Task Queue Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Network status indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green[100] : Colors.red[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isOnline ? Colors.green : Colors.red,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOnline ? Icons.wifi : Icons.wifi_off,
                    color: _isOnline ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: _isOnline ? Colors.green[900] : Colors.red[900],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Task statistics
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Pending',
                    _pendingCount.toString(),
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Completed',
                    _completedCount.toString(),
                    Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _queueTask,
                    icon: const Icon(Icons.add),
                    label: const Text('Queue Task'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _completedCount > 0 ? _clearCompleted : null,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear Done'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Debug button
            OutlinedButton.icon(
              onPressed: _forceStartService,
              icon: const Icon(Icons.bug_report),
              label: const Text('DEBUG: Force Start'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 24),

            // Task list
            const Text(
              'All Tasks',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _allTasks.isEmpty
                  ? const Center(
                      child: Text(
                        'No tasks yet.\nTap "Queue Task" to add one!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _allTasks.length,
                      itemBuilder: (context, index) {
                        final task = _allTasks[index];
                        return _buildTaskCard(task);
                      },
                    ),
            ),

            const SizedBox(height: 16),

            // Instructions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit & Forget:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text('1. Go offline, queue tasks',
                      style: TextStyle(fontSize: 12)),
                  Text('2. Close app completely',
                      style: TextStyle(fontSize: 12)),
                  Text('3. Go online → auto-starts!',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha((255 * 0.1).toInt()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    IconData icon;
    Color color;

    switch (task.status) {
      case TaskStatus.pending:
        icon = Icons.schedule;
        color = Colors.orange;
        break;
      case TaskStatus.processing:
        icon = Icons.sync;
        color = Colors.blue;
        break;
      case TaskStatus.complete:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case TaskStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text('Task #${task.data?['index'] ?? '?'}'),
        subtitle: Text(
          task.status.name.toUpperCase(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        trailing: Text(
          _formatTime(task.createdAt),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
