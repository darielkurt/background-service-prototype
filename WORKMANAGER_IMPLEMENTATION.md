# WorkManager Implementation

## Overview

This implementation adds Android WorkManager integration to enable "Submit and Forget" functionality. Tasks queued while offline are processed automatically when network restores, **even after the app has been terminated**.

## Features

- **Task Processing After App Termination**: WorkManager triggers when network becomes available
- **Notification Tap Action**: Tapping progress/completion notifications opens the app
- **Seamless Handoff**: When app opens during WorkManager processing, foreground takes over
- **Processing Lock**: Prevents duplicate processing between WorkManager and app
- **Auto-Registration**: WorkManager task registered automatically when tasks are added

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PROCESSING PATHS                          │
├─────────────────────────────┬───────────────────────────────┤
│     APP IN MEMORY           │     APP TERMINATED            │
│                             │                               │
│  ProcessingCoordinator      │   Android WorkManager         │
│  (lifecycle aware)          │   (system component)          │
│            │                │              │                │
│     ┌──────┴──────┐         │              ▼                │
│     ▼             ▼         │   WorkManager Callback        │
│ Foreground   Background     │   (processes tasks directly,  │
│ Processor    Service        │    shows notifications)       │
└─────────────────────────────┴───────────────────────────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │     TaskQueue       │
         │  (SharedPreferences)│
         │  + Processing Lock  │
         └─────────────────────┘
```

## Files

### New Files

| File | Purpose |
|------|---------|
| `lib/services/workmanager_service.dart` | WorkManager initialization and callback dispatcher |
| `lib/services/workmanager_task_processor.dart` | Standalone task processor with notification tap support |

### Modified Files

| File | Changes |
|------|---------|
| `lib/main.dart` | Added WorkManager initialization |
| `lib/services/task_queue.dart` | Added processing lock, stop request, auto-registration |
| `lib/services/processing_coordinator.dart` | Added WorkManager takeover logic on app startup |
| `pubspec.yaml` | Added `workmanager: ^0.9.0+3` dependency |

## Processing Lock System

Prevents duplicate processing between WorkManager and foreground/background processors.

```dart
// Lock stored in SharedPreferences
{
  "lockerId": "workmanager" | "foreground" | "background",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

- **5-minute timeout**: Stale locks are automatically released
- **Force-release**: App force-releases WorkManager lock after 2 seconds if needed

## Notification IDs

| Processor | Progress ID | Completion ID |
|-----------|-------------|---------------|
| Background Service | 888 | 888 |
| WorkManager | 889 | 890 |

## Test Results

### Test 1: Tap Progress Notification (Handoff)
- 10 tasks queued → WorkManager processed 5 tasks
- Tapped notification → App opened mid-processing
- Foreground took over → Completed remaining 5 tasks

### Test 2: Tap Completion Notification
- 3 tasks queued → WorkManager processed all 3
- Completion notification shown
- Tapping notification opens app

### Test 3: Handoff During Processing
- 10 tasks queued → WorkManager completed 2 tasks
- Tapped notification during processing
- Foreground took over → Completed remaining 8 tasks

## Usage

### Adding Tasks (Auto-registers WorkManager)
```dart
final task = Task(id: 'task_1');
await TaskQueue().addTask(task);
// WorkManager task automatically registered with network constraint
```

### Manual Registration (if needed)
```dart
import 'services/workmanager_service.dart';
await registerPendingTasksSync();
```

### Cancel WorkManager Task
```dart
await cancelPendingTasksSync();
```

## Test Commands

```bash
# Watch logs
adb logcat | grep -E "(WorkManager|TaskQueue|Coordinator|Processor)"

# Force stop app
adb shell am force-stop com.example.basic_bg

# Toggle airplane mode
adb shell settings put global airplane_mode_on 1
adb shell am broadcast -a android.intent.action.AIRPLANE_MODE
adb shell settings put global airplane_mode_on 0
adb shell am broadcast -a android.intent.action.AIRPLANE_MODE
```

## Completed Milestones

- [x] Milestone 1: WorkManager Basic Setup
- [x] Milestone 2: Processing Lock + SharedPreferences
- [x] Milestone 3: WorkManager Task Processor
- [x] Milestone 4: Auto-Registration + App Takeover
- [x] Milestone 5: Notification Tap Action
- [ ] Milestone 6: Full Integration Testing
- [ ] Milestone 7: Edge Cases & Documentation
