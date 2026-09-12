# The Kitchen Clock — Roadmap to MVP

## Part one: the app

The Kitchen Clock is a simple kitchen timer built around a large, readable countdown and controls you can use with the one clean finger you have while cooking.

The starting example is boiling bagels: set 30 seconds, start the timer, flip the bagel when it finishes, and start another 30 seconds with a tap. The app should make this repeated action quick and comfortable, with very little to learn or navigate.

### The core experience

- **One timer.** A huge countdown is the focus of the screen. Its ready, running, and finished states should be easy to distinguish.
- **Easy reuse.** Start the timer with a large control and run the same duration again with a tap when it finishes. Provide an obvious way to stop a running timer.
- **Adjustable durations and saved presets.** Thirty seconds is a useful starting point, not a fixed limit. Save frequently used durations locally so they are easy to return to.
- **Optional automatic repeat.** Press and hold to toggle repeat. Give immediate feedback and show clearly when repeat is enabled. Explain the hold interaction briefly so it does not depend on discovery.
- **A gentle finish.** Use a short, noticeable completion sound while the app is open, supported by a clear visual change. The right sound needs to be judged in an actual kitchen.
- **Open from a link.** Support a URL containing timer configuration, so a configured timer can be opened from elsewhere. Keep the initial payload small and document it when implemented.
- **Reliable recovery.** Preserve enough information to restore the timer after switching apps, closing the app, or restarting the device.

### Returning to the timer

Time spent outside the app still counts. If a timer has not expired when the user returns, show the correct remaining time. If it has expired, show the finished state and let the user continue from there.

Automatic repeat continues while the app is visible. If a cycle expires while the app is away, it waits at finished until the user deliberately starts it again. Do not calculate unseen repeat cycles or play missed completion sounds.

MVP does not promise an alert while the app is in the background or the device is locked. It also does not show a countdown outside the main app. Reliable restoration is the requirement, including after a full device restart. Store the timer's timing information and state rather than relying on a countdown process to remain running.

### Design and project direction

Build primarily for iPhone using native SwiftUI. iPad uses the same simple experience at a generous scale; it does not need a separate dashboard or additional controls just because there is more space.

Use large touch targets, rounded shapes, readable numbers, and a restrained colour treatment. Keep frequent actions on the main screen and duration editing and presets close at hand. Avoid gestures that are easy to trigger accidentally; the hold-to-repeat interaction is a particular hardware check. Keep the screen awake during active countertop timing and restore normal behaviour when timing ends or the app is left.

Target iOS and iPadOS 26 or later, with Swift 6.2 or later. Keep timer behaviour and persistence separate from the views, using a small feature-oriented structure and testable state. Use native frameworks and local storage; MVP needs no account, backend, or third-party dependencies.

This timer may eventually become part of a larger cooking, shopping, or planning app. Let that guide clear boundaries and naming, without adding a framework for future features. The timer should remain straightforward to build and understand on its own.

### After MVP

Voice control, on-device generated colour themes, generated cooking imagery, and broader cooking, shopping, and planning experiences can be revisited after the basic timer works well. Background alerts and a countdown outside the app are also later work.

Dedicated VoiceOver and Dynamic Type validation are outside the MVP testing scope. Continue using native controls and semantic text styles as the baseline.

## Part two: building MVP

The repository currently contains the [original brainstorm](kitchen-timer-app-brainstorm-transcript.md); the Xcode app has not been created yet. Build in small steps, keeping each milestone usable before adding the next.

Codex should handle most implementation and focused automated checks, with Xcode used to build and run the app. Hand device setup and real-world checks to the user where doing them directly is simpler and faster. Each hardware handoff should include a short set of steps and the behaviour to check.

### Milestone 1 — A running app

