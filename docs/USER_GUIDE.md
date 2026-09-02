# Gymon — User Guide

Gymon is a virtual-companion game: you raise a pet that grows and stays happy only if you keep training. Under the companion layer is a full workout tracker. This covers the mobile app end to end, in the order you'll actually meet each screen.

## Contents

1. [Getting started](#1-getting-started)
2. [Starting a workout](#2-starting-a-workout)
3. [Logging a set](#3-logging-a-set)
4. [Supersets](#4-supersets)
5. [Templates](#5-templates)
6. [Personalized programs](#6-personalized-programs)
7. [Offline logging](#7-offline-logging)
8. [Progress & records](#8-progress--records)
9. [Coaching signals](#9-coaching-signals)
10. [Sharing your stats](#10-sharing-your-stats)
11. [Units & settings](#11-units--settings)

## 1. Getting started

Create an account with your email, a password (at least 8 characters), and a display name. Once you're in, you stay signed in — the app refreshes your session automatically, so you won't be asked to log in again until you explicitly sign out.

1. Open the app and tap **Sign up** from the login screen.
2. Enter your email, a password (8+ characters), and the name you want to appear in the app. Bad values are flagged before the request is sent.
3. You're dropped straight into the home screen — no separate verification step.

<p>
  <img src="images/login-light.png" width="200" alt="Login screen, light theme">
  <img src="images/login-dark.png" width="200" alt="Login screen, dark theme">
</p>

Already have an account? Use **Log in** instead. To sign out, tap your **profile avatar** in the Home tab's top bar and choose **Log out**.

**First-run setup**: the first time you sign up — and the first time you log in on a device that hasn't seen it — Gymon walks you through setting up your companion. It's short and hands-on rather than a slideshow:

1. **Welcome** — what the companion is and why it exists.
2. **Choose your companion** — pick a species and colour and give it a name. This hatches your pet then and there.
3. **How it works** — the three rules: finishing a workout feeds and grows your companion; keeping a training streak unlocks accessories; disappearing for a week leaves it neglected (recoverable with one workout).
4. **Set up a program** (optional) — answer a few questions about your goal, experience and equipment to generate a training split. Skippable; you can do it later from the **Programs** tab.

Steps 1–3 have no Skip — they take under a minute and step 2 is the fun part — so everyone lands in the app knowing what the companion is for. If you're signing in on a device that's already seen this and your account already has a fitness profile or a program, the app skips it entirely. You can replay steps 1 and 3 any time from **View app tour** behind your profile avatar.

The app has five tabs at the bottom of the screen — **Companion** (your pet, and where you start a workout), **Train**, **History**, **Programs**, and **Progress**. Your saved single-day templates live one level in, behind the checklist icon on the **Programs** tab (see [Chapter 5](#5-templates)).

## 2. Starting a workout

From the **Home** tab, tap **Start workout**. You'll be asked to choose:

- **Blank workout** — starts immediately with nothing planned. Add exercises as you go — the natural choice if you're training by feel today.
- **From a template** — opens your saved templates. Pick one and the app pre-loads every planned exercise as its own card, ready to log against — no need to add anything before you start.

<p>
  <img src="images/start-workout-sheet.png" width="220" alt="Choosing how to start a workout">
</p>

Once a workout is running, the top bar shows a live elapsed-time clock and your set count for the session. Only one workout can be active at a time — if you already have one running, tapping **Start workout** just takes you back to it rather than starting a fresh one.

**Jumping back in**: if you switch to another tab mid-workout, a slim bar appears above the bottom navigation showing your elapsed time and set count. Tap it from anywhere in the app to return straight to your active workout.

<p>
  <img src="images/resume-bar.png" width="220" alt="Resume-workout bar visible on a non-Home tab">
</p>

**Finishing up**: tap **Finish workout** at the bottom of the screen. The panel that opens is a bottom sheet, not a cramped dialog — a set-count and duration line at the top, an optional notes field (saved with the workout, visible later in history), then **Finish workout** and **Keep going** stacked full-width, with **Discard workout** set apart below a divider so it can't be mis-tapped for the button next to it. If you tap Finish without having logged any sets, the app offers to discard the empty session rather than clutter your history with it.

## 3. Logging a set

Tap **Log set** (the floating button on an active workout) and search for an exercise, or tap one already on screen — either a planned exercise chip or an exercise card. For a template-based workout, every planned exercise already has a card waiting, even before you've logged anything against it — tap **Add set** on an empty card to get started.

<p>
  <img src="images/exercise-picker.png" width="220" alt="Picking an exercise to log">
</p>

Tapping either opens the set sheet:

1. Enter **reps** (1–100) and **weight** (0–1000 kg / equivalent in lb). If you've done this exercise before, both fields pre-fill with your last set — you'll usually just need to confirm or tweak them.
2. Optionally log **RPE** (rate of perceived exertion, 1–10 in half-point steps) — how hard that set felt. This is what powers the coaching suggestions in [Chapter 9](#9-coaching-signals).
3. Choose a **set type**, then tap **Log set**. Values outside the ranges above are rejected with an explanation.

<p>
  <img src="images/log-set-sheet.png" width="220" alt="The set-logging sheet">
</p>

### Set types

| Type | Meaning | Counts toward PRs? |
|---|---|---|
| Normal | A working set at full effort. | Yes |
| Warm-up | Ramping up before working weight. | No |
| Drop set | Reduced weight, continued past failure. | Yes |
| Failure | Taken to muscular failure. | Yes |

Every logged set beyond a warm-up is checked against your history for four kinds of personal record: heaviest weight, best single-set volume (weight × reps), estimated one-rep max, and most reps in a set. Beat one and a gold banner appears above your set list naming which record fell — tap the share icon on that banner to post it, see [Chapter 10](#10-sharing-your-stats).

**Custom exercises**: not in the built-in list? Tap **+** in the exercise picker (or, when a search comes up empty, the **Create "…"** button) to add your own — a name, a category, its equipment, and optionally the muscle groups it trains. Custom exercises work everywhere a built-in does, including as candidates when a program is generated. Long-press a custom exercise in the picker to edit or delete it (deletion is blocked while it's used by a logged set or a template).

**Bodyweight exercises**: for anything tagged *bodyweight* (pull-ups, dips, push-ups…), the weight field means *added* load — enter `0` for plain bodyweight, a positive number for weighted, or a negative number for assisted. Since the weight stays at zero, the **most reps** record is what tracks progress here, and the "By exercise" chart defaults to reps for them.

**Plate calculator**: tap the calculator icon in the set sheet and a little barbell diagram shows which plates to load per side for the weight you've entered — drawn to scale and colour-coded by size. Pick your bar with the **20 / 15 / 10 kg** presets (it remembers which you use) or type a custom weight; a line underneath confirms the exact total it loads to, or flags it when standard plates can't hit your target.

<p>
  <img src="images/plate-calculator.png" width="220" alt="Plate calculator — a barbell diagram of the plates per side">
</p>

**Repeat last set**: each exercise card in an active workout has a **Repeat last** button — logs another set identical to the one before it (same reps, weight, RPE, and set type) in a single tap, for straight sets across working sets.

<p>
  <img src="images/set-logged-rest-timer.png" width="220" alt="A logged set with the rest timer running">
</p>

**Fixing a mistake**: tap the **⋮** on any logged set to **Edit** or **Delete** it. Editing or removing a set that was holding a personal record automatically updates your records to whatever the next-best set was — nothing is left pointing at a set that no longer exists.

<p>
  <img src="images/edit-delete-set.png" width="220" alt="Edit or delete a logged set">
</p>

**Rest timer**: logging a set starts a rest timer automatically, shown as a countdown ring above your exercise list. Add fifteen seconds with the **+** button, or tap **Skip** to end the rest early. When it reaches zero it fires a notification (with sound and vibration) so you don't have to keep the screen open. Long-press the **+** button to change the default rest length.

## 4. Supersets

A superset links two or more exercises you alternate between with no rest in between. WorkoutTracker supports both ways people actually plan them:

- **Planned, in a template** — when building or editing a template, tap **Group as superset** between an exercise and the one above it to link them. Linked exercises show a connecting icon between their chips whenever that template is in use.
- **Ad hoc, mid-workout** — tap the link icon in the top bar during an active workout, select two or more exercises, and confirm. Every set you log for those exercises from then on is tagged as part of that group, for that session only.

A linked-set icon appears next to any set that's part of a superset, so you can see the pairing directly in your set list, not just in the planning view.

## 5. Templates

Templates aren't a bottom-nav tab of their own — open the **checklist icon** in the top bar of the **Programs** tab to reach the template library. From there:

- **Create one** — tap **New template**, name it, and add exercises with a target set count each. Group any of them into supersets as you go.
- **Edit one** — tap a template to open it for editing (rename, add/remove exercises, change target sets, regroup supersets). This works on generated program days too.
- **Start from one** — tap the **▶** button on a template to launch a workout pre-loaded with its exercise list. (When you reach the same list via **Start workout → From a template**, tapping the row starts it directly instead of opening the editor.)
- **Delete one** — swipe, or use the delete action on a template you no longer use. This doesn't touch any workouts you've already logged from it.

To build a whole program instead of one template at a time, use the sparkle or **+** icons on the **Programs** tab — see [Chapter 6](#6-personalized-programs).

<p>
  <img src="images/templates-saved.png" width="220" alt="Saved templates list">
  <img src="images/templates-list.png" width="220" alt="Templates tab including a generated program">
</p>

Once a template-based workout is running, its planned exercises appear both as a row of progress chips up top and as a full card each further down — see [Chapter 2](#2-starting-a-workout).

<p>
  <img src="images/prepopulated-cards.png" width="220" alt="Pre-populated exercise cards when starting from a template">
</p>

## 6. Personalized programs

Don't want to build templates by hand? On the **Programs** tab, tap the sparkle icon to generate a full multi-day training split from a short questionnaire (or the **+** icon to assemble a program from templates you've already made):

1. **Goal** — strength, hypertrophy, fat loss, or general fitness. This drives the sets, reps, and exercise selection for every day.
2. **Experience level** — beginner, intermediate, or advanced.
3. **Days per week** — how many days you can train, from 1 to 7. This decides the split itself: 1–3 days is full-body, 4 is upper/lower, 5–7 is a push/pull/legs rotation. Every lower-body or full-body day is built around both a squat (knee-dominant) and a hinge (hip-dominant) movement so hamstrings and glutes aren't skipped; push days pair a horizontal and a vertical press, pull days a horizontal and a vertical pull.
4. **Equipment access** — barbell, dumbbell, bodyweight, cable, machine, or any combination. Only exercises you can actually perform are selected.
5. **Areas to avoid** — any muscle groups to leave out entirely, for working around an injury or a personal preference.

<p>
  <img src="images/program-generator.png" width="220" alt="The program generator form">
</p>

Tap **Generate** and the app builds a named, multi-day program — for example a 4-day Upper/Lower split — with each day also saved as its own template in the library, ready to start a workout from exactly like any template you built by hand. If your equipment or avoid-list is restrictive enough that a movement pattern can't be filled on some day, the program still generates with a note explaining what was skipped, rather than failing outright.

Your answers are remembered — reopening the generator next time pre-fills your last profile, so tweaking and regenerating is quick.

**Week-to-week progression**: a generated program carries a progression rule based on your goal — *linear* (add a little weight each week) for strength, *double progression* (add reps to the top of the range, then weight) for hypertrophy, or *maintain* otherwise. The program review screen shows which one you're on, and Home's **Continue** card shows which week of the program you're in. When you start a workout from a program day, the set sheet pre-fills a suggested weight for each planned exercise from that rule and your training history — including a deload roughly every fourth week.

**Finding a program again**: the **Programs** tab itself is the list — every program you've generated or built, newest first, each showing its goal and days per week, with a check mark on the one you're currently following. Tap one to reopen the review screen you saw right after generating it (mark it active, start any day, see its progression rule). Individual days always show up as ordinary templates in the library too — the Programs list is just the grouped view tying them back together.

<p>
  <img src="images/my-programs-list.png" width="220" alt="My Programs list, showing every generated program">
</p>

## 7. Offline logging

If a set fails to save because you've got no connection, it isn't lost — it's queued on your device and shown immediately with a small cloud-off icon so you know it hasn't synced yet. The app keeps checking for connectivity in the background and pushes every queued set the moment it's back, swapping the placeholder for the confirmed, PR-checked result automatically.

> Nothing to do here. Log sets exactly as normal, connected or not — the queue and retry are automatic.

## 8. Progress & records

Open the **Progress** tab. It has four sub-tabs of its own:

- **Volume** — total weight moved per day across all exercises, over the last 90 days — the highest-level view of whether you're training more or less than you used to.
- **By exercise** — pick any exercise and chart it by **Weight**, **Reps**, or **Volume** over time (bodyweight exercises default to Reps). If you haven't beaten your best in three weeks despite training it, a plateau notice appears — see [Chapter 9](#9-coaching-signals).
- **Records** — every all-time personal record you hold, grouped by exercise with the date it was set — so a PR that scrolled past the in-workout banner isn't lost.
- **Measurements** — track body weight and five circumference measurements — waist, chest, arms, thighs, hips — each on its own chart. Choose a measurement from the dropdown, tap **Log**, and enter today's reading. Circumferences can be entered and shown in **cm** or **in** (toggle beside the Log button); body weight follows your app-wide KG/LB setting.

<p>
  <img src="images/progress-volume-light.png" width="220" alt="Volume chart, light theme">
  <img src="images/progress-volume-dark.png" width="220" alt="Volume chart, dark theme">
</p>

Personal records are tracked per exercise across four categories — heaviest weight, best volume, estimated one-rep max, and most reps — and surface automatically as the gold banner described in [Chapter 3](#3-logging-a-set) as you hit them. The **Records** sub-tab is the place to browse all of them after the fact.

Each entry in the **History** tab also shows that session's total volume, so you don't need to open a workout to see roughly how much work it was.

<p>
  <img src="images/workout-history.png" width="220" alt="Workout history list">
</p>

**Fixing a past workout**: tap a card in the **History** tab to open the session and correct a mis-logged set — edit or delete any set the same way you would during the workout. You're warned once that this recalculates your personal records for that exercise.

**Deleting a workout**: swipe a card left in the **History** tab and confirm to remove the entire session, including its sets. This can't be undone.

## 9. Coaching signals

### Next-set suggestions

Open the set sheet for an exercise you've logged before with an RPE, and a suggestion appears above the input fields, with the weight and reps already filled in:

| Last RPE | Suggestion |
|---|---|
| ≤ 7.0 | Felt easy — weight increased about 2.5%. |
| 7.5 – 8.5 | Solid effort — same weight, aim for an extra rep. |
| > 8.5 | Near failure — weight reduced about 5%. |

The suggested weight always lands on a loadable **2.5 kg / 5 lb** step (and "same weight" hands back exactly what you last lifted), so you're never told to load a number you can't actually make.

No RPE logged yet for that exercise? The sheet just pre-fills your last set with no suggestion attached — log an RPE once and suggestions start from the next time.

When the workout was started from a **program day**, the suggestion instead comes from that program's week-to-week progression rule (see [Chapter 6](#6-personalized-programs)) — labelled "Week N · …" — rather than this RPE table.

### Plateau notices

> **No new best in three weeks.** The [By exercise](#8-progress--records) tab shows a banner like this only when you've genuinely trained that lift at least twice recently without progressing — not simply because you haven't touched it lately. Take it as a cue to deload, change rep ranges, or swap in a variation.

## 10. Sharing your stats

WorkoutTracker doesn't do live workout sharing — instead, you get a shareable image any time you hit a milestone worth showing off:

- **A new personal record**: when the gold PR banner appears (see [Chapter 3](#3-logging-a-set)), tap its share icon to preview a card with the exercise, the record you hit, and the new value.
- **A finished workout**: after tapping **Finish workout**, a **Share** action appears alongside the confirmation — it opens a card summarizing that session's total sets, volume, duration, and exercise list.

<p>
  <img src="images/share-pr-card.png" width="220" alt="PR share card preview">
  <img src="images/share-workout-summary.png" width="220" alt="Workout summary share card preview">
</p>

Either way, you get a preview first. It has **Download image** — a plain download, or your Files app — and **Share…**, which hands the image to your device's share sheet so you can post it wherever you like (Instagram, messages, etc.). Nothing leaves the app until you pick one. Both cards render with the same fixed dark red-and-black look regardless of your app theme, so the image looks consistent no matter which theme you're using.

## 11. Units & settings

Everything here lives behind your **profile avatar** in the Home tab's top bar — tap it to open the settings sheet.

**Units**: switch **Kilograms** / **Pounds**. This changes how weight is displayed and entered across the entire app — set logging, history, progress charts, and body weight — in one place. Everything is still stored in kilograms behind the scenes, so switching back and forth never loses precision.

**Appearance**: choose **System**, **Light**, or **Dark** — System follows your device's setting, and your choice is remembered. The theme changes instantly, so you can see it before closing the sheet.

---

If a screen doesn't match what's described here, the app has likely moved on since this guide was written — the underlying ideas (log fast, adapt to effort, keep working offline) won't have.
