# Phase 2 Implementation Summary

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

2. **No network detection:** Tasks must be manually triggered. Auto-trigger on network restoration is not implemented.

3. **No retry logic:** If a task fails, there's no retry mechanism.

4. **Simple task model:** Tasks only have ID and status. No payload processing.

---

## Dependencies

```yaml
dependencies:
  flutter_background_service: ^5.0.0
  flutter_local_notifications: ^17.0.0
  shared_preferences: ^2.2.0
```

---

## Commands

```bash
# Run the app
flutter run

# Watch logs
adb logcat | grep -E "(Coordinator|BackgroundService|ForegroundProcessor|TaskQueue)"

# Clear app data for fresh test
adb shell pm clear com.example.basic_bg
```
