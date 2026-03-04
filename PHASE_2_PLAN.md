# Phase 2: Task Persistence + Network Detection

## Goal
Implement "Submit and Forget" functionality - queue tasks while offline, app can be terminated, and when network becomes available, automatically start background service to process tasks.

---

## Success Criteria

**Submit and forget scenario:**
1. User is in foreground, offline
2. User queues 4 tasks
3. App is terminated (force closed)
4. Device goes online (WiFi/cellular available)
5. Background service automatically starts
6. Notification appears: "Processing tasks..."
7. All 4 tasks complete successfully
8. Notification shows: "4 tasks completed!"

---

## What Phase 1 Gave Us

✅ Background service that runs in separate isolate
✅ Foreground service survives app closure
✅ Notification system working
✅ Manual trigger to start work
✅ Simulated task processing (Timer with delays)

---

## What Phase 2 Adds

### 1. Task Queue with Persistence
- Store tasks in `shared_preferences` (survives app restart)
- Each task has: `id`, `status`, `createdAt`, `data`
- Task statuses: `pending`, `processing`, `complete`, `failed`
- Queue persists across app termination

### 2. Network Detection
- Use `connectivity_plus` package
- Listen for connectivity changes
- Detect when device goes from offline → online

### 3. Auto-trigger Background Service
- When network becomes available AND pending tasks exist
- Automatically start background service
- No manual button press needed

### 4. Task Processing Logic
- Background service reads pending tasks from storage
- Processes tasks one by one
- Updates task status as it progresses
- Saves progress after each task

---

## Implementation Steps

### Step 1: Add Dependencies
```yaml
dependencies:
  shared_preferences: ^2.2.0
  connectivity_plus: ^5.0.0
```

### Step 2: Create Task Model
```dart
class Task {
  final String id;
  final TaskStatus status;
  final DateTime createdAt;
  final Map<String, dynamic>? data;
}

enum TaskStatus { pending, processing, complete, failed }
```

### Step 3: Create Task Queue Manager
```dart
class TaskQueue {
  Future<void> addTask(Task task);
  Future<List<Task>> getPendingTasks();
  Future<void> updateTaskStatus(String taskId, TaskStatus status);
  Future<void> clearCompletedTasks();
}
```

### Step 4: Implement Network Listener
```dart
class NetworkListener {
  void startListening() {
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _checkAndStartService();
      }
    });
  }
}
```

### Step 5: Update Background Service
- Read tasks from persistent storage
- Process each task
- Update task status after each one
- Save progress continuously

### Step 6: Update UI
- Add "Queue Task" button (works offline)
- Show list of pending/completed tasks
- Remove "Start Background Work" button (auto-trigger now)

---

## File Structure

```
lib/
├── main.dart                    # UI - queue tasks, show status
├── background_service.dart      # Background service (modified)
├── models/
│   └── task.dart               # Task model
├── services/
│   ├── task_queue.dart         # Task persistence
│   └── network_listener.dart   # Network detection
└── utils/
    └── task_processor.dart     # Shared task processing logic
```

---

## Key Changes from Phase 1

| Aspect | Phase 1 | Phase 2 |
|--------|---------|---------|
| Task storage | None (in-memory only) | Persistent (shared_preferences) |
| Trigger | Manual button | Auto on network available |
| Offline support | No | Yes - queue tasks offline |
| Survives restart | Service survives, but no task memory | Tasks survive app/device restart |
| UI | "Start" button | "Queue Task" button |

---

## Testing Plan

### Test 1: Queue Offline, Go Online
1. Turn off WiFi/data
2. Open app, queue 4 tasks
3. Verify tasks show as "pending"
4. Close app completely
5. Turn on WiFi
6. **Expected:** Background service auto-starts, notification appears, tasks process

### Test 2: Queue While Online
1. WiFi is on
2. Open app, queue 4 tasks
3. **Expected:** Background service starts immediately, tasks process

### Test 3: App Restart with Pending Tasks
1. Queue tasks while offline
2. Close app
3. Reopen app (still offline)
4. **Expected:** Pending tasks still shown
5. Turn on WiFi
6. **Expected:** Service auto-starts

### Test 4: Partial Completion
1. Queue 10 tasks
2. Let 5 complete
3. Force close app
4. Reopen app
5. **Expected:** 5 shown as complete, 5 as pending
6. If online, remaining 5 should process

---

## Technical Considerations

### 1. Auto-start on Boot (Optional)
- Android can start services on device boot
- Would need `RECEIVE_BOOT_COMPLETED` permission
- Not required for Phase 2, can be Phase 4 enhancement

### 2. Battery Optimization
- Some manufacturers kill background services aggressively
- User may need to disable battery optimization for the app
- Document this in testing notes

### 3. Network Listener Lifecycle
- Must survive app restarts
- Use WorkManager or AlarmManager for reliability
- For Phase 2, keep simple with app-level listener

### 4. Concurrent Task Processing
- Phase 2: Process tasks sequentially (one at a time)
- Phase 4: Could add parallel processing

---

## Out of Scope for Phase 2

❌ Foreground/background handoff (Phase 3)
❌ Retry logic for failed tasks (Phase 4)
❌ Task prioritization (Phase 4)
❌ Real API calls (still simulated work)
❌ iOS support (Android only)
❌ Upload progress for individual tasks (Phase 4)

---

## Estimated Time

- Step 1-3 (Models & Queue): 30-45 minutes
- Step 4 (Network Listener): 30 minutes
- Step 5 (Update Service): 45 minutes
- Step 6 (Update UI): 30 minutes
- Testing & Debugging: 30-60 minutes

**Total:** ~3-4 hours

---

## Next Steps

1. Add dependencies
2. Create task model
3. Implement task queue with shared_preferences
4. Add network listener
5. Integrate with background service
6. Update UI
7. Test all scenarios

Ready to begin implementation!
