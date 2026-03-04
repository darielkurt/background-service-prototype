# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**This is a proof-of-concept (POC) Flutter Android application** that demonstrates background task processing with persistence, network awareness, and the ability to survive app termination. The app implements a "submit and forget" pattern where users can queue tasks offline, close the app, and have tasks automatically process when network becomes available.

**Important: This is NOT production-ready code.** It's a prototype to explore and validate background processing patterns. Focus on learning and demonstrating concepts, not production hardening.

## Development Commands

### Setup
```bash
flutter pub get                    # Install dependencies
```

### Running
```bash
flutter run                        # Run on connected device/emulator
flutter run -d <device-id>        # Run on specific device
```

### Building
```bash
flutter build apk                  # Build release APK
flutter build apk --debug         # Build debug APK
```

### Testing
```bash
flutter test                       # Run all tests
flutter analyze                    # Run static analysis
```

### Maintenance
```bash
flutter clean                      # Clean build artifacts
flutter pub upgrade               # Upgrade dependencies
```

## Architecture Overview

### Background Processing System

The app uses **Android Foreground Services** with **Dart Isolates** to enable true background processing that survives app termination:

```
┌─────────────────────────────────┐
│ Main Isolate (UI)               │
│  - Flutter widgets              │
│  - User interactions            │
│  - Task queue management        │
│  - Network status display       │
└──────────────┬──────────────────┘
               │ Stream-based IPC
               ↓
┌─────────────────────────────────┐
│ Background Service Isolate      │
│  - Separate Dart isolate        │
│  - Processes queued tasks       │
│  - Updates notifications        │
│  - Survives app closure         │
└─────────────────────────────────┘
```

**Key Point:** The background service runs in a **separate isolate** from the main UI thread. When the app is force-closed (swiped away), the main isolate dies, but the background service isolate continues running because it's backed by an Android Foreground Service.

### Core Components

#### 1. Task Queue System (`lib/services/task_queue.dart`)
- **Persistent storage** using `shared_preferences`
- Stores tasks as JSON, survives app restart and device reboot
- Singleton pattern ensures consistent state across isolates
- Task states: `pending`, `processing`, `complete`, `failed`

**POC Tradeoff:** Uses `shared_preferences` (designed for small key-value data) instead of a proper database like SQLite. This is fine for the POC with a few tasks but would hit performance/size limits in production.

#### 2. Network Listener (`lib/services/network_listener.dart`)
- Monitors network connectivity using `connectivity_plus`
- **Auto-triggers background service** when network becomes available AND pending tasks exist
- This enables "submit and forget" functionality

**POC Tradeoff:** Network listener only works while app is running in foreground/background. After device reboot or app termination, there's no listener active until app reopens. Production would need WorkManager or boot receiver.

#### 3. Background Service (`lib/background_service.dart`)
- Entry point: `onStart()` decorated with `@pragma('vm:entry-point')`
- Runs in **separate isolate** from main app
- Processes tasks sequentially with 3-second delays (simulated work)
- Updates both notifications and UI via streams
- **Automatically stops** when all tasks complete

**POC Tradeoff:** No error handling, retry logic, or timeout handling. Tasks just simulate delays. Production would need robust error handling, exponential backoff, and real API calls.

#### 4. Main UI (`lib/main.dart`)
- Queue tasks (works offline)
- Display task statistics and list
- Show network status
- Listen for progress updates via streams

**POC Tradeoff:** UI directly instantiates services instead of using dependency injection. No state management solution. Fine for POC, would need refactoring for production.

### Task Model (`lib/models/task.dart`)

```dart
class Task {
  final String id;              // Timestamp-based unique ID
  final TaskStatus status;      // pending|processing|complete|failed
  final DateTime createdAt;     // For sorting and display
  final Map<String, dynamic>? data;  // Flexible payload
}
```

**POC Tradeoff:** Uses timestamp for ID generation (risk of collisions). Production would use UUID. Flexible `data` map instead of typed models.

