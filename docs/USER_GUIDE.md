# WorkoutTracker — User Guide

Everything the app does, and how to use it. Covers the mobile app end to end, in the order you'll actually meet each screen.

## Contents

1. [Getting started](#1-getting-started)
2. [Starting a workout](#2-starting-a-workout)
3. [Logging a set](#3-logging-a-set)
4. [Supersets](#4-supersets)
5. [Templates](#5-templates)
6. [Offline logging](#6-offline-logging)
7. [Progress & records](#7-progress--records)
8. [Coaching signals](#8-coaching-signals)
9. [Live sharing](#9-live-sharing)
10. [Units & settings](#10-units--settings)

## 1. Getting started

Create an account with your email, a password, and a display name. Once you're in, you stay signed in — the app refreshes your session automatically, so you won't be asked to log in again until you explicitly sign out.

1. Open the app and tap **Sign up** from the login screen.
2. Enter your email, a password, and the name you want to appear in the app.
3. You're dropped straight into the home screen — no separate verification step.

Already have an account? Use **Log in** instead. To sign out at any time, open the **⋮** menu on the Home tab and tap **Log out**.

The app has four main tabs at the bottom of the screen — **Home**, **History**, **Templates**, and **Progress** — everything below is organized around them.

## 2. Starting a workout

From the **Home** tab, tap **Start workout**. You'll be asked to choose:

- **Blank workout** — starts immediately with nothing planned. Add exercises as you go — the natural choice if you're training by feel today.
- **From a template** — opens your saved templates. Pick one and the app pre-loads its exercises as a checklist you tap through as you train.

Once a workout is running, the top bar shows a live elapsed-time clock and your set count for the session. Only one workout can be active at a time — finishing or starting a new one closes out the last.

**Finishing up**: tap **Finish workout** at the bottom of the screen. You can add optional notes about how the session went before confirming — these are saved with the workout and visible later in your history.

## 3. Logging a set

Tap **Log set** (the floating button on an active workout) and search for an exercise, or tap one already on screen — either a planned exercise chip or an exercise card you've already started. This opens the set sheet:

1. Enter **reps** and **weight**. If you've done this exercise before, both fields pre-fill with your last set — you'll usually just need to confirm or tweak them.
2. Optionally log **RPE** (rate of perceived exertion, 1–10) — how hard that set felt. This is what powers the coaching suggestions in [Chapter 8](#8-coaching-signals).
3. Choose a **set type**, then tap **Log set**.

### Set types

| Type | Meaning | Counts toward PRs? |
|---|---|---|
| Normal | A working set at full effort. | Yes |
| Warm-up | Ramping up before working weight. | No |
| Drop set | Reduced weight, continued past failure. | Yes |
| Failure | Taken to muscular failure. | Yes |

Every logged set beyond a warm-up is checked against your history for three kinds of personal record: heaviest weight, best single-set volume (weight × reps), and estimated one-rep max. Beat one and a gold banner appears above your set list naming which record fell.

**Plate calculator**: tap the calculator icon in the set sheet to see which plates to load per side of the bar for the weight you've entered — useful mid-set when doing the arithmetic in your head is the last thing you want to do.

**Repeat last set**: each exercise card in an active workout has a **Repeat last** button — logs another set identical to the one before it (same reps, weight, RPE, and set type) in a single tap, for straight sets across working sets.

**Rest timer**: logging a set starts a rest timer automatically, shown as a countdown ring above your exercise list. Add fifteen seconds with the **+** button, or tap **Skip** to end the rest early.

## 4. Supersets

A superset links two or more exercises you alternate between with no rest in between. WorkoutTracker supports both ways people actually plan them:

- **Planned, in a template** — when building a template, tap **Group with previous** on an exercise to link it to the one above. Linked exercises show a connecting icon between their chips whenever that template is in use.
- **Ad hoc, mid-workout** — tap the link icon in the top bar during an active workout, select two or more exercises, and confirm. Every set you log for those exercises from then on is tagged as part of that group, for that session only.

A linked-set icon appears next to any set that's part of a superset, so you can see the pairing directly in your set list, not just in the planning view.

## 5. Templates

Open the **Templates** tab to see everything you've saved. From here:

- **Create one** — tap **New template**, name it, and add exercises with a target set count each. Group any of them into supersets as you go.
- **Start from one** — tap a template to launch a workout pre-loaded with its exercise list.
- **Delete one** — swipe or use the delete action on a template you no longer use. This doesn't touch any workouts you've already logged from it.

Once a template-based workout is running, its planned exercises appear as a row of chips up top — each shows your progress toward the target set count and turns green when complete, so you always know what's left.

## 6. Offline logging

If a set fails to save because you've got no connection, it isn't lost — it's queued on your device and shown immediately with a small cloud-off icon so you know it hasn't synced yet. The app keeps checking for connectivity in the background and pushes every queued set the moment it's back, swapping the placeholder for the confirmed, PR-checked result automatically.

> Nothing to do here. Log sets exactly as normal, connected or not — the queue and retry are automatic.

## 7. Progress & records

Open the **Progress** tab. It has three sub-tabs of its own:

- **Volume** — total weight moved per day across all exercises, over the last 90 days — the highest-level view of whether you're training more or less than you used to.
- **By exercise** — pick any exercise to chart your heaviest set over time. If you haven't beaten your best in three weeks despite training it, a plateau notice appears — see [Chapter 8](#8-coaching-signals).
- **Measurements** — track body weight and five circumference measurements — waist, chest, arms, thighs, hips — each on its own chart. Choose a measurement from the dropdown, tap **Log**, and enter today's reading.

Personal records are tracked per exercise across three categories — heaviest weight, best volume, and estimated one-rep max — and surface automatically as the gold banner described in [Chapter 3](#3-logging-a-set), not as a separate screen you have to check.

Each entry in the **History** tab also shows that session's total volume, so you don't need to open a workout to see roughly how much work it was.

## 8. Coaching signals

### Next-set suggestions

Open the set sheet for an exercise you've logged before with an RPE, and a suggestion appears above the input fields, with the weight and reps already filled in:

| Last RPE | Suggestion |
|---|---|
| ≤ 7.0 | Felt easy — weight increased about 2.5%. |
| 7.5 – 8.5 | Solid effort — same weight, aim for an extra rep. |
| > 8.5 | Near failure — weight reduced about 5%. |

No RPE logged yet for that exercise? The sheet just pre-fills your last set with no suggestion attached — log an RPE once and suggestions start from the next time.

### Plateau notices

> **No new best in three weeks.** The [By exercise](#7-progress--records) tab shows a banner like this only when you've genuinely trained that lift at least twice recently without progressing — not simply because you haven't touched it lately. Take it as a cue to deload, change rep ranges, or swap in a variation.

## 9. Live sharing

Let someone watch your session as you log it — no account link-up required.

- **Share your workout** — while a workout is active, tap the share icon in the top bar. A six-character code appears — read it out or send it to whoever you want watching.
- **Watch someone else's** — tap the eye icon, enter the code you were given, and tap **Watch**. Their sets appear live as they log them, for the rest of that session.

The view is read-only and expires with the workout: once it's finished, the code stops working. There's no separate follower or friends list — the code itself is the invitation.

## 10. Units & settings

Tap the **KG** / **LB** label in the Home tab's top bar to switch your preferred weight unit. This changes how weight is displayed and entered across the entire app — set logging, history, progress charts, and body weight — in one place. Everything is still stored in kilograms behind the scenes, so switching back and forth never loses precision.

**Theme**: open the **⋮** menu on the Home tab and choose **System**, **Light**, or **Dark** — System follows your device's setting, and your choice is remembered.

---

If a screen doesn't match what's described here, the app has likely moved on since this guide was written — the underlying ideas (log fast, adapt to effort, keep working offline) won't have.
