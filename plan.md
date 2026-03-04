# Simple Background Processing POC for Flutter/Android

## Goal
Create the **simplest possible proof-of-concept** that demonstrates background processing continues when the Flutter app is backgrounded or terminated on Android.

**Not implementing**: The full hybrid sync architecture from DECISION.md
**Instead**: A minimal demo using `flutter_background_service` package

---

## User Requirements Summary
- ✅ Android only (no iOS complexity)
- ✅ Manual trigger (button to start)
- ✅ Persistent notification acceptable
- ✅ Battery drain acceptable for POC
- ✅ User can keep app open briefly before backgrounding
- ✅ **Just prove background processing works** (not full sync)

---

## Simplified Architecture

### Using Flutter Packages (Pure Dart!)

Instead of writing native Kotlin code, we'll use:
- **`flutter_background_service`** - Handles foreground service in pure Dart
- **`flutter_local_notifications`** - Shows and updates notifications

### Two Simple Components

#### 1. Flutter UI (Dart)
- **One screen** with:
  - "Start Background Work" button
  - Status text showing current state
  - Simple progress indicator
- Listens to background service updates via streams

#### 2. Background Service (Dart)
- **Service that runs in isolate** using `flutter_background_service`:
  - Runs background work (simulated tasks: counting, delays)
  - Shows persistent notification: "Processing... X/10 tasks complete"
  - Updates notification as work progresses
  - Continues running even when app is backgrounded/closed
  - Sends updates to UI via built-in streams
  - Stops automatically when work completes

---

## This Plan Implements: Phase 1 Only

**We'll build the foundational POC first**, then you can decide if you want to continue with Phases 2-3 or if adjustments are needed.

**Phase 1 deliverable:**
- Simple task execution (simulated work with delays)
- Background service that survives app backgrounding/closure
- Basic notification with progress updates
- Manual trigger (no network detection yet)
- No persistence (won't survive complete app termination on task queue)

**What Phase 1 proves:**
- The infrastructure works
- Background processing continues reliably
- Notifications update correctly
- Foundation is solid for adding more features

**After Phase 1 works, you can:**
- Continue to Phase 2 (persistence + network detection)
- Continue to Phase 3 (foreground/background handoff)
- Or pivot based on what you learn

---

## What the POC Will Do

1. User opens app
2. User taps "Start Background Work" button
3. Android Foreground Service starts
4. Notification appears: "Processing task 1/10"
5. User backgrounds or closes the app
6. **Service continues processing** (this proves the concept!)
7. Notification updates: "Processing task 2/10", "Processing task 3/10", etc.
8. When complete: Notification shows "Work complete!"
9. Service stops, notification dismisses

### Simulated Work
For the POC, the service will just:
- Loop 10 times
- Sleep 3 seconds between each iteration
- Update notification with current count
- Send progress back to Flutter (if app is open)

**Total runtime**: ~30 seconds
**This proves**: Background processing survives app backgrounding

---

## Implementation Plan

### Phase 1: Add Dependencies

**File**: `pubspec.yaml`

Add the required packages:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_background_service: ^5.0.0
  flutter_local_notifications: ^17.0.0
```

Run: `flutter pub get`

---

### Phase 2: Configure Android Permissions

**File**: `android/app/src/main/AndroidManifest.xml`

Add permissions inside `<manifest>` tag:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

The `flutter_background_service` package will handle the service declaration automatically.

---

### Phase 3: Create Background Service Logic

**File**: `lib/background_service.dart` (NEW FILE)

```dart
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
        ongoing: true, // Can't be dismissed while working
        showProgress: progress != null && progress < 100,
        maxProgress: 100,
        progress: progress ?? 0,
      ),
    ),
  );
}
```

---

### Phase 4: Create Flutter UI

**File**: `lib/main.dart`

Replace the default counter app:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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

  Future<void> _startBackgroundWork() async {
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
```

**Key Features:**
- Clean, modern UI with Material 3
- Real-time progress updates from background service
- Linear progress bar showing completion percentage
- Start/stop controls
- Built-in test instructions
- Stream-based communication with background service

---

### Phase 5: Testing & Validation

#### Manual Test Steps

1. **Build and run app**
   ```bash
   flutter run
   ```

2. **Start background work**
   - Tap "Start Background Work" button
   - Verify status changes to "Starting background work..."
   - Verify notification appears in Android status bar

