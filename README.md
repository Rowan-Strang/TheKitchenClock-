# The Kitchen Clock

This started while I was making bagels. I needed 30 seconds for each side in the boiling water, a number I could read from the countertop, and an easy way to start it again.

That's the idea here: a kitchen timer with big numbers, big controls, and very little getting in the way. Something you can use with the one clean finger you have left while cooking.

The first version will have adjustable durations, saved presets, optional repeat, and a gentle sound when it's done. It should remember where you left it, even if you leave the app or restart your phone. Alerts outside the app can wait.

We're building for iPhone first, in Xcode with native SwiftUI, targeting iOS/iPadOS 26+ and Swift 6.2+. iPad gets the same app with more room. Most of the build will happen with Codex and Xcode; the kitchen is where we'll find out whether it actually feels right.

## Timer links

The app accepts a custom link that configures a timer without starting it:

```
kitchenclock://timer?seconds=30
```

`seconds` must appear exactly once as a whole number from `1` to `359999` (99:59:59). The link accepts no other parameters, including repeat. A successful link loads the duration in the ready state and turns repeat off, so the cook can choose whether to enable it.

Links never interrupt a running or paused timer. Reset the active timer first, then open the link again. Invalid links leave the current timer unchanged and show an explanation in the app.

Examples:

```
kitchenclock://timer?seconds=30
kitchenclock://timer?seconds=90
```

The app is built in small milestones; see the [roadmap to MVP](RoadmapToMVP.md) and the [original kitchen brainstorm](kitchen-timer-app-brainstorm-transcript.md).

There are plenty of places this could go later. For now, I'd like a really good little timer.
