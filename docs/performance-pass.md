# Performance pass

The six fixes from the audit, in the order they were made. Each was built
separately on the simulator; none was profiled on a device, so the figures a
profiling run would give are still missing. What follows is what changed and why,
not a claim about measured frame times.

## 1. `SessionEngine` no longer publishes ten times a second

`Develop/SessionEngine.swift`

The engine ticks a 0.1 s timer so a stage boundary is never missed. It also
assigned `now = Date()` on every tick, and `now` is observable — so every view
reading `stageElapsed`, `stageRemaining` or `currentPrompt` re-evaluated its
body ten times a second, for a reading that only moves once.

Now the exact instant lives in a separate `@ObservationIgnored preciseNow`, used
by the engine's own boundary checks, prompt announcements and notification
scheduling, where tenth-of-a-second resolution is the point. The published
`now` is only updated when a reading the running screen actually draws changes —
the stage countdown (compared exactly as `Clock.mmssCeil` renders it), the
current agitation phase's countdown, or the phase itself. That is roughly once a
second, plus one update at each prompt boundary, so the displayed prompt is
never behind the chime that marks it.

Timer accuracy and prompt timing are unchanged: the tick is still 0.1 s, and
`refreshAlerts()` deliberately computes elapsed time from `preciseNow` rather
than the published clock — scheduling from a reading up to a second old would
have fired notifications up to a second late.

`preciseNow` is also set wherever the clock is restarted (`begin`, both branches
of `togglePause`, `advance`, `jump`), so a resumed stage never measures from a
stale instant.

## 2. `TimerTools` timelines wrap the digits, not the screen

`Tools/TimerTools.swift`

The stopwatch, interval timer and wash/rinse timer each wrapped a whole
`ScrollView` — cards, credential rows, lap lists, buttons — in a
`TimelineView`. Every tick rebuilt all of it.

A small `LiveTicker<Content>` now renders its content on a timeline only while
something is counting, and renders statically otherwise. It wraps only the one
`Text` that changes in each timer, keeping each call site's font, colour,
`contentTransition` and accessibility label exactly as they were.

The two timers that also did work on the tick (advancing the interval, ending
the final rinse) keep a 0.2 s `Timer.publish` driver on the view, which changes
no state unless a boundary has actually been crossed. The animations, the
`.numericText()` transitions and the 0.1 s / 0.2 s cadences are unchanged.

## 3. `LiquidBackdrop` stops when nobody is looking

`Design/LiquidBackdrop.swift`

The darkroom backdrop is the one thing that drifts forever, at 24 fps, on ~30
screens. It now pauses when the view is off screen (`onAppear` / `onDisappear`),
when the app is not active (`scenePhase`), and when Reduce Motion is on. All
three use the schedule's own `paused:` flag, so the last frame is held rather
than the layer disappearing: with Reduce Motion the backdrop is a still image of
the same liquid.

## 4. `LibraryStore` answers from an index

`Library/LibraryStore.swift`, `Library/LibraryBrowserView.swift`

Everything the screens asked for repeatedly was recomputed on each call:

- `film(key:)`, `developer(key:)` and `source(key:)` were linear scans, called
  per row from the detail screens;
- `times(forFilm:)` filtered *and sorted* the whole time table, then sorted with
  a comparator that did two developer lookups per comparison — per row, per
  render;
- `developers(matching:)` rebuilt a haystack string per candidate per keystroke;
- `verificationItems` rebuilt a formatted array for every time, film and
  developer entry on every access — including every keystroke in the search
  field.

A private `Index` is now built once per document change (`didSet` on `document`)
and again on first init. It holds key dictionaries (first entry wins, matching
the old `first(where:)`), a film's times already filtered and sorted in the same
order, per-developer film counts, the search haystacks, and the films'
pre-normalised names and makers for the DX match. `libraryFilm(for:)` keeps its
document-order, first-match behaviour and its ISO rule; it simply no longer
re-normalises every candidate.

`verificationItems` is cached, and rebuilt only when the temperature scale it
formats its subtitles in has changed — that scale is the only input it takes
from outside the document.

`developerRow` now asks the store for the film count instead of building a `Set`
across every time entry.

## 5. A stage's agitation script is built once

`Models/SessionPlan.swift`, `Develop/SessionEngine.swift`

`SessionStage.segments` was a computed property rebuilding the whole agitation
array on every read. The engine reads it several times a second while running,
and the running screen reads it again for each prompt it draws.

`segments` is now stored, built in the stage's initialiser. `duration` became
`private(set)`, and the three places that change a stage's length —
`+30 s`, the leader-clearing fixer time, the standard fix time — go through
`addTime(_:)` or `setDuration(_:)`, which update the duration and rebuild the
script once. No behaviour changed: the same three call sites, the same values.

## 6. `StageRing`'s expensive layers only redraw when their values change

`Develop/StageRing.swift`