3. **Background the app**
   - Press home button or switch to another app
   - Verify notification continues updating: "Processing task 2/10", "Processing task 3/10", etc.
   - **This proves background processing works!**

4. **Close the app completely**
   - Swipe app away from recent apps
   - Verify notification STILL continues updating
   - **This proves it survives app termination!**

5. **Return to app**
   - Open app again
   - If work is still running, progress updates should resume in UI
   - When complete, status shows "Work complete!"

#### Expected Behavior

✅ Notification persists while work is running
✅ Work continues when app is backgrounded
✅ Work continues even when app is force-closed
✅ Notification updates every ~3 seconds
✅ Service stops automatically when done

---

## Key Differences from DECISION.md Architecture

| Feature | DECISION.md (Complex) | This POC (Simple) |
|---------|----------------------|-------------------|
| Platforms | iOS + Android hybrid | Android only |
| Sync modes | 3 modes (foreground, Android bg, iOS bg) | 1 mode (foreground service) |
| Network detection | Automatic WiFi monitoring | None - manual trigger |
| Data model | Inspections, queue, persistence | None - simulated work |
| Vision API | OCR scanning, photo processing | None - just counting |
| Upload handling | Photos, retries, progress | None - simulated delays |
| Native code | Kotlin + Swift + MethodChannels | None - pure Dart packages |
| Complexity | High (platform channels, services, state management) | Low (packages handle everything) |

---

## Why This POC Works

### Proves the Core Concept
- Demonstrates **foreground service continues when app is closed**
- Shows **notification updates work reliably**
- Validates **background-to-UI communication** via streams
- Tests **Android lifecycle handling**

### Advantages of Using Packages
- **Pure Dart** - No Kotlin/Java code to write or maintain
- **Battle-tested** - `flutter_background_service` is widely used and maintained
- **Simple** - ~150 lines of code vs 300+ with native approach
- **Debuggable** - Can test most logic without running on device
- **Cross-platform ready** - Easy to add iOS later if needed

### Extensible Foundation
Once this works, you can extend it:
1. Replace simulated work with real uploads
2. Add data models for inspections
3. Implement network detection with `connectivity_plus`
4. Add retry logic for failures
5. Eventually add iOS support if needed
6. Add `shared_preferences` for state persistence

---

## Files to Create/Modify

### New Files (1)
1. `lib/background_service.dart` - Background service logic (pure Dart)

### Modified Files (3)
1. `pubspec.yaml` - Add flutter_background_service and flutter_local_notifications
2. `lib/main.dart` - Replace with POC UI
3. `android/app/src/main/AndroidManifest.xml` - Add permissions only (no service declaration needed)

---

## Success Criteria Mapping

### Your Success Criteria → Implementation Phases

| Your Scenario | Phase | What Gets Built |
|--------------|-------|----------------|
| **Happy path** (foreground, online, queue 4 tasks, success) | Phase 1 | Basic task execution in foreground ✅ |
| **App in background** (queue tasks, background app, return, success) | Phase 1 | Background service continues when app backgrounded ✅ |
| **Submit and forget** (offline, queue, terminate, go online, background notification, success) | Phase 2 | Task persistence + network detection + auto-trigger ⏳ |
| **Submit and forget 2** (same + tap notification → foreground takes over) | Phase 3 | Foreground/background handoff logic ⏳ |

### Phase 1 POC Success Criteria

The initial POC is successful when:

✅ User can tap button to start background work
✅ Notification appears and shows progress
✅ User can background app and work continues
✅ User can close app completely and work still continues
✅ Notification updates reflect actual progress
✅ Service stops automatically when complete
✅ No crashes, no excessive battery drain

This validates the **core infrastructure** before adding persistence and handoff complexity.

---

## Progressive Implementation Phases

### Phase 1: Simple POC (Current Plan Above)
**Goal:** Prove background processing works

**Features:**
- Manual trigger button
- 10 simulated tasks with delays
- Background service continues when app is backgrounded
- Notification shows progress

**Success Criteria:**
- ✅ Happy path (foreground, online, 4 tasks success)
- ✅ App in background (start foreground, background app, tasks continue, return to see success)

**Time:** ~30-60 minutes to implement and test

---

