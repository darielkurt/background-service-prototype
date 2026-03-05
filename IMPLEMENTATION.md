# Phase 2 Implementation Summary (Updated with Phase 2F)

## Overview

Successfully implemented a **foreground/background task processing system** with handoff coordination for Flutter/Android. The system allows tasks to be processed in the foreground (with UI updates) when the app is visible, and seamlessly hands off to a background service when the app is backgrounded.

---

## Problem Statement

Phase 1 (basic background service) worked, but we needed:
1. A **task queue** that both foreground and background could share
2. **Foreground processing** with real-time UI updates
3. **Background processing** with notifications when app is hidden
4. **Seamless handoff** between foreground and background modes
5. **Task persistence** so tasks survive app restarts

---

## Implementation Approach

We broke the work into **sub-phases**, each testable independently:

| Sub-Phase | Goal | Files |
|-----------|------|-------|
| 2A | Task model | `lib/models/task.dart` |
| 2B | TaskQueue (in-memory) | `lib/services/task_queue.dart` |
| 2C | Coordinator integration | `lib/main.dart` |
| 2D | Background handoff signals | `lib/background_service.dart` |
| 2E | SharedPreferences persistence | `task_queue.dart`, `pubspec.yaml` |

---

## Files Created/Modified

### New Files

#### `lib/models/task.dart`
- `TaskStatus` enum: `pending`, `processing`, `complete`
- `Task` class with JSON serialization for persistence

#### `lib/services/task_queue.dart`
- Singleton pattern for shared access
- SharedPreferences persistence with `reload()` for cross-isolate consistency
- Methods: `addTask()`, `getPendingTasks()`, `updateTaskStatus()`, `clearAll()`

### Modified Files

#### `lib/main.dart`
- Integrated `ProcessingCoordinator`
- Added `WidgetsBindingObserver` for lifecycle detection
- Added UI: task count, add/clear buttons, mode indicator
- Listens to both foreground processor and background service progress

#### `lib/background_service.dart`
- Added `DartPluginRegistrant.ensureInitialized()` for plugin access in isolate
- Now processes actual tasks from `TaskQueue` (not simulated)
- Added `requestHandoff` listener for graceful stop
- Emits `handoffReady` signal before stopping

#### `lib/services/processing_coordinator.dart` (existed, fixed)
- Only acts on `paused` state (ignores `inactive`, `hidden`)
- Added `_isHandoffInProgress` flag to prevent duplicates
- Resets mode to `idle` before starting foreground after handoff

#### `pubspec.yaml`
- Added `shared_preferences: ^2.2.0`

---

## Key Technical Decisions

### 1. SharedPreferences for Cross-Isolate State

**Problem:** Background service runs in a separate Dart isolate. In-memory data isn't shared.

**Solution:** Use SharedPreferences which persists to disk. Both isolates read/write to the same file.

**Critical Fix:** Call `prefs.reload()` before reading to get fresh data (not cached).

```dart
Future<List<Task>> getAllTasks() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();  // Critical for cross-isolate consistency
  // ...
}
```

### 2. Lifecycle Event Handling

**Problem:** Android fires multiple lifecycle events: `inactive` → `hidden` → `paused`

**Solution:** Only act on `paused` for backgrounding and `resumed` for foregrounding.

```dart
case AppLifecycleState.paused:
  await _handleAppBackgrounded();
  break;
case AppLifecycleState.inactive:
case AppLifecycleState.hidden:
  // Ignore - wait for paused
  break;
```

### 3. Graceful Handoff Protocol

**Foreground → Background:**
1. Stop foreground processor (gracefully finishes current task)
2. Wait 500ms
3. Start background service

**Background → Foreground:**
1. Send `requestHandoff` signal
2. Wait for `handoffReady` response (or 10s timeout)
3. Poll until background service stops
4. Start foreground processor

### 4. DartPluginRegistrant for Background Isolate

The background isolate needs explicit plugin initialization:

```dart
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();  // Required!
  // ...
}
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        main.dart                             │
│  - UI (buttons, progress, status)                           │
│  - WidgetsBindingObserver (lifecycle events)                │
│  - Listens to coordinator + processors                      │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  ProcessingCoordinator                       │
│  - Decides: foreground or background?                       │
│  - Handles lifecycle changes                                │
│  - Orchestrates handoffs                                    │
└──────────┬─────────────────────────────────┬────────────────┘
           │                                 │
           ▼                                 ▼
┌─────────────────────┐           ┌─────────────────────────┐
│ ForegroundProcessor │           │   BackgroundService     │
│ (main isolate)      │           │   (separate isolate)    │
│ - No notifications  │           │   - Shows notification  │
│ - Direct UI updates │           │   - Runs when app hidden│
└──────────┬──────────┘           └──────────┬──────────────┘
           │                                 │
           └────────────┬────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │    TaskQueue    │
              │ (SharedPrefs)   │
              │ - Persisted     │
              │ - Cross-isolate │
              └─────────────────┘
```

