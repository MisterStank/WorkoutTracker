package service

import (
	"time"

	"gymon/internal/domain"
)

// This file is the pet's whole game-design brain, kept as pure functions over
// (training history, now) so every rule is unit-testable without a database
// and the numbers live in one place. Nothing here reads or writes state.

// PetTuning holds the tunable constants. Defaults are in DefaultPetTuning;
// the service loads overrides from config so they can be adjusted without a
// code change.
type PetTuning struct {
	// WeeklyTarget is the number of finished workouts per rolling 7 days that
	// keeps a pet fully happy.
	WeeklyTarget int
	// MoodBaseline is where mood sits with no recent training and no long
	// absence — the neutral middle.
	MoodBaseline int
	// MoodTargetBonus is added on top of the baseline for hitting WeeklyTarget
	// in the trailing 7 days (scaled linearly below the target).
	MoodTargetBonus int
	// MoodOverBonusPerWorkout / MoodOverBonusCap reward training beyond the
	// target.
	MoodOverBonusPerWorkout int
	MoodOverBonusCap        int
	// DecayGraceDays is how many days since the last workout are forgiven
	// before the staleness penalty starts.
	DecayGraceDays int
	// DecayPerDay is the mood lost for each day past the grace period with no
	// workout.
	DecayPerDay int
	// StreakGraceDays is how many consecutive calendar days may be missed
	// without breaking the streak (1 = miss a day, streak holds; miss two, it
	// breaks).
	StreakGraceDays int
	// StageWorkoutGates[i] is the cumulative finished-workout count required to
	// reach stage i (index 0 is the egg, always 0).
	StageWorkoutGates [5]int
	// ChampionStreakGate is the longest-streak-ever also required for the
	// final stage.
	ChampionStreakGate int
}

var DefaultPetTuning = PetTuning{
	WeeklyTarget:            3,
	MoodBaseline:            50,
	MoodTargetBonus:         40,
	MoodOverBonusPerWorkout: 4,
	MoodOverBonusCap:        10,
	DecayGraceDays:          3,
	DecayPerDay:             8,
	StreakGraceDays:         1,
	StageWorkoutGates:       [5]int{0, 5, 20, 50, 120},
	ChampionStreakGate:      14,
}

// PetComputed is the full derived view of a pet for one read: everything the
// GraphQL layer needs that is not stored on the row.
type PetComputed struct {
	Mood                int
	MoodState           domain.MoodState
	CurrentStreak       int
	Stage               domain.PetStage
	WorkoutsToNextStage *int
	// UnlockedCodes is the set of accessory unlock_codes the user currently
	// qualifies for. The service diffs this against what the pet already owns.
	UnlockedCodes map[string]bool
}

// ComputePet runs every rule for one read. tzOffsetMinutes is the viewer's
// UTC offset (east-positive), used so "day" boundaries for streaks match the
// user's local midnight rather than the server's.
func ComputePet(t PetTuning, pet *domain.Pet, snap *domain.PetStatsSnapshot, now time.Time, tzOffsetMinutes int) PetComputed {
	loc := time.FixedZone("viewer", tzOffsetMinutes*60)
	ends := snap.FinishedWorkoutEndTimes

	streak := currentStreak(t, now, loc, ends)
	longest := pet.LongestStreak
	if streak > longest {
		longest = streak
	}

	mood := computeMood(t, now, ends)
	stage := computeStage(t, len(ends), longest)

	var toNext *int
	if stage < domain.PetStageChampion {
		remaining := t.StageWorkoutGates[stage+1] - len(ends)
		if remaining < 0 {
			remaining = 0
		}
		toNext = &remaining
	}

	return PetComputed{
		Mood:                mood,
		MoodState:           moodState(mood),
		CurrentStreak:       streak,
		Stage:               stage,
		WorkoutsToNextStage: toNext,
		UnlockedCodes:       evaluateUnlocks(t, snap, longest, now, loc),
	}
}

// computeMood derives the 0..100 mood. It is not an accumulator of "+25 per
// workout" deltas — that value would need a stored snapshot and offline
// reconciliation. Instead it is a direct function of how much training landed
// in the trailing 7 days (each workout there lifts mood substantially, which
// is the "+25" felt in practice) minus a penalty that grows the longer it has
// been since the last workout.
func computeMood(t PetTuning, now time.Time, endsDesc []time.Time) int {
	if len(endsDesc) == 0 {
		return t.MoodBaseline - 10
	}

	weekAgo := now.AddDate(0, 0, -7)
	recent := 0
	for _, e := range endsDesc {
		if e.After(weekAgo) {
			recent++
		}
	}

	score := t.MoodBaseline
	if recent >= t.WeeklyTarget {
		score += t.MoodTargetBonus
		over := recent - t.WeeklyTarget
		bonus := over * t.MoodOverBonusPerWorkout
		if bonus > t.MoodOverBonusCap {
			bonus = t.MoodOverBonusCap
		}
		score += bonus
	} else {
		score += t.MoodTargetBonus * recent / t.WeeklyTarget
	}

	daysSinceLast := int(now.Sub(endsDesc[0]).Hours() / 24)
	if daysSinceLast > t.DecayGraceDays {
		score -= (daysSinceLast - t.DecayGraceDays) * t.DecayPerDay
	}

	return clampInt(score, 0, 100)
}

func moodState(mood int) domain.MoodState {
	switch {
	case mood >= 75:
		return domain.MoodHappy
	case mood >= 40:
		return domain.MoodContent
	case mood >= 20:
		return domain.MoodLow
	default:
		return domain.MoodNeglected
	}
}