### Communication Pattern

**Main Isolate → Background Isolate:**
- Service started via `FlutterBackgroundService.startService()`
- Stop commands via `service.on('stop')`

**Background Isolate → Main Isolate:**
- Progress updates via `service.invoke('progress', {...})`
- Completion via `service.invoke('workComplete', {...})`
- Main UI listens via `_service.on('progress').listen(...)`

**Both Isolates ↔ Persistent Storage:**
- Both can read/write to `TaskQueue` (backed by `shared_preferences`)
- This is how tasks survive app termination

**POC Tradeoff:** No conflict resolution if both isolates write simultaneously. Unlikely in this POC flow, but production would need proper concurrency handling.

## Android Manifest Configuration

Located at `android/app/src/main/AndroidManifest.xml`:

**Required Permissions:**
- `FOREGROUND_SERVICE` - Run foreground services
- `POST_NOTIFICATIONS` - Show notifications (Android 13+)
- `FOREGROUND_SERVICE_DATA_SYNC` - Required for Android 14+ with `foregroundServiceType="dataSync"`
- `WAKE_LOCK` - Keep CPU awake during background work

**Service Declaration:**
```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:exported="false"
    android:foregroundServiceType="dataSync" />
```

The `foregroundServiceType="dataSync"` is critical for Android 14+ compliance.

## Key Technical Concepts

### Why This Works (When Other Approaches Fail)

**Android Foreground Service:**
- High-priority service that shows persistent notification
- Protected from being killed by OS (except extreme low memory)
- Survives app closure, screen off, and moderate battery optimization
- **Must** show ongoing notification (Android requirement for transparency)

**Dart Isolates:**
- Independent execution contexts with separate memory
- Background isolate continues running even if main isolate is terminated
- Communication only via message passing (streams)

**This Combination:**
- Flutter background service = Android Foreground Service + Dart Isolate
- Service survives because Android protects it
- Isolate survives because service keeps it alive
- Tasks survive because they're persisted to disk

### POC Tradeoffs Summary

| Aspect | POC Implementation | Production Consideration |
|--------|-------------------|-------------------------|
| **Task Storage** | `shared_preferences` | Would need SQLite/Hive for scalability |
| **Error Handling** | None - tasks just delay 3s | Needs try-catch, retry logic, exponential backoff |
| **Network Detection** | Only when app is open | Needs WorkManager/AlarmManager for reliability |
| **Task Processing** | Sequential, no timeout | Would need parallel processing, timeouts, cancellation |
| **ID Generation** | Timestamp | Would need UUID to prevent collisions |
| **Concurrency** | No locking | Would need proper database transactions |
| **State Management** | `setState()` | Would need proper state management (Riverpod, Bloc, etc.) |
| **Dependency Injection** | Direct instantiation | Would need DI container |
| **Logging** | None | Would need proper logging/analytics |
| **Testing** | Minimal | Would need comprehensive unit/integration tests |
| **Foreground Efficiency** | Always uses background service | Phase 3 would add smart handoff |

**The Key Message:** These tradeoffs are intentional to keep the POC simple and focused on proving the core background processing concept. Don't spend time fixing these for production unless explicitly asked.

### Phase Implementation Strategy

The app follows a phased approach (see `PHASE_1_QA.md` and `PHASE_2_PLAN.md`):

**Phase 1 (Complete):** Basic background service with manual trigger
**Phase 2 (Current):** Task persistence + network auto-trigger ("submit and forget")
**Phase 3 (Future):** Smart foreground/background handoff for efficiency
**Phase 4 (Future):** Production polish, retry logic, error handling

### Current Limitation: Always Uses Background Service

Even when app is in foreground (visible on screen), tasks run in the background service isolate. This means:
- ✅ Consistent behavior across all scenarios
- ✅ Simple implementation for POC
- ❌ Less efficient than running in main isolate when app is open
- ❌ Shows notification even when unnecessary
- ❌ Higher battery drain than necessary

