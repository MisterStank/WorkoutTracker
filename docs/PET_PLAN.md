# Companion (pet) — redesign plan

Status: **planning**. The AI-art attempt was reverted; `pet-cosmetics` is back
at `main`. The backend game logic is intact and good — this plan is about the
**art pipeline** (made by hand this time) and **simplifying the system** so one
person can finish it.

---

## 1. What already exists (don't rebuild this)

### Backend — Go, working & tested

| Piece | File | Notes |
|---|---|---|
| Game "brain" | `internal/service/pet_rules.go` | Pure functions over `(training history, now)`. **Mood, streak, stage are all derived on read** — no stored snapshot, nothing to reconcile after an offline workout. Keep this design. |
| Tuning | `DefaultPetTuning` | weekly target 3 · stage gates `[0, 5, 20, 50, 120]` cumulative finished workouts · champion also needs longest-streak ≥ 14 · streak grace 1 day · mood −8/day after a 3-day grace. |
| Unlock rules | `evaluateUnlocks` in `pet_rules.go` | Computes ~26 achievement codes from history (`workouts_N`, `streak_N`, `pr_N`, `early_bird`, …). |
| Persistence | `pets`, `accessory_catalog`, `pet_accessories` tables | Only `stage` + `longest_streak` + `hatched_at` are stored on the pet; everything else is derived. |
| API | `internal/graphql` | `pet(tzOffsetMinutes)` query; `createPet` / `renamePet` / `setPetColor` / `equipAccessory` / `unequipAccessory`. Sends **asset *keys*** (`pet/{species}/{stage}`, `expr/{mood}`, `acc/{code}`), never images — the render layer is swappable. |

### Mobile — Flutter

`PetAvatar` (placeholder polygon painter) · `pet_home_screen` · `pet_detail_screen`
(wardrobe) · `pet_onboarding_screen` · `pet_provider` / `pet_repository` · offline
cache (`PetCache` Drift table) · `PetShareCard`.

### Current enums

- species `SPROUT · EMBER · PEBBLE · DRIFT`
- stage `EGG · HATCHLING · JUVENILE · ADULT · CHAMPION`
- mood `HAPPY · CONTENT · LOW · NEGLECTED`
- colour `GREEN · RED · BLUE · AMBER · VIOLET`

---

## 2. The lesson from the failed attempt

Every `(species × stage × expression × colour)` combination was treated as a
separate illustration → dozens of images that drift in style and can't be kept
consistent. **The rule from here on:** states are cheap — one rig, one palette,
components/frames — never a fresh drawing per state.

---

## 3. Art tool — DECISION NEEDED

### Option A — Aseprite (pixel art) · **recommended**

- ~$20 one-time · <https://www.aseprite.org>
- Pixel art is forgiving; a 64–96 px sprite with a small palette looks charming
  even from a non-artist. Classic Tamagotchi / Pokémon-Gen-1 feel.
- **Animation timeline built in** — idle breathe, blink, a post-workout hop are
  2–4 frames each.
- Exports sprite sheets or per-frame PNGs. Whole pet ≈ 5–20 KB.
- Runtime recolour via indexed palette (keeps the colour feature for free).
- Flutter: plain `Image.asset` for frames + a small sprite-sheet animator. **No
  new dependency.**

### Option B — Rive · for a smoother, "alive" mascot

- Free tier · <https://rive.app>
- Design + rig + animate in one app → one tiny `.riv` (~30–100 KB) per creature.
- **State machine**: feed inputs (`stage` 0–4, `mood` 0–3, `blink`/`celebrate`
  triggers) and it blends animations. One rig covers every state — no redundant
  art.
- Best for reactions (perk up on app open, celebrate after a workout).
- Flutter: the official `rive` package.
- Cost: real learning curve; rigging is a skill.

### Not this

Illustrator / After Effects (subscription, overkill) · Spine ($$$) ·
hand-drawn raster illustration per state (the trap). Figma / Inkscape / Affinity
are acceptable **only** if you want flat vector and use components religiously.

**Recommendation: Aseprite.** Lowest effort for a good result, tiny assets,
animation included.

> **Chosen tool:** _(fill in)_

---

## 4. Asset contract — lock before drawing

