# Next Steps

## Current State

Phase 2 + 2F complete:
- ✅ Task model with persistence
- ✅ TaskQueue with SharedPreferences
- ✅ Foreground processing with UI
- ✅ Background processing with notifications
- ✅ Bidirectional handoff (foreground ↔ background)
- ✅ Cross-isolate state consistency
- ✅ Network detection (auto-trigger on connection restore)

---

## Recommended Next Steps

### ~~Priority 1: Network Detection (Phase 2F)~~ ✅ COMPLETE

Implemented in `lib/services/network_monitor.dart`. See IMPLEMENTATION.md for details.

**Limitation:** Only works while app is in memory. For auto-start after app termination, WorkManager integration is needed (see Priority 5).

---

### Priority 1: Real Task Payloads

**Goal:** Tasks carry actual data (not just IDs).

**Implementation:**
1. Expand `Task.data` to include meaningful payload
2. Add task creation with data (e.g., inspection data, file paths)
3. Process payload in foreground/background processors

**Example:**
```dart
final task = Task(
  id: 'inspection_123',
  data: {
    'type': 'photo_upload',
    'filePath': '/path/to/photo.jpg',
    'inspectionId': 'insp_456',
  },
);
```

**Effort:** Low

---

### Priority 3: Error Handling & Retry Logic

**Goal:** Tasks can fail and be retried.

**Implementation:**
1. Add `TaskStatus.failed` status
2. Add `retryCount` and `lastError` to Task model
3. Implement exponential backoff (1s, 2s, 4s, 8s delays)
4. Move failed tasks to end of queue or separate failed queue
5. Add max retry limit

**Files to modify:**
- `lib/models/task.dart` (add failed status, retry fields)
- `lib/services/foreground_task_processor.dart` (wrap processing in try/catch)
- `lib/services/task_queue.dart` (add retry methods)

**Effort:** Medium

---

### Priority 4: Progress Communication Improvements

**Goal:** Fix the `flutter_background_service_android` warning and improve IPC.

**Current issue:** Warning about using the package in main isolate.

**Options:**
1. Suppress the warning (it's cosmetic)
2. Use `flutter_background_service_android` correctly per package docs
3. Switch to method channels for cleaner IPC

**Effort:** Medium

---

### Priority 5: Notification Tap Action

**Goal:** Tapping the notification opens the app and shows progress.

**Implementation:**
1. Configure notification click action in `flutter_local_notifications`
2. Handle notification tap in app
3. Navigate to progress screen or show overlay

**Effort:** Low-Medium

---

## Future Considerations (From DECISION.md)

### iOS Support

Currently Android-only. iOS would need:
- Background upload sessions (NSURLSession)
- Different lifecycle handling
- No foreground service equivalent

**Effort:** High

### WorkManager Integration

Use Android's WorkManager for guaranteed execution:
- Survives device restart
- OS handles scheduling
- Better battery optimization
- **Required for:** Auto-start background processing after app termination when network restores

**Current limitation:** NetworkMonitor only works while app is in memory. WorkManager would enable:
1. Queue tasks offline
2. App terminated
3. Go online
4. WorkManager triggers background service automatically

**Effort:** Medium-High

### Server-Side Processing

Move heavy processing to backend:
- App only uploads files
- Server does OCR/Vision API calls
- Reduces client complexity

**Effort:** High (requires backend changes)

---

## Suggested Implementation Order

| Step | Feature | Effort | Impact | Status |
|------|---------|--------|--------|--------|
| 1 | Network detection | Low-Medium | High | ✅ Done |
| 2 | Real task payloads | Low | High | Pending |
| 3 | Error handling | Medium | High | Pending |
| 4 | Notification tap | Low-Medium | Medium | Pending |
| 5 | WorkManager (offline→online) | Medium-High | High | Pending |
| 6 | IPC improvements | Medium | Low | Pending |

---

## Quick Wins

These can be done immediately with minimal effort:

1. **Add task descriptions to UI** - Show what each task is (not just "task_1")
2. **Completion summary** - "5 tasks completed in 15 seconds"
3. **Clear completed tasks button** - Currently only "clear all"
4. **Timestamp display** - Show when tasks were created/completed

---

## Testing Recommendations

Before adding new features:

1. **Stress test current implementation:**
   - 50+ tasks
   - Rapid foreground/background switching
   - Low memory conditions

2. **Device testing:**
   - Multiple Android versions (API 26+)
   - Different manufacturers (Samsung, Pixel, etc.)
   - Battery saver mode

3. **Edge cases:**
   - App killed during background processing
   - Network drop during task
   - Device restart with pending tasks
