package service

import (
	"strings"

	"workouttracker/internal/domain"
)

// Movement patterns the program generator balances a training day around.
// Derived from an exercise's category + muscle groups + name rather than a
// stored column, so no migration or catalog re-tag is needed.
const (
	patternSquat          = "squat"           // knee-dominant lower: squats, lunges, leg press
	patternHinge          = "hinge"           // hip-dominant lower: deadlifts, RDLs, hip thrusts, leg curls
	patternHorizontalPush = "horizontal_push" // bench, push-ups, chest press/fly
	patternVerticalPush   = "vertical_push"   // overhead press, pike push-up, lateral raise
	patternHorizontalPull = "horizontal_pull" // rows, face pulls
	patternVerticalPull   = "vertical_pull"   // pull-ups, chin-ups, lat pulldown
	patternBiceps         = "biceps"
	patternTriceps        = "triceps"
	patternCore           = "core"
)

func hasMuscle(e *domain.Exercise, m string) bool {
	for _, g := range e.MuscleGroups {
		if g == m {
			return true
		}
	}
	return false
}

func nameContainsAny(name string, subs ...string) bool {
	lower := strings.ToLower(name)
	for _, s := range subs {
		if strings.Contains(lower, s) {
			return true
		}
	}
	return false
}

// movementPattern classifies one exercise. Returns "" for exercises that
// don't map cleanly (they simply won't be picked for a pattern slot, but
// the generator's category fallback still covers them).
func movementPattern(e *domain.Exercise) string {
	switch e.Category {
	case "legs":
		// Hip-dominant if it's a hamstring/glute exercise without quads,
		// or its name says so.
		if nameContainsAny(e.Name, "deadlift", "romanian", "hip thrust", "glute bridge", "leg curl", "good morning") {
			return patternHinge
		}
		if (hasMuscle(e, "hamstrings") || hasMuscle(e, "glutes")) && !hasMuscle(e, "quads") {
			return patternHinge
		}
		return patternSquat
	case "push":
		if hasMuscle(e, "shoulders") && !hasMuscle(e, "chest") {
			return patternVerticalPush
		}
		if nameContainsAny(e.Name, "overhead press", "shoulder press", "pike", "lateral raise") {
			return patternVerticalPush
		}
		return patternHorizontalPush
	case "pull":
		if nameContainsAny(e.Name, "deadlift") {
			return patternHinge
		}
		if nameContainsAny(e.Name, "pull-up", "pullup", "chin-up", "chinup", "pulldown", "pull down") {
			return patternVerticalPull
		}
		return patternHorizontalPull
	case "arms":
		if hasMuscle(e, "biceps") {
			return patternBiceps
		}
		if hasMuscle(e, "triceps") {
			return patternTriceps
		}
		return ""
	case "core":
		return patternCore
	}
	return ""
}

// isCompoundPattern reports whether a pattern gets the compound set/rep
// scheme (more sets, lower reps for strength) vs the accessory scheme.
func isCompoundPattern(pattern string) bool {
	switch pattern {
	case patternSquat, patternHinge, patternHorizontalPush, patternVerticalPush, patternHorizontalPull, patternVerticalPull:
		return true
	default:
		return false
	}
}
