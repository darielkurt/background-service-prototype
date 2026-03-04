
# Background Sync: Decision Document

## Problem Statement

### The Core Challenge

How do we reliably sync inspection data to the cloud when users are working in the field with unreliable connectivity, and the mobile app might be closed, backgrounded, or even terminated by the operating system?

### Why This Matters

Field inspections happen in real-world conditions:
- Workers move in and out of connectivity zones
- Phone batteries run low, triggering aggressive power management
- Users frequently switch between apps or close them entirely
- Data must reach the server reliably, even hours after collection

The traditional approach—syncing only when the app is actively open—fails in these scenarios. Users close the app thinking their work is saved locally, only to discover later that data never reached the server.

### The Technical Reality

Mobile operating systems (iOS and Android) impose strict limitations on what apps can do in the background:

**iOS:**
- Apps get approximately 30 seconds when backgrounded
- Apps cannot wake themselves up
- Apps cannot bring themselves back to the foreground
- Background execution is severely restricted to preserve battery life

**Android:**
- Battery optimization can terminate background services
- Background execution requires user-visible notifications (for foreground services)
- Different Android versions have different rules
- Manufacturers add their own battery optimization layers

### What We Need

A solution that:
1. Syncs reliably even when the app isn't visible
2. Works within platform constraints rather than fighting them
3. Preserves battery life (doesn't drain user's phone)
4. Provides transparent progress feedback
5. Handles network interruptions gracefully
6. Feels fast and responsive when the app is in use

---

## Options Explored

We evaluated four different architectural approaches before settling on our final solution.

### Option A: Pure Background Service

**Concept:**
Run all sync operations in a background service that continues regardless of whether the app is visible.

**How It Would Work:**
- Service starts when data needs syncing
- Runs independently of the main app
- Processes uploads, API calls, and data transformations
- Continues until all data is synced

**Advantages:**
- ✅ Works when app is closed
- ✅ User can continue using their phone
- ✅ Fully automated—no user intervention needed

**Disadvantages:**
- ❌ Complex architecture (app and service run in separate processes)
- ❌ Difficult to update UI when sync completes
- ❌ Platform restrictions make it unreliable (iOS especially)
- ❌ Higher battery drain
- ❌ More prone to being killed by OS battery optimization

**Why We Passed:**
While powerful in theory, background services are increasingly restricted by mobile operating systems. iOS makes this approach nearly impossible, and Android's battery optimization often kills these services unpredictably. The complexity wasn't worth the unreliability.

---

### Option B: Foreground-Only Sync

**Concept:**
Only sync when the app is actively open and visible to the user.

**How It Would Work:**
- User opens app
- User manually triggers sync
- Sync runs while app is visible
- Progress shown in real-time in the UI

**Advantages:**
- ✅ Simple and reliable
- ✅ Immediate UI updates
- ✅ No platform restriction issues
- ✅ Lower battery usage
- ✅ Easy to debug and maintain

**Disadvantages:**
- ❌ Stops completely if user closes app
- ❌ Forces user to keep app open during sync
- ❌ Poor experience for large batches
- ❌ Doesn't work for automatic background sync

**Why We Passed:**
This was actually our starting point (and it worked well!). However, user testing revealed frustration: field workers would create inspections, close the app, and expect sync to complete automatically. When they reopened the app hours later, nothing had synced.

---

### Option C: Hybrid Platform-Adaptive Approach ⭐ CHOSEN

**Concept:**
Adapt the sync strategy based on two factors:
1. Is the app in the foreground or background?
2. Which platform (iOS or Android)?

Rather than fighting platform limitations, embrace them and use different strategies for different situations.

**How It Works:**

**When app is in foreground:**
- Use fast, direct sync (like Option B)
- Show progress in the UI
- No notifications needed

**When app is in background on Android:**
- Use a "foreground service" (a special Android service with a visible notification)
- The notification tells Android "this is important work the user started"
- Android allows unlimited background time as long as the notification is visible
- Process everything automatically

**When app is in background on iOS:**
- Queue file uploads using iOS's system-managed upload system
- iOS handles uploads even if our app is terminated
- When uploads finish, show notification
- User taps notification to open app and finish remaining quick tasks

**Advantages:**
- ✅ Best user experience on each platform
- ✅ Works within platform constraints
- ✅ Fast when app is visible, reliable when it's not
- ✅ Battery efficient (uses platform-native capabilities)
- ✅ Transparent progress feedback

**Disadvantages:**
- ❌ More complex architecture
- ❌ Platform-specific code paths
- ❌ iOS doesn't get fully automatic background sync

**Why We Chose This:**
This approach acknowledges reality: iOS and Android are fundamentally different platforms with different capabilities. By embracing these differences rather than trying to paper over them, we get the best possible experience on each platform.

---

### Option D: Server-Side Processing

**Concept:**
Upload raw photos to the server, then let the server handle Vision API calls and data processing.

