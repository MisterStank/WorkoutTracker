// Command seed populates a demo account with several weeks of realistic
// workout history — progressive overload across a push/pull/legs split,
// occasional warm-up sets, and a bodyweight trend — so screens that are
// otherwise empty on a fresh database (progress charts, history, PRs) have
// something meaningful to look at. Idempotent: re-running it replaces the
// demo user's data rather than appending to it.
//
// Usage: go run ./cmd/seed
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"time"

	"gymon/internal/platform"
	"gymon/internal/service"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	demoEmail    = "demo@gymon.app"
	demoPassword = "demo12345"
	weeks        = 8
	// Extra light workouts on each of the last streakDays calendar days, so
	// the demo companion has a live training streak (not just historical
	// progressive-overload weeks on Mon/Wed/Fri).
	streakDays = 12
)

// One push/pull/legs split, run 3x/week. Weight is the working-set starting
// point (kg) and increments a little each week to show progression on the
// charts; restDay offsets pick Mon/Wed/Fri within each week.
type exercisePlan struct {
	name        string
	startWeight float64
	weeklyGain  float64
	repsLow     int
	repsHigh    int
}

var splits = [][]exercisePlan{
	{ // push
		{"Barbell Bench Press", 60, 1.25, 5, 8},
		{"Overhead Press", 40, 1.0, 6, 8},
		{"Triceps Pushdown", 25, 1.0, 8, 12},
	},
	{ // pull
		{"Conventional Deadlift", 80, 2.5, 4, 6},
		{"Barbell Row", 45, 1.25, 6, 8},
		{"Dumbbell Bicep Curl", 12, 0.5, 8, 12},
	},
	{ // legs
		{"Barbell Back Squat", 70, 2.5, 5, 8},
		{"Leg Press", 90, 5.0, 8, 12},
		{"Plank", 0, 0, 1, 1}, // bodyweight hold; logged as a single low-weight "set"
	},
}

var dayOffsetInWeek = []int{0, 2, 4} // Mon, Wed, Fri

func main() {
	ctx := context.Background()
	cfg, err := platform.LoadConfig()
	if err != nil {
		log.Fatal(err)
	}

	db, err := platform.NewPostgresPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("connect to postgres: %v", err)
	}
	defer db.Close()

	userID, err := seedUser(ctx, db)
	if err != nil {
		log.Fatalf("seed user: %v", err)
	}

	exerciseIDs, err := loadExerciseIDs(ctx, db)
	if err != nil {
		log.Fatalf("load exercises: %v", err)
	}

	rng := rand.New(rand.NewSource(42)) // fixed seed: reproducible demo data

	now := time.Now()
	start := now.AddDate(0, 0, -weeks*7)
	workoutCount, setCount := 0, 0

	for week := 0; week < weeks; week++ {
		for splitIdx, plan := range splits {
			day := start.AddDate(0, 0, week*7+dayOffsetInWeek[splitIdx])
			workoutDate := time.Date(day.Year(), day.Month(), day.Day(), 18, 0, 0, 0, day.Location())
			if workoutDate.After(now) {
				continue
			}
			n, err := seedWorkout(ctx, db, userID, exerciseIDs, plan, week, workoutDate, rng)
			if err != nil {
				log.Fatalf("seed workout: %v", err)
			}
			workoutCount++
			setCount += n
		}
	}

	streakWorkouts, err := seedStreakFinisher(ctx, db, userID, exerciseIDs, now, rng)
	if err != nil {
		log.Fatalf("seed streak finisher: %v", err)
	}
	workoutCount += streakWorkouts

	if err := seedBodyMetrics(ctx, db, userID, start, now, rng); err != nil {
		log.Fatalf("seed body metrics: %v", err)
	}

	if err := seedPet(ctx, db, userID); err != nil {
		log.Fatalf("seed pet: %v", err)
	}

	fmt.Printf("Seeded demo account: %s / %s\n", demoEmail, demoPassword)
	fmt.Printf("  %d workouts (%d in a closing daily streak), %d sets\n", workoutCount, streakWorkouts, setCount)
}

