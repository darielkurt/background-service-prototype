# Next Steps

## Current State

Phase 2 is complete:
- ✅ Task model with persistence
- ✅ TaskQueue with SharedPreferences
- ✅ Foreground processing with UI
- ✅ Background processing with notifications
- ✅ Bidirectional handoff (foreground ↔ background)
- ✅ Cross-isolate state consistency

---

## Recommended Next Steps

### Priority 1: Network Detection (Phase 2F)

**Goal:** Auto-trigger processing when network becomes available.

**Implementation:**
1. Add `connectivity_plus: ^5.0.0` to pubspec.yaml
2. Create `lib/services/network_monitor.dart`
3. Listen for connectivity changes
4. When: disconnected → connected AND pending tasks exist → trigger coordinator

**Files to create/modify:**
- `lib/services/network_monitor.dart` (new)
- `lib/main.dart` (initialize monitor)
- `pubspec.yaml` (add dependency)

**Effort:** Low-Medium

---

### Priority 2: Real Task Payloads

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

**Effort:** Medium-High

### Server-Side Processing

Move heavy processing to backend:
- App only uploads files
- Server does OCR/Vision API calls
- Reduces client complexity

**Effort:** High (requires backend changes)

---

## Suggested Implementation Order

| Step | Feature | Effort | Impact |
|------|---------|--------|--------|
| 1 | Real task payloads | Low | High |
| 2 | Network detection | Low-Medium | High |
| 3 | Error handling | Medium | High |
| 4 | Notification tap | Low-Medium | Medium |
| 5 | IPC improvements | Medium | Low |

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
