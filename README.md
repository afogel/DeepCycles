# DeepCycles — time blocking + Work Cycles for macOS

A small native macOS app that combines Cal Newport's **time-block planning** with
Ultraworking's **Work Cycles**, wired into the Calendar app (which already carries
your Google / iCloud / Exchange calendars).

    Day       → the time-block grid, with calendar events as ghosts, and an inspector
    Week      → seven columns + this week's plan and values plan
    Systems   → Newport's root document: Values, Career & Personal strategic plans,
                Ideas, Tasks, disciplines
    Focus     → a Work Cycles session takes over the window (from a deep block, ⇧⌘F)
    End day   → the shutdown sheet: disciplines, metrics, full capture, "complete" (⇧⌘S)
    Menu bar  → live cycle countdown, pause, end cycle

## Install (about 2 minutes)

Requirements: macOS 13 or newer and the Xcode Command Line Tools.

```bash
xcode-select --install        # once, if you don't have it already (skip if it says "already installed")
cd DeepCycles
./build.sh --install          # compiles and copies DeepCycles.app into /Applications
```

Open **DeepCycles** from Launchpad/Spotlight. The first launch asks for Calendar
access — say yes, or nothing can be read or written. (Because the app is not
notarized, if macOS complains about an unidentified developer: right-click the app
→ Open, once.)

Without `--install`, the app is left at `build/DeepCycles.app`; drag it wherever you like.

## How time blocks and Work Cycles fit together

Time blocking is the day's map: which hours go to deep work, meetings, shallow
work, breaks. Work Cycles is how you *execute* a deep block once you're inside it.
So a deep block and a cycle session are one-to-one:

    09:00 ─┬─ Deep block: draft chapter 3 (2h40)
           │   cycle 1  30 min  ─ break 10
           │   cycle 2  30 min  ─ break 10
           │   cycle 3  30 min  ─ break 10
           │   cycle 4  30 min
    11:40 ─┴─ (10-min overflow for the debrief)

The app enforces this: creating a session from a deep block sizes the cycles to
fit the block (4 cycles fit in 150 min, 5 in 190, and so on), the block shows its
cycle progress on the grid, and when a deep block is happening right now with no
session, the top bar offers to start one. Cycle minutes actually worked roll up
into the daily DW metric; the per-cycle "did I hit the target?" answers are the
honest feedback Newport says time blocking gives you about how long things take.

## The whole system (Newport's three categories)

    Core documents   Values · Career plan · Personal plan · Ideas · Tasks   (Systems tab)
         ↓ weekly
    Weekly plan + values plan                                            (Systems tab)
         ↓ daily
    Time-block plan  →  Work Cycles inside deep blocks                    (Plan, Cycles)
         ↓ evening
    Shutdown: log disciplines, full capture of tasks, "shutdown complete" (End day sheet)

Each level only has to look at the one above it. The morning panel on the Plan
page shows the current weekly and values plan; the shutdown checklist checks that
the Collection box was processed into Tasks, that tomorrow has a deep block, and
that every discipline is logged. Disciplines are the metric codes (DW, EX, CC…)
that get a value every day; the Systems tab shows a 14-day streak grid.

## Keyboard shortcuts

    ⌘P            command palette (everything below, by name)
    ⌘1 ⌘2 ⌘3      Day · Week · Systems       ⇧⌘F   focus mode in / out
    ⇧⌘T  ⇧⌘L     tasks · session log
    ⌘[  ⌘]  ⌘T    previous · next · today     ⇧⌘S   end day (shutdown sheet)
    ⌘N   ⌫        new block · delete block    ⌘K    capture to Collection
    ⌘I            adopt events as blocks      ⇧⌘P   sync blocks now
    ⌘↩            start the planned cycle     ⌘.    pause / resume
    ⇧⌘E           end cycle or break

Click the keyboard icon in the top bar for the same list in-app. These work while
DeepCycles is the front app; the menu-bar timer is the control surface when it isn't.

## Daily use

**Morning — Day**
1. Your calendar events appear as dashed ghosts on the timeline. Click one to adopt it
   as a block; leave it if it doesn't need planning around.
2. Drag across the hours you want to block (or ⌘N), name the block, pick its kind.
   Drag a block to move it; drag its bottom edge to resize. Overlapping items sit
   side by side. A task block lets you tick open tasks into it.
3. Blocks sync to your calendar automatically (footer shows the target; gear icon to
   change it, create a dedicated "Time Blocks" calendar, or turn sync off).
4. When the day breaks, edit the blocks; the calendar follows.

**Deep block — Focus**
1. Select a deep block → *Run Work Cycles on this block* (or ⇧⌘F → New session).
2. Prepare: the six Ultraworking questions plus cycle/break length and count.
3. Work: answer PLAN (goal, first step, hazards, energy, morale) → Start cycle.
   The timer runs in the window and the menu bar. When it ends: REVIEW
   (target hit? noteworthy? distractions? improvements?) → Start break → repeat.
4. Debrief: energy/morale/target table across cycles, five debrief questions.

**Tasks and review**
Capture (⌘K) → at shutdown, *Move to tasks* → the Tasks list (⇧⌘T). From there:
promote a task to *this week's outcomes* on the Week page ("↑ week"), tick outcomes
into deep blocks and tasks into task blocks on the Day page, and tick them off on
the block card or in the list. The weekly plan and values plan are checklists too:
outcomes are done-for-the-week; values habits get one tick per day.
Sessions live with their day (sorted by their block's start; finished ones drop to a
"Done today" group; hover for ×). Every session from the last 30 days is reviewable
in Systems → Session log (⇧⌘L) with its pulse and debrief.

**Evening — End day (⇧⌘S)**
Deep-work hours are tallied from your cycles; add your own metrics (e.g. "CC" for cold
calls), then flip *Shutdown complete*.

Stray thoughts during a block go in *Collection* (⌘K) as checkable items; at shutdown, *Move to tasks* sends the open ones to the task list in Systems.

## Where data lives
`~/Library/Application Support/DeepCycles/plans.json` — one entry per day, and `system.json` for the core documents, weekly plans and disciplines. Plain JSON.

## Files
- `Sources/DeepCycles/Models.swift`         data model + JSON persistence
- `Sources/DeepCycles/CalendarService.swift` EventKit read/write
- `Sources/DeepCycles/CycleEngine.swift`     timer state machine + notifications
- `Sources/DeepCycles/PlannerView.swift`     time-block grid and editor
- `Sources/DeepCycles/CyclesView.swift`      Prepare / Work / Debrief
- `Sources/DeepCycles/ShutdownView.swift`    disciplines, metrics and shutdown ritual
- `Sources/DeepCycles/SystemsView.swift`     root document, core docs, weekly plan, disciplines
- `Sources/DeepCycles/Theme.swift`          palette (light + calm dark), type, button styles
- `Resources/Info.plist`, `build.sh`