func seedUser(ctx context.Context, db *pgxpool.Pool) (uuid.UUID, error) {
	hash, err := service.HashPassword(demoPassword)
	if err != nil {
		return uuid.Nil, err
	}

	// Idempotent re-seed: wipe any prior demo account (cascades to its
	// workouts/sets/PRs/body metrics via FK ON DELETE CASCADE).
	if _, err := db.Exec(ctx, `DELETE FROM users WHERE email = $1`, demoEmail); err != nil {
		return uuid.Nil, err
	}

	userID := uuid.New()
	_, err = db.Exec(ctx,
		`INSERT INTO users (id, email, password_hash, display_name, timezone, created_at)
		 VALUES ($1, $2, $3, $4, 'UTC', now())`,
		userID, demoEmail, hash, "Demo User",
	)
	return userID, err
}

func loadExerciseIDs(ctx context.Context, db *pgxpool.Pool) (map[string]uuid.UUID, error) {
	rows, err := db.Query(ctx, `SELECT id, name FROM exercises`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	ids := map[string]uuid.UUID{}
	for rows.Next() {
		var id uuid.UUID
		var name string
		if err := rows.Scan(&id, &name); err != nil {
			return nil, err
		}
		ids[name] = id
	}
	return ids, rows.Err()
}

// seedWorkout inserts one completed workout with a warm-up + 3 working sets
// per exercise in the split, then upserts personal_records and
// progress_daily_rollup exactly like WorkoutSetRepository.LogSet does —
// duplicated here (rather than reusing it) because LogSet always stamps
// performed_at as time.Now(), and backdated demo data needs control over
// that.
func seedWorkout(ctx context.Context, db *pgxpool.Pool, userID uuid.UUID, exerciseIDs map[string]uuid.UUID, plan []exercisePlan, week int, workoutDate time.Time, rng *rand.Rand) (int, error) {
	tx, err := db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	workoutID := uuid.New()
	endedAt := workoutDate.Add(50 * time.Minute)
	if _, err := tx.Exec(ctx,
		`INSERT INTO workouts (id, user_id, started_at, ended_at, notes, status)
		 VALUES ($1, $2, $3, $4, '', 'completed')`,
		workoutID, userID, workoutDate, endedAt,
	); err != nil {
		return 0, err
	}

	setNumber := 0
	setCount := 0
	for _, ex := range plan {
		exerciseID, ok := exerciseIDs[ex.name]
		if !ok {
			continue
		}

		workingWeight := ex.startWeight + ex.weeklyGain*float64(week)
		sets := 3
		if ex.startWeight == 0 {
			sets = 2 // bodyweight-only movement, keep it short
		}

		// A single light warm-up before the working sets, skipped for
		// bodyweight-only movements.
		if ex.startWeight > 0 {
			setNumber++
			warmupWeight := workingWeight * 0.5
			t := workoutDate.Add(time.Duration(setNumber) * 90 * time.Second)
			if err := logSeedSet(ctx, tx, userID, workoutID, exerciseID, setNumber, ex.repsHigh, warmupWeight, nil, true, t); err != nil {
				return 0, err
			}
			setCount++
		}

		for i := 0; i < sets; i++ {
			setNumber++
			reps := ex.repsLow + rng.Intn(ex.repsHigh-ex.repsLow+1)
			jitter := (rng.Float64() - 0.5) * ex.weeklyGain
			weight := roundToHalf(workingWeight + jitter)
			rpe := 6.5 + rng.Float64()*2.5
			t := workoutDate.Add(time.Duration(setNumber) * 90 * time.Second)
			if err := logSeedSet(ctx, tx, userID, workoutID, exerciseID, setNumber, reps, weight, &rpe, false, t); err != nil {
				return 0, err
			}
			setCount++
		}
	}

	return setCount, tx.Commit(ctx)
}

func roundToHalf(v float64) float64 {
	return float64(int(v*2+0.5)) / 2
}

// streakFinisherExercises rotates through a handful of compound lifts at
// steady working weights for the closing daily-streak block.
var streakFinisherExercises = []struct {
	name   string
	weight float64
	reps   int
}{
	{"Barbell Bench Press", 72.5, 6},
	{"Barbell Back Squat", 95, 6},
	{"Barbell Row", 57.5, 8},
	{"Overhead Press", 47.5, 7},
	{"Conventional Deadlift", 110, 4},
}

// seedStreakFinisher adds one short completed workout on each of the last
// streakDays calendar days (skipping any day the split weeks already
// covered), so the demo companion shows a live current streak rather than
// only historical Mon/Wed/Fri sessions. Returns how many it inserted.
func seedStreakFinisher(ctx context.Context, db *pgxpool.Pool, userID uuid.UUID, exerciseIDs map[string]uuid.UUID, now time.Time, rng *rand.Rand) (int, error) {
	inserted := 0
	for d := streakDays - 1; d >= 0; d-- {
		day := now.AddDate(0, 0, -d)
		workoutDate := time.Date(day.Year(), day.Month(), day.Day(), 7, 15, 0, 0, day.Location())
		if workoutDate.After(now) {
			continue
		}

		var exists bool
		if err := db.QueryRow(ctx,
			`SELECT EXISTS(
			   SELECT 1 FROM workouts
			   WHERE user_id = $1 AND status = 'completed'
			     AND date_trunc('day', ended_at) = date_trunc('day', $2::timestamptz))`,
			userID, workoutDate,
		).Scan(&exists); err != nil {
			return inserted, err
		}
		if exists {
			continue
		}

		ex := streakFinisherExercises[d%len(streakFinisherExercises)]
		exerciseID, ok := exerciseIDs[ex.name]
		if !ok {
			continue
		}

		tx, err := db.Begin(ctx)
		if err != nil {
			return inserted, err
		}
		workoutID := uuid.New()
		endedAt := workoutDate.Add(35 * time.Minute)
		if _, err := tx.Exec(ctx,
			`INSERT INTO workouts (id, user_id, started_at, ended_at, notes, status)
			 VALUES ($1, $2, $3, $4, '', 'completed')`,
			workoutID, userID, workoutDate, endedAt,
		); err != nil {
			_ = tx.Rollback(ctx)
			return inserted, err
		}
		for i := 0; i < 3; i++ {
			reps := ex.reps + rng.Intn(2)
			rpe := 7.0 + rng.Float64()*2.0
			t := workoutDate.Add(time.Duration(i+1) * 2 * time.Minute)
			if err := logSeedSet(ctx, tx, userID, workoutID, exerciseID, i+1, reps, ex.weight, &rpe, false, t); err != nil {
				_ = tx.Rollback(ctx)
				return inserted, err
			}
		}
		if err := tx.Commit(ctx); err != nil {
			return inserted, err
		}
		inserted++
	}
	return inserted, nil
}

// logSeedSet mirrors WorkoutSetRepository.LogSet's insert + PR-upsert +
// rollup-upsert logic, parameterized on an explicit performedAt instead of
// time.Now().
func logSeedSet(ctx context.Context, tx pgx.Tx, userID, workoutID, exerciseID uuid.UUID, setNumber, reps int, weightKg float64, rpe *float64, isWarmup bool, performedAt time.Time) error {
	setID := uuid.New()
	setType := "normal"
	if isWarmup {
		setType = "warmup"
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO workout_sets (id, workout_id, exercise_id, set_number, reps, weight_kg, rpe, set_type, performed_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		setID, workoutID, exerciseID, setNumber, reps, weightKg, rpe, setType, performedAt,
	); err != nil {
		return err
	}

	if isWarmup {
		return nil
	}

	candidates := map[string]float64{
		"max_weight":    weightKg,
		"max_volume":    weightKg * float64(reps),
		"estimated_1rm": weightKg * (1 + float64(reps)/30.0),
	}
	for recordType, value := range candidates {
		var returnedID uuid.UUID
		err := tx.QueryRow(ctx,
			`INSERT INTO personal_records (id, user_id, exercise_id, record_type, value, achieved_at, workout_set_id)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)
			 ON CONFLICT (user_id, exercise_id, record_type) DO UPDATE
			   SET value = EXCLUDED.value, achieved_at = EXCLUDED.achieved_at, workout_set_id = EXCLUDED.workout_set_id
			   WHERE personal_records.value < EXCLUDED.value
			 RETURNING id`,
			uuid.New(), userID, exerciseID, recordType, value, performedAt, setID,
		).Scan(&returnedID)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
	}

	volume := weightKg * float64(reps)
	if _, err := tx.Exec(ctx,
		`INSERT INTO progress_daily_rollup (user_id, exercise_id, day, total_volume, max_weight, set_count)
		 VALUES ($1, $2, date_trunc('day', $3::timestamptz), $4, $5, 1)
		 ON CONFLICT (user_id, exercise_id, day) DO UPDATE
		   SET total_volume = progress_daily_rollup.total_volume + EXCLUDED.total_volume,
		       max_weight = GREATEST(progress_daily_rollup.max_weight, EXCLUDED.max_weight),
		       set_count = progress_daily_rollup.set_count + 1`,
		userID, exerciseID, performedAt, volume, weightKg,
	); err != nil {
		return err
	}

	return nil
}

// seedBodyMetrics logs a bodyweight entry twice a week with a gentle
// downward trend plus noise, the way someone tracking a cut actually looks.
// seedPet gives the demo account a companion so the pet screen — the app's
// landing screen — has something to show. Mood, current streak, evolution
// stage and which accessories are unlocked are all derived on read from the
// workout history seeded above (see internal/service/pet_rules.go), so the
// row is created near-empty; longest_streak is pre-set because it's the one
// value the client can't rederive, and a couple of accessories are
// pre-equipped so the demo pet isn't bare. The DELETE FROM users re-seed
// already cascaded any prior pet away.
func seedPet(ctx context.Context, db *pgxpool.Pool, userID uuid.UUID) error {
	petID := uuid.New()
	hatched := time.Now().AddDate(0, 0, -50)
	if _, err := db.Exec(ctx,
		`INSERT INTO pets (id, user_id, name, species, color, stage, stage_updated_at, longest_streak, hatched_at, created_at)
		 VALUES ($1, $2, 'Pixel', 'sprout', 'green', 0, now(), $3, $4, $4)`,
		petID, userID, streakDays, hatched,
	); err != nil {
		return err
	}

	// Pre-equip one head + one collar accessory the seeded history is
	// guaranteed to have unlocked (1 workout, 10 workouts). A read grants the
	// rest via ON CONFLICT DO NOTHING, leaving these equipped.
	for _, code := range []string{"starter_band", "collar_bronze"} {
		if _, err := db.Exec(ctx,
			`INSERT INTO pet_accessories (pet_id, accessory_id, slot, unlocked_at, equipped)
			 SELECT $1, id, slot, now(), true FROM accessory_catalog WHERE code = $2`,
			petID, code,
		); err != nil {
			return err
		}
	}
	return nil
}

func seedBodyMetrics(ctx context.Context, db *pgxpool.Pool, userID uuid.UUID, start, now time.Time, rng *rand.Rand) error {
	const startWeight = 82.0
	const totalDrift = -2.5 // kg lost over the whole window

	totalDays := int(now.Sub(start).Hours() / 24)
	if totalDays <= 0 {
		return nil
	}

	for day := 0; day <= totalDays; day += 3 {
		t := start.AddDate(0, 0, day)
		if t.After(now) {
			break
		}
		progress := float64(day) / float64(totalDays)
		weight := startWeight + totalDrift*progress + (rng.Float64()-0.5)*0.6
		if _, err := db.Exec(ctx,
			`INSERT INTO body_metrics (id, user_id, metric_type, value, recorded_at)
			 VALUES ($1, $2, 'bodyweight_kg', $3, $4)`,
			uuid.New(), userID, roundToHalf(weight), t,
		); err != nil {
			return err
		}
	}
	return nil
}