func computeStage(t PetTuning, finishedWorkouts, longestStreak int) domain.PetStage {
	stage := domain.PetStageEgg
	for s := domain.PetStageHatchling; s <= domain.PetStageChampion; s++ {
		if finishedWorkouts < t.StageWorkoutGates[s] {
			break
		}
		if s == domain.PetStageChampion && longestStreak < t.ChampionStreakGate {
			break
		}
		stage = s
	}
	return stage
}

// currentStreak counts consecutive training days (a day with >=1 finished
// workout), walking back from today and forgiving up to StreakGraceDays
// missed calendar days between trained days.
func currentStreak(t PetTuning, now time.Time, loc *time.Location, endsDesc []time.Time) int {
	if len(endsDesc) == 0 {
		return 0
	}

	// Distinct local training days, newest first.
	seen := map[int64]bool{}
	var days []time.Time
	for _, e := range endsDesc {
		d := dayStart(e.In(loc))
		key := d.Unix()
		if !seen[key] {
			seen[key] = true
			days = append(days, d)
		}
	}

	today := dayStart(now.In(loc))
	maxGap := t.StreakGraceDays + 1 // gap in calendar days between trained days

	if calDaysBetween(days[0], today) > maxGap {
		return 0
	}

	streak := 1
	for i := 1; i < len(days); i++ {
		if calDaysBetween(days[i], days[i-1]) > maxGap {
			break
		}
		streak++
	}
	return streak
}

// evaluateUnlocks returns the set of accessory unlock_codes the user
// currently qualifies for. The service is responsible for persisting any that
// aren't owned yet.
func evaluateUnlocks(t PetTuning, snap *domain.PetStatsSnapshot, longestStreak int, now time.Time, loc *time.Location) map[string]bool {
	ends := snap.FinishedWorkoutEndTimes
	workouts := len(ends)
	out := map[string]bool{}

	set := func(code string, ok bool) {
		if ok {
			out[code] = true
		}
	}

	set("workouts_1", workouts >= 1)
	set("workouts_10", workouts >= 10)
	set("workouts_25", workouts >= 25)
	set("workouts_50", workouts >= 50)
	set("workouts_100", workouts >= 100)
	set("workouts_250", workouts >= 250)
	set("workouts_500", workouts >= 500)

	set("streak_3", longestStreak >= 3)
	set("streak_7", longestStreak >= 7)
	set("streak_14", longestStreak >= 14)
	set("streak_30", longestStreak >= 30)
	set("streak_60", longestStreak >= 60)
	set("streak_100", longestStreak >= 100)
	set("streak_365", longestStreak >= 365)

	set("pr_1", snap.PersonalRecordCount >= 1)
	set("pr_10", snap.PersonalRecordCount >= 10)
	set("pr_25", snap.PersonalRecordCount >= 25)
	set("pr_100", snap.PersonalRecordCount >= 100)

	set("exercises_10", snap.DistinctExercisesLogged >= 10)
	set("muscles_5", snap.DistinctMuscleGroups >= 5)
	set("template_1", snap.TemplateCount >= 1)
	set("templates_5", snap.TemplateCount >= 5)
	set("bodyweight_1", snap.BodyMetricCount >= 1)

	set("early_bird", anyWorkout(ends, loc, func(local time.Time) bool { return local.Hour() < 7 }))
	set("weekend_warrior", weekendWarrior(ends, loc))
	set("weeks4_ontarget", consecutiveOnTargetWeeks(t, ends, now, loc) >= 4)

	return out
}

func anyWorkout(ends []time.Time, loc *time.Location, pred func(time.Time) bool) bool {
	for _, e := range ends {
		if pred(e.In(loc)) {
			return true
		}
	}
	return false
}

// weekendWarrior is true once the user has trained on a Saturday and the
// adjacent Sunday of the same weekend.
func weekendWarrior(ends []time.Time, loc *time.Location) bool {
	sundays := map[int64]bool{} // dayStart unix of Sundays trained
	saturdays := map[int64]bool{}
	for _, e := range ends {
		d := dayStart(e.In(loc))
		switch d.Weekday() {
		case time.Saturday:
			saturdays[d.Unix()] = true
		case time.Sunday:
			sundays[d.Unix()] = true
		}
	}
	for sat := range saturdays {
		if sundays[time.Unix(sat, 0).AddDate(0, 0, 1).Unix()] {
			return true
		}
	}
	return false
}

// consecutiveOnTargetWeeks counts how many of the most recent completed
// 7-day windows (ending at the last local midnight) had at least WeeklyTarget
// finished workouts, stopping at the first window that missed.
func consecutiveOnTargetWeeks(t PetTuning, ends []time.Time, now time.Time, loc *time.Location) int {
	windowEnd := dayStart(now.In(loc))
	count := 0
	for w := 0; w < 52; w++ {
		windowStart := windowEnd.AddDate(0, 0, -7)
		n := 0
		for _, e := range ends {
			le := e.In(loc)
			if !le.Before(windowStart) && le.Before(windowEnd) {
				n++
			}
		}
		if n >= t.WeeklyTarget {
			count++
			windowEnd = windowStart
			continue
		}
		break
	}
	return count
}

func dayStart(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, t.Location())
}

// calDaysBetween is the number of whole calendar days from a to b (both
// already day-start values in the same location). Assumes b >= a.
func calDaysBetween(a, b time.Time) int {
	return int(b.Sub(a).Hours()/24 + 0.5)
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