**Future Enhancement (Phase 3):**
Implement smart handoff:
- App open → run in main isolate (no service, no notification)
- App backgrounds → transfer to background service
- App reopens → transfer back to main isolate

## Testing Scenarios

### Scenario 1: Normal Operation (App Open)
1. App is open and online
2. Queue tasks
3. Service starts immediately
4. See progress in UI and notification

### Scenario 2: App Backgrounded (Home Button)
1. Queue tasks with app open
2. Press Home button
3. Service continues running
4. Notification updates continue
5. Return to app → see progress

### Scenario 3: App Force-Closed (Submit & Forget)
1. Go offline, queue tasks
2. Force close app (swipe away)
3. Go online
4. **Background service auto-starts** (no app needed!)
5. Notification shows progress
6. Tasks complete independently

**POC Limitation:** Only works if network listener is still active when you go online. If you reboot device or wait too long, you need to reopen app first to restart the listener.

### Scenario 4: Device Restart
1. Queue tasks
2. Reboot device
3. Open app → tasks still show as pending (persisted!)
4. If online, service auto-starts and processes them

**POC Limitation:** Must manually reopen app after reboot. Production would use `RECEIVE_BOOT_COMPLETED` to auto-start listener on boot.

## Important Notes

### Background Service Lifecycle
- Service runs until all pending tasks complete
- Automatically stops itself via `service.stopSelf()`
- If no pending tasks, service exits immediately
- Network listener prevents duplicate service instances (checks `isRunning()`)

### Battery Optimization
Some manufacturers (Xiaomi, Samsung, OnePlus) aggressively kill background services despite foreground status. Users may need to:
- Disable battery optimization for the app
- Add app to "protected apps" list
- Disable adaptive battery for the app

This is a known Android ecosystem issue, not a bug in the implementation. POC doesn't handle this - just document it.

### Task Processing
- Tasks are processed **sequentially** (one at a time)
- Each task simulates 3 seconds of work (`Future.delayed`)
- In production, replace with actual network calls/processing
- Task data stored in flexible `data` map for POC convenience

### Dependencies
- `flutter_background_service: ^5.0.0` - Background service infrastructure
- `flutter_local_notifications: ^17.0.0` - Notification system
- `shared_preferences: ^2.2.0` - Persistent task storage
- `connectivity_plus: ^5.0.0` - Network monitoring

## Common Patterns

### Adding a New Task
```dart
final task = Task.create(data: {'key': 'value'});
await TaskQueue().addTask(task);
```

### Checking Service Status
```dart
final isRunning = await FlutterBackgroundService().isRunning();
```

### Manually Triggering Service
```dart
await NetworkListener().triggerServiceIfNeeded();
```

### Reading Task Statistics
```dart
final pending = await TaskQueue().getPendingTasks();
final count = pending.length;
```

## File Structure

```
lib/
├── main.dart                          # UI and app initialization
├── background_service.dart            # Background service isolate logic
├── models/
│   └── task.dart                     # Task model and TaskStatus enum
└── services/
    ├── task_queue.dart               # Persistent task storage (singleton)
    └── network_listener.dart         # Network monitoring and auto-trigger

android/app/src/main/
└── AndroidManifest.xml               # Permissions and service declaration
```

## Debugging Tips

### Check if Service is Running
```bash
adb shell dumpsys activity services | grep BackgroundService
```

### View Logs from Background Isolate
Background service prints are visible in:
```bash
flutter logs
# or
adb logcat | grep flutter
```

### Clear Persistent Tasks (for Testing)
In code:
```dart
await TaskQueue().clearAllTasks();
```

### Test Offline Mode
- Use airplane mode on device
- Or in emulator settings → turn off WiFi/cellular

## Additional Documentation

- `PHASE_1_QA.md` - Detailed explanation of how background processing works (isolates, foreground services, etc.)
- `PHASE_2_PLAN.md` - Implementation plan for persistence and network detection
- `plan.md` - Original project plan
- `DECISION.md` - Architectural decisions