**How It Would Work:**
- App only uploads photos
- Server receives photos
- Server calls Vision API
- Server processes results
- Server updates database

**Advantages:**
- ✅ Offloads processing from phone
- ✅ Faster app experience (just upload and forget)
- ✅ Easier to update processing logic (server-side)
- ✅ Works regardless of app state

**Disadvantages:**
- ❌ Requires backend architecture changes
- ❌ Higher server costs (processing + storage)
- ❌ Additional latency (wait for server processing)
- ❌ More complex error handling (server failures)
- ❌ Requires server infrastructure for Vision API

**Why We Deferred:**
This is actually a good long-term solution, but it requires significant backend work. For the initial version, we wanted a solution that could be implemented within the mobile app without requiring server-side changes.

---

## The Chosen Solution: Hybrid Platform-Adaptive Sync

### Core Principle

**Embrace platform differences instead of fighting them.**

Each platform has its strengths. Android allows foreground services. iOS has excellent system-managed uploads. By using the right tool for each platform, we get better results than trying to force a one-size-fits-all approach.

### Three Operating Modes

#### Mode 1: Foreground Sync (Both Platforms)

**When:** App is actively open and visible

**What Happens:**
- User can see sync progress in real-time
- Sync runs at full speed using device resources
- UI updates immediately as each inspection completes
- No notifications (user can already see what's happening)

**User Experience:**
Fast and responsive. Like watching a progress bar fill up. Users see exactly what's happening.

---

#### Mode 2: Android Background Sync

**When:** App is backgrounded or closed on Android device

**What Happens:**
1. Network becomes available (WiFi connects)
2. App detects pending work
3. Starts a "foreground service"—a special Android feature
4. Shows persistent notification: "Syncing 10 inspections..."
5. Processes all uploads, scans, and API calls
6. Updates notification: "Sync complete!"
7. Automatically stops

**Why This Works:**
Android trusts foreground services because users can see the notification. The OS knows the user is aware of this work, so it won't kill the service to save battery.

**User Experience:**
Automatic. User turns on WiFi, sees a notification that sync is happening, and it just completes. They can use other apps while this happens.

---

#### Mode 3: iOS Background Upload

**When:** App is backgrounded on iOS device

**What Happens:**
1. Network becomes available
2. App queues photo uploads with iOS's system
3. iOS manages the uploads using its own infrastructure
4. When uploads finish, app shows notification: "Photos uploaded! Tap to complete"
5. User taps notification
6. App opens and quickly finishes remaining work (scanning text, API calls)
7. Total time in app: ~30 seconds

**Why This Works:**
iOS has a built-in system for handling uploads that survives app termination. By leveraging this, we get the most reliable uploads possible on iOS. The remaining work (OCR scanning, API calls) is quick enough to finish while the app is open.

**User Experience:**
Mostly automatic. Heavy lifting (uploading large photos) happens in background. User taps notification to finish the last quick steps. Much faster than uploading everything from scratch.

---

### Smart Notifications

The system knows when to notify and when to stay quiet:

**Notifications Shown:**
- When app is backgrounded and work is happening
- When work completes and user action is needed (iOS)
- When errors occur

**Notifications Suppressed:**
- When app is in foreground (user can already see progress)
- When no work is pending
- When sync completes while app is visible

This prevents notification spam while ensuring users stay informed when they can't see the app.

---

### Network Awareness

The system automatically detects when network connectivity returns:

1. User creates inspections while offline
2. Network monitor detects WiFi/data connection
3. System checks: Is app in foreground or background?
4. Routes to appropriate sync mode
5. Sync starts automatically

**Smart Behavior:**
- Only triggers on network restoration (not every connectivity check)
- Checks if there's actually work to do before starting
- Chooses the right sync mode for current app state

---

## Trade-offs & Considerations

### What We Gained

✅ **Reliability**
Sync works across platforms despite different OS limitations. Data gets to the server even when apps are backgrounded or closed.

✅ **Battery Efficiency**
Using platform-native capabilities means the OS can optimize power usage. We're not fighting the system.

✅ **User Experience**
Fast when app is visible, automatic when it's not. Transparent progress. Minimal user intervention needed.

✅ **Maintainability**
Each platform uses its preferred approach. Code is clearer because we're not trying to make incompatible platforms behave identically.

### What We Gave Up

❌ **Unified Code Path**
Platform-specific strategies mean more code to maintain. What works on Android doesn't work on iOS, and vice versa.

❌ **Fully Automatic iOS Sync**
iOS users need to tap a notification to finish sync. It's not as seamless as Android's fully automatic approach.

❌ **Simplicity**
The hybrid approach is more complex than "just sync everything in the foreground" or "just use a background service."

### When This Works Well

🎯 **Field Inspections**
Workers complete inspections one at a time, expecting sync before moving to the next location. The app has time to sync between tasks.

🎯 **Moderate Batch Sizes**
10-50 inspections sync quickly. Even with interruptions, batches complete in minutes.

🎯 **Intermittent Connectivity**
Network comes and goes. System waits for connectivity and auto-triggers sync when available.

🎯 **User-Aware Workflow**
Users understand they need to keep the app running briefly or respond to notifications. They're engaged in the process.

### When This Might Struggle

⚠️ **Very Large Batches**
100+ inspections could take a long time. Users might not want to wait, and battery drain becomes a concern.

⚠️ **Immediate App Closure**
If users create data and immediately force-quit the app, iOS uploads might not start (no time to queue them).

⚠️ **Poor Network Conditions**
Very slow or unstable connections could cause timeouts. Current implementation could use better retry logic.

⚠️ **Multi-Device Scenarios**
If the same inspection is edited on multiple devices, there's no conflict resolution. Last write wins.

---

## Next Steps

### Already Implemented ✅

These features are working now:

- **Network detection and auto-trigger**: System detects when connectivity returns and starts sync automatically
- **Smart notification system**: Context-aware notifications that adapt to app state
- **Upload progress tracking**: Real-time progress updates during sync
- **Platform-adaptive sync**: Different strategies for Android and iOS

### Recommended Next (Medium Term)

Priority improvements for the next phase:

**1. True iOS Background Uploads**
Currently using a standard HTTP library for uploads. Implementing native iOS background upload sessions would survive app termination completely.

**Impact:** More reliable iOS uploads
**Effort:** Medium (requires native iOS code)

**2. Enhanced Retry Logic**
Add exponential backoff when network calls fail. Instead of immediate retry, wait longer each time (1s, 2s, 4s, 8s).

**Impact:** Better handling of poor network conditions
**Effort:** Low (just improved error handling)

**3. Offline Queue Persistence**
Ensure queued work survives app restarts. Currently, backgrounding the app works, but force-quitting might lose queue state.

**Impact:** More resilient to app kills
**Effort:** Medium (requires careful state management)

### Future Considerations (Long Term)

Larger architectural improvements to consider:

**1. Task Granularity**
Break each inspection into atomic tasks (upload photo, scan text, call API). Track and retry individual tasks instead of whole inspections.

**Benefits:**
- Resume from exact point of failure
- Better progress granularity
- Parallel processing possible

**Effort:** High (significant refactor)

**2. WorkManager Integration (Android)**
Use Android's WorkManager for guaranteed eventual execution, even if app is force-killed.

**Benefits:**
- Survives device restart
- OS handles scheduling and retry
- Better battery optimization

**Effort:** Medium (Android-specific work)

**3. Server-Side Processing**
Move Vision API calls and processing to the backend. App only uploads photos.

**Benefits:**
- Faster app experience
- Easier to update processing logic
- No client-side resource constraints

**Effort:** High (requires backend changes)

**4. Conflict Resolution**
Handle cases where the same inspection is edited on multiple devices.

**Approaches:**
- Last-write-wins (simple)
- Field-level merge (complex)
- User choice (manual resolution)

**Effort:** High (requires sync protocol design)

---

## Conclusion

We chose a hybrid, platform-adaptive approach that embraces the differences between iOS and Android rather than fighting them. While more complex than a single-strategy solution, this approach delivers better reliability, user experience, and battery efficiency on each platform.

The key insight: **there is no universal "best" way to handle background sync on mobile**. The constraints are too different. By accepting this reality and optimizing for each platform's strengths, we built a solution that works well in practice.

---

## Appendix: Visual Flow Diagrams

### Foreground Sync (Both Platforms)

```
User opens app
    ↓
Creates inspections while offline
    ↓
Taps "Start Sync"
    ↓
Progress bar appears
    ↓
Inspections sync one by one
    ↓
UI updates in real-time
    ↓
"Sync complete!" message
```

### Android Background Sync

```
User creates inspections
    ↓
Closes app or switches to another app
    ↓
WiFi connects
    ↓
Notification appears: "Syncing..."
    ↓
Sync runs automatically
    ↓
Notification updates: "Sync complete!"
    ↓
Notification disappears after 2 seconds
```

### iOS Background Upload

```
User creates inspections
    ↓
Closes app
    ↓
WiFi connects
    ↓
Notification: "Uploading files..."
    ↓
iOS manages uploads in background
    ↓
Notification: "Files uploaded! Tap to complete"
    ↓
User taps notification
    ↓
App opens
    ↓
Quick finish (30 seconds)
    ↓
"Sync complete!"
```

### Network Detection Logic

```
Network state changes
    ↓
Was disconnected? AND Now connected?
    ↓
Check: Is app in foreground?
    ├── YES → Direct sync (fast, no notifications)
    └── NO → Check platform
        ├── Android → Start foreground service
        └── iOS → Queue background uploads
```