### Phase 2: Task Persistence + Network Detection
**Goal:** Survive app termination and auto-trigger when online

**New Features:**
1. **Task Queue with Persistence**
   - Use `shared_preferences` to store pending tasks
   - Tasks survive app termination
   - Each task has: `{id, status: 'pending'|'processing'|'complete', data: {}}`

2. **Network Detection**
   - Add `connectivity_plus` package
   - Listen for network changes
   - Auto-trigger background service when online + pending tasks exist

3. **Queue Management**
   - `addTask(task)` - add to queue while offline
   - `getpendingTasks()` - retrieve unprocessed tasks
   - `markComplete(taskId)` - update task status

**Success Criteria:**
- ✅ Submit and forget (queue offline, terminate app, go online, background runs, notification shows progress, 4 tasks success)

**Time:** ~1-2 hours

---

### Phase 3: Foreground/Background Handoff
**Goal:** Intelligently switch between foreground and background processing

**New Features:**
1. **App State Detection**
   - Detect when app comes to foreground
   - Check if background service is currently running

2. **Smart Handoff Logic**
   - **When app opens while background is running:**
     1. Read current progress from shared state
     2. Send 'stop' signal to background service
     3. Background service saves its state and stops
     4. Foreground picks up remaining tasks
     5. Process in main isolate with UI updates

   - **When app opens and no background running:**
     1. Check for pending tasks
     2. If found, process in foreground with UI
     3. If none, show "all synced" status

3. **Priority System**
   - Foreground is always preferred (more efficient)
   - Background only runs when app is not visible
   - Notification tap opens app → triggers handoff

**Implementation Details:**
```dart
// Shared state structure
{
  "tasks": [
    {"id": "task1", "status": "complete"},
    {"id": "task2", "status": "processing"},  // ← Background was working on this
    {"id": "task3", "status": "pending"},
    {"id": "task4", "status": "pending"}
  ],
  "backgroundServiceRunning": true,
  "currentTaskId": "task2"
}

// When app opens:
1. Check backgroundServiceRunning flag
2. If true:
   - Send stop signal to background
   - Wait for background to save state
   - Continue from currentTaskId in foreground
3. If false:
   - Just process pending tasks in foreground
```

**Success Criteria:**
- ✅ Submit and forget 2 (queue offline, terminate, go online, background starts, tap notification, app opens, background stops, foreground takes over and completes tasks)

**Time:** ~2-3 hours

---

### Phase 4: Polish & Edge Cases
**Goal:** Production-ready reliability

**Enhancements:**
1. Error handling and retries
2. Task timeout handling
3. Notification improvements (tap to open specific screen)
4. Battery optimization (coalesce tasks, efficient polling)
5. Edge case handling:
   - Rapid foreground/background switches
   - Network drops mid-task
   - Multiple tasks failing
6. Testing on various Android versions

**Time:** ~2-4 hours

---

## Recommended Handoff Strategy (For Phase 3)

Based on your requirement that "foreground is more efficient and better for tasks," here's the recommended approach:

### Foreground Priority Model

**Core Principle:** Always prefer foreground execution when app is open

**Behavior:**
1. **App in foreground** → Process tasks in main isolate, update UI directly
2. **App in background** → Run background service with notification
3. **App returns to foreground while background running** → Stop background, handoff to foreground

**Why this works:**
- ✅ **More efficient** - No service overhead when app is visible
- ✅ **Better battery** - Foreground uses less power than foreground service
- ✅ **Better UX** - Real-time UI updates instead of notification
- ✅ **Graceful handoff** - Background saves state, foreground continues seamlessly
- ✅ **Smart resource use** - Use the right tool for the current state

**Alternative considered:** Let background finish regardless of app state
- ❌ Less efficient (runs service when foreground available)
- ❌ Wastes battery
- ✅ Simpler (no handoff logic)

Your intuition was correct—foreground should take priority!

---

## Conclusion

This plan builds progressively:

**Phase 1 (This Implementation):** Proves background infrastructure works with minimal complexity

**Phase 2 (Future):** Adds offline queueing and auto-trigger on network restoration

**Phase 3 (Future):** Implements smart foreground/background handoff for optimal efficiency

By starting simple and adding features incrementally, we can validate each piece works before adding the next layer of complexity. The foundation uses `flutter_background_service` to avoid writing native code, keeping everything in Dart.
