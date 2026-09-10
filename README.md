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

Requirements: macOS 14 or newer and the Xcode Command Line Tools.

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

## Keyboard

The app is built to be driven from the keyboard. Only the things you do many times a
day have a shortcut; everything else is one ⌘P away, by name.

    ⌘P            command palette (everything, by name)
    ⌘,            settings: appearance, default hours, calendar sync
    ⌘1 ⌘2 ⌘3      Day · Week · Systems         ⇧⌘F  ⎋   focus mode in · out
    ⌘[  ⌘]  ⌘T    previous · next · today
    ⌘N   ⌘⌫       new block · delete block     ⌘Z ⇧⌘Z   undo · redo
    ⌘K            capture to Collection
    ⇧⌘N           new session for the next deep block
    ⌘↩            next step: plan → start cycle → start break → debrief
    ⌘.   ⇧⌘E      pause / resume · end cycle or break early

Inside the forms:

    ⇥  ⇧⇥         move between fields and controls (buttons and switches included)
    ␣             press the focused button, switch or checkbox
    ↑↓  ←→        move in lists, pickers, steppers and ratings
    1–5  Y H N    rate energy / morale · answer "did you hit the target?"
    ↩  ⌫          in the session list and the day grid: open · delete

Focus mode, all on the keyboard: ⇧⌘N makes a session for the next deep block and puts
you in the first Prepare question. ⌘↩ moves to planning the first cycle, then starts
it. When the timer ends the target question has focus: Y, H or N, then ⌘↩ starts the
break. After the last cycle ⌘↩ opens the debrief, and once more marks the session
finished. Tab reaches the session list (↑↓ to switch sessions), the stage picker
(←→), every question, both ratings and every button.

Click the keyboard icon in the top bar for this list in-app. Shortcuts work while
DeepCycles is the front app; the menu-bar timer is the control surface when it isn't.

## Daily use

**Morning — Day**
1. Your calendar events appear as dashed ghosts on the timeline. Click one to adopt it
   as a block; leave it if it doesn't need planning around.
2. Drag across the hours you want to block (or ⌘N), name the block, pick its kind.
   Drag a block to move it; drag its bottom edge to resize. Overlapping items sit
   side by side. A task block lets you tick open tasks into it.
3. Blocks sync to your calendar automatically. Settings (⌘,) picks the target
   calendar, creates a dedicated "Time Blocks" calendar, or turns sync off; the gear
   in the Day footer changes that day's hours and syncs or adopts events now.
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

Saves are coalesced: an edit is written a moment later, and anything pending is written when
the app goes to the background or quits. Set `DEEPCYCLES_DATA_DIR=/some/folder` to run
against scratch data instead.

## Code layout

Two modules. `DeepCyclesCore` has no SwiftUI or AppKit in it: the data, its persistence, the
timer and the session flow, all unit-tested. `DeepCycles` is the SwiftUI app on top, one
directory per page.

    Sources/DeepCyclesCore/
      Model/      Blocks, Cycles, DayPlan, Systems, Time — the data and its JSON migrations
      State/      Store (plans.json / system.json, undo, coalesced saves), AppState (what the
                  window is showing), Pages (tabs, stages, pending commands), UndoHistory
      Services/   CalendarService (EventKit), CycleEngine (the timer state machine)
      Flow/       SessionFlow (the ⌘↩ steps, shared by buttons, menus and palette), FuzzyMatch
      Layout/     OverlapPacking (side-by-side blocks)
    Sources/DeepCycles/
      App/        DeepCyclesApp, RootView, DateBar, MenuBarView, CycleAlerts (beep, notification)
      Commands/   CommandCatalog (every command and shortcut, once), AppCommands (the menus),
                  CommandPalette, ShortcutsSheet
      Design/     Theme (palette, type, tokens), Buttons, Controls (keyboard-first controls),
                  WritingField, Wordmark
      Day/        PlannerView, DayGrid, BlockControls
      Week/       WeekView, ValuesTracker
      Focus/      FocusView, CyclesView (session list), SessionView (Prepare / Work / Debrief),
                  SessionPulse
      Systems/    SystemsView          Shutdown/   ShutdownView          Settings/   SettingsView
      Shared/     TaskList
    Tests/DeepCyclesCoreTests/   the Core tests        Tests/TestKit/   a small XCTest stand-in
    Resources/Info.plist, build.sh

## Tests

    swift run DeepCyclesCoreTests

covers the models and their JSON migrations, the store (undo, persistence, day and week
queries), the timer engine on a fake clock, the whole session flow, overlap packing and the
palette matcher. The Command Line Tools ship neither XCTest nor Swift Testing, so the tests
are an executable written against `Tests/TestKit`, a few dozen lines that mirror the XCTest
API. With Xcode installed they become a regular `.testTarget` by changing one import.