- [x] Establish the Xcode project for iPhone and iPad, targeting iOS/iPadOS 26+ and Swift 6.2+.
- [x] Create a small timer feature structure with state and behaviour separate from SwiftUI presentation.
- [x] Build the first screen around a large countdown and a large start control, using 30 seconds as the initial duration.
- [x] **User / hardware:** complete signing and device setup where needed, then launch on an iPhone and check the initial scale and readability from the countertop.
- [x] **Done when:** the app builds and runs, and the basic screen feels large, clear, and easy to reach.

### Milestone 2 — One useful timer

- [ ] Add duration editing, start, stop, a clear finished state, and one-tap reuse of the same duration.
- [ ] Base remaining time on a recorded deadline so display updates do not determine timing accuracy.
- [ ] Add the foreground completion sound and visual feedback, with no repeated sound caused by screen updates.
- [ ] Keep the display awake during active timing and restore normal behaviour when appropriate.
- [ ] Add focused unit tests for the core timer transitions and completion behaviour.
- [ ] **User / hardware:** time several bagel-style cycles; check touch targets, countdown readability, screen wake behaviour, and whether the sound is noticeable without being irritating.
- [ ] **Done when:** a single timer is useful for actual cooking without presets or repeat mode.

### Milestone 3 — Reliable interruption and recovery

- [ ] Save timing information and state whenever meaningful timer actions occur, so recovery does not depend on a clean app shutdown.
- [ ] Restore the correct remaining time when returning before expiry, and the finished state when returning after expiry.
- [ ] Preserve the selected duration and recover after app termination or a full device restart.
- [ ] Avoid playing a completion sound for a timer that finished while away; keep background alerts outside this milestone.
- [ ] Test restoration before and after expiry, including stopped timers and missing saved state, using controllable time in unit tests.
- [ ] **User / hardware:** switch apps and return before and after expiry, then repeat the checks after terminating the app and restarting the device.
- [ ] **Done when:** returning to the app gives the expected timer state without needing a process to have kept running.

### Milestone 4 — Repeat and saved presets

- [ ] Add locally saved duration presets with simple selection, saving, and removal.
- [ ] Add press-and-hold repeat toggling, immediate feedback, a visible repeat indicator, and a brief explanation of the gesture.
- [ ] Repeat automatically while the app is visible, with a clear way to stop the timer or turn repeat off.
- [ ] If a cycle expires while away, restore a finished timer and wait for a deliberate restart; do not run missed cycles.
- [ ] Preserve presets and the repeat setting across launches. Test repeat transitions, recovery, and preset persistence.
- [ ] **User / hardware:** check the hold gesture while cooking, including whether ordinary taps accidentally toggle repeat and whether repeat status is obvious at a glance.
- [ ] **Done when:** frequently used durations and repeated cycles are quicker to use without making the main screen feel busy.

### Milestone 5 — Open a configured timer from a link

- [ ] Define and document a minimal URL format for duration and repeat configuration, including whether opening the link starts the timer.
- [ ] Route links through the same timer behaviour used by the app's controls.
- [ ] Handle invalid input clearly and require an explicit choice before replacing an active timer.
- [ ] Test valid and invalid payloads, opening from a closed app, and opening while a timer is already running.
- [ ] **User / hardware:** open example links on a device and confirm the expected configuration and timer state appear.
- [ ] **Done when:** a documented link reliably opens the intended timer without silently disrupting an existing one.

### Milestone 6 — Cook with it and finish MVP

- [ ] Refine the main screen based on kitchen use: readability, reach, accidental input, sound, and the speed of starting another cycle.
- [ ] Check the same experience on iPad, keeping the interface large and simple across the available space.
- [ ] Run the focused unit tests and resolve remaining build issues; run SwiftLint if installed.
- [ ] **User / hardware:** use the app during a real cooking session, then check the agreed recovery scenarios and the iPad layout on available hardware.
- [ ] **Done when:** the single-timer experience is quick, clear, and dependable, with repeat, presets, links, and recovery working as described above.

MVP ends here. Use what cooking with this version teaches us to decide what comes next.