---

## Test Results

All test cases passed:

| Test | Result |
|------|--------|
| Add tasks, foreground processing | ✅ |
| Stop mid-processing | ✅ |
| Foreground → Background handoff | ✅ |
| Background completes tasks | ✅ |
| Background → Foreground handoff | ✅ |
| No duplicate task processing | ✅ |
| Tasks persist across restart | ✅ |

---

## Known Limitations

1. **Warning on startup:** `flutter_background_service_android` throws a warning about main isolate usage. This is cosmetic and doesn't affect functionality.

2. ~~**No network detection:**~~ ✅ Implemented in Phase 2F (see below)

3. **No retry logic:** If a task fails, there's no retry mechanism.

4. **Simple task model:** Tasks only have ID and status. No payload processing.

5. **Network detection requires app running:** Auto-trigger only works while app is in memory. See "Future: WorkManager" below.

---

## Dependencies

```yaml
dependencies:
  flutter_background_service: ^5.0.0
  flutter_local_notifications: ^17.0.0
  shared_preferences: ^2.2.0
  connectivity_plus: ^5.0.0  # Added in Phase 2F
```

---

## Commands

```bash
# Run the app
flutter run

# Watch logs
adb logcat | grep -E "(Coordinator|BackgroundService|ForegroundProcessor|TaskQueue|NetworkMonitor)"

# Clear app data for fresh test (required after changing notification settings)
adb shell pm clear com.example.basic_bg
```

---

# Phase 2F: Network Detection

## Overview

Implemented auto-trigger processing when network connection is restored.

---

## Files Created/Modified

### New Files

#### `lib/services/network_monitor.dart`
- Singleton service monitoring network connectivity
- Uses `connectivity_plus` package
- Tracks `_wasDisconnected` state to detect restore events
- Triggers `ProcessingCoordinator.startProcessingIfNeeded()` when:
  - Connection restored (disconnected → connected)
  - AND pending tasks exist

### Modified Files

#### `lib/main.dart`
- Import `NetworkMonitor`
- Initialize in `main()` after `ProcessingCoordinator`
- Call `_networkMonitor.setForegroundState()` in `didChangeAppLifecycleState()`

#### `lib/background_service.dart`
- Changed notification `Importance.low` → `Importance.defaultImportance` (3 places)
- Fixes inconsistent notification display on some Android versions

#### `pubspec.yaml`
- Added `connectivity_plus: ^5.0.0`

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     NetworkMonitor                           │
│  - Subscribes to connectivity_plus stream                   │
│  - Tracks _wasDisconnected state                            │
│  - Tracks _isInForeground state (from lifecycle)            │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Connection restored?
                          │ Pending tasks exist?
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              ProcessingCoordinator                           │
│  startProcessingIfNeeded(isInForeground: true/false)        │
│  - If foreground → start ForegroundProcessor                │
│  - If background → start BackgroundService                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Test Cases

| Test | Steps | Expected | Status |
|------|-------|----------|--------|
| Basic connectivity | Toggle airplane mode | Logs show "Connection RESTORED" / "Connection LOST" | ✅ |
| Auto-trigger (foreground) | Add tasks → airplane ON → airplane OFF | Processing starts automatically | ✅ |
| Auto-trigger (background) | Add tasks → airplane ON → background app → airplane OFF → resume | Processing starts automatically | ✅ |
| Handoff with notification | Start processing → background app | Notification appears consistently | ✅ (after importance fix) |

---

## Bug Fix: Inconsistent Notifications

**Problem:** Background service notification sometimes didn't appear.

**Cause:** `Importance.low` notifications can be suppressed by Android.

**Fix:** Changed to `Importance.defaultImportance` in 3 locations:
- `initializeBackgroundService()` - channel creation
- `onStart()` - channel creation in isolate
- `_showNotification()` - notification display

**Note:** After changing notification importance, must clear app data:
```bash
adb shell pm clear com.example.basic_bg
```

---

## Limitation: App Must Be Running

The current implementation only detects network changes **while the app is in memory** (foreground or background).

**Scenario NOT supported:**
1. Queue tasks offline
2. Terminate app completely
3. Go online
4. ❌ Background service does NOT auto-start

**Why:** When app is terminated, no Dart code is running to listen for connectivity changes.

---

## Future: WorkManager Integration

To support auto-start after app termination, implement Android WorkManager:

```
App running → queue tasks → register WorkManager task
                              ↓
                     App terminated
                              ↓
              Android detects network restored
                              ↓
              WorkManager triggers our callback
                              ↓
              Callback starts background service
```

**Required:**
- Add `workmanager` Flutter package
- Register callback with network constraint
- Callback checks for pending tasks and starts service

**Effort:** Medium-High (requires careful testing)