The bezel (sixty stroked ticks) and the progress arc (a stroked circle with two
shadows and a running animation) sat directly in the ring's body, so any parent
pass re-stroked both — and could re-time the arc's animation — even when neither
had changed.

They are now `StageRingTicks` and `StageRingFill`, both `Equatable`, applied with
`.equatable()`. The tick canvas redraws for a new stage count, active stage,
diameter or accent; the arc redraws only when its fraction changes. Both
animations, both shadows, the opacity rule and the `.id(index)` that restarts
the arc on a new stage are untouched.

## Files changed

| File | Change |
| --- | --- |
| `Develop/SessionEngine.swift` | Publish cadence; `preciseNow`; precise prompt/alerts timing; stage-time setters |
| `Tools/TimerTools.swift` | `LiveTicker`; three timelines unwrapped; tick drivers for interval advance and rinse end |
| `Design/LiquidBackdrop.swift` | Visibility, scene phase and Reduce Motion pause the liquid |
| `Library/LibraryStore.swift` | Derived `Index`; cached lookups, sorted times, film counts, search keys, verification queue |
| `Library/LibraryBrowserView.swift` | Developer row uses the cached film count |
| `Models/SessionPlan.swift` | Stored `segments`; `private(set) duration`; `addTime` / `setDuration` |
| `Develop/StageRing.swift` | Equatable tick and arc subviews |
| `docs/performance-pass.md` | This record |

## Still to measure

The audit's measurement plan (Animation Hitches + the SwiftUI instrument on
"scroll Recipes with a query typed" and "run a session into the developer
stage") has not been run — that needs a device, and this project builds on a
remote Mac. Findings 3, 4, 5 and 6 above are the ones that plan would confirm
first.

---

# Second pass: presentation bug and card/backdrop cost

Everything below is a **code reading**, not a measurement. It was written without
a compiler or a device, so no frame times are claimed. Where a finding names what
would confirm it, that is the first thing to run.

## 7. Settings stopped opening after a theme change (bug)

`ContentView.swift`, `Design/Appearance.swift`, `Settings/SettingsView.swift`

`ContentView` hung its Settings sheet on a `Group` whose content switched between
`tabs` and `ThemeLanguageRootView`. Modifiers on a `Group` are applied to each
branch, so a theme change across that boundary removed the view presenting the
sheet. The sheet was dismissed by the system without the binding being written
back, `AppearanceStore.isShowingSettings` stayed `true`, and every later
`isShowingSettings = true` changed nothing.

That sheet is gone. Settings is now an ordinary pushed screen, reached from the
disc in the Develop header and from the Tools hub, so it travels the same
navigation path as every other screen in the app and has no presentation state
that can go stale. `AppearanceStore` no longer carries a presentation flag.

The tab stack is no longer re-identified either: `AppearanceStore` forwards the
theme and preference stores' changes through `objectWillChange` instead of a
`revision` counter applied as `.id`, which used to tear the whole hierarchy down
on every accent write and on every Settings dismissal.

To confirm: open Settings from Develop, change the palette, come back, open it
again from Tools.

## 8. Cards paid for a shadow that drew nothing

`Design/Glass.swift`

Every `glassCard` added a second `.shadow` with a clear colour when it was not
glowing. A clear shadow draws nothing but is still a separate blurred pass. It is
now added only when `glowing` is true. The picture is identical.

## 9. The backdrop redrew 24 times a second under every frosted card

`Design/LiquidBackdrop.swift`, `Languages/DesignLanguageGraphics.swift`

Each frosted card samples and blurs what is behind it, so every redraw of the
backdrop forces a re-blur of every visible card. The liquid moves a couple of
points a second under a 24–44 pt blur; it is now redrawn 6 times a second, which
is indistinguishable at that speed and about a quarter of the compositing work.

To confirm: Animation Hitches and the Core Animation instrument on a device,
scrolling Recipes, before and after.

## 10. A palette was rebuilt for every card in a drawn theme

`Languages/DesignLanguageComponents.swift`, `Languages/DesignLanguage.swift`

`DLRuntime.activeStyle` built a `DLStyle`, and with it a whole palette, on every
call, and every card and button calls it while building its body. The last style
is now reused until the theme, palette, brightness, text size or density changes.

## 11. The library bridge re-mapped every film on every read

`Library/LibraryStore.swift`

`StarterLibrary.films` and `.developers` rebuilt hundreds of `Film` values on each
access, including inside a view initialiser's `@State` default and in `ForEach`.
They are now built once per document change.

## Not changed on purpose

- Closing Settings still rebuilds the tab stack. Some screens read defaults
  (fix time, wash time) once when built, so the rebuild is what refreshes them.
  Making it conditional is a behaviour change and needs a device to check.
- The variable edge blurs stay on. They are the app's look. If a device trace
  shows them in the hitch, `ProgressiveBlur` is the one place to scale back.
- The library is still decoded and merged on the main thread at first use.