| Item | Recommendation | Chosen |
|---|---|---|
| Canvas | fixed square (e.g. 96×96), transparent bg, feet on a constant baseline row | |
| Path convention (frames) | `assets/pet/<species>/<stage>.png`, optional `_sad` variant; idle/blink as extra frames or a sheet | |
| Path convention (Rive) | `assets/pet/<species>.riv`, one state machine | |
| Expressions to draw | **2** — `content` + `sad`. `happy` = content + bounce animation; `neglected` = `sad` + code desaturation. | |
| Stages | **4** — egg · baby · teen · adult. Champion = "adult + a glow frame" drawn once. (Keeping 5 is fine too.) | |
| Idle animation | per stage: 2-frame breathe + 2-frame blink. Nothing else for v1. | |
| Recolour | Aseprite indexed palette → keep 5 colours. Rive colour bindings → keep. Otherwise **drop `PetColor`**. | |

**Do a vertical slice first:** one species, all its stages, `content` +
`sad` + idle/blink. Wire it in. Run it on device. *Then* make the rest.

---

## 5. Phased plan

### Phase 0 — Slice
1. Pick the tool.
2. Make one species: 4 stages × (content + sad) + idle + blink.
3. Wire into `PetAvatar` behind the existing asset-key system, keep an
   `errorBuilder` → simple placeholder.
4. `flutter run` on device. Sign-off on look + pipeline, or bail cheaply.

### Phase 1 — Species & enum
- **Recommended: reduce to ONE species.** "Which creature" multiplies all art
  cost for little value and is what made the last attempt explode. One creature,
  named (and maybe recoloured), is the cheapest good option.
- If keeping ≥2 species: rename the enum in **one deliberate commit** —
  `migrations/00NN_*.sql` + `go run github.com/99designs/gqlgen generate` +
  mobile `PetSpecies` enum + `cmd/seed`. (This step broke things before; do it
  carefully, verify `go build ./...` and `flutter analyze` before moving on.)

### Phase 2 — Full art
Remaining stages / species / expressions per §4. Onboarding picker and share
card switch to real art.

### Phase 3 — Flutter integration
- Rewrite `PetAvatar` for the chosen format (sprite frames **or** `rive`).
- Bundle `assets/pet/` in `pubspec.yaml`.
- Delete the code-side motion system — motion now lives in the art (Aseprite
  frames / Rive state machine).

### Phase 4 — System changes (§6) + regenerate the 4 pet doc screenshots.

---

## 6. Pet-system rethink

### Keep (these are good)
Derived mood · streak with 1-day grace · evolution gated on workout count ·
"asset keys not images" seam · offline cache.

### Change

**6.1 Accessories → badge wall.**
Stop equipping cosmetics on the pet. The ~26 unlocks become a **grid on the pet
detail screen** — earned (bright) vs locked (greyed + hint like "Reach a 7-day
streak").
- Backend: keep `evaluateUnlocks` + the catalog rows (code, name, hint).
  **Drop** `pet_accessories.slot`, `.equipped`, `equipAccessory` /
  `unequipAccessory`, the one-per-slot index. One migration.
- Zero pet-render cost. Badge icons can be tiny pixel icons or even Material
  icons. Nothing composites on the creature — ever.

**6.2 Expressions 4 → 3.**
Draw `content` + `sad`. `neglected` = `sad` + desaturate in code.

**6.3 Stages 5 → 4 (optional).**
Egg · Baby · Teen · Adult. Champion = "Adult + glow". Or keep 5.

**6.4 Colours — keep only if free from the tool** (indexed palette / Rive
bindings). Otherwise remove `PetColor` and `setPetColor`.

**6.5 One new low-cost delight (pick ≤1 for v1):**
- **Post-workout celebration** — pet plays a one-off hop/cheer on
  `finishWorkout`. One 4-frame animation or one Rive trigger. Best
  delight-per-effort.
- **Home background tiers** — pet sits in a scene that upgrades with total
  workouts (bare → mat → rack → trophy room). 3–4 full-bleed backgrounds, no
  anchoring.
- Nothing that requires art *on* the creature.

**6.6 Reframe the feature.** Not "the headline feature with deep
customization" — that framing drove the accessory ambition. It's **"your
training companion"**: prominent on the home tab, it grows and reacts. Its depth
is *evolution + streak + badges + a reaction*, not a wardrobe. That's a complete
loop one person can finish in ~a week.

---

## 7. Open decisions

- [ ] Art tool: Aseprite or Rive
- [ ] One species, or keep/rename multiple
- [ ] Stages: 4 or 5
- [ ] Keep the 5 colours
- [ ] Which §6.5 delight (or none for v1)
- [ ] Badge-wall now, or defer accessories entirely for v1
