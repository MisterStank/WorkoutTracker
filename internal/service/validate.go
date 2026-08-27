package service

import (
	"math"
	"regexp"
	"strings"

	"workouttracker/internal/domain"
)

// This file holds all user-input validation for the service layer. The
// backend previously trusted every value the GraphQL layer passed through,
// so negative weights, RPE 99, empty templates and malformed emails all
// reached the database. Each helper returns one of the domain.ErrInvalid*
// sentinels (which the API's error presenter forwards to clients verbatim).

const (
	maxReps        = 100
	maxWeightKg    = 1000.0
	minAssistedKg  = -500.0
	maxMetricValue = 1000.0
	maxDisplayName = 80
	maxNotesLen    = 2000
	minPasswordLen = 8
)

// emailPattern is deliberately permissive — it rejects obvious junk
// ("notanemail", "a@b", trailing spaces) without trying to be RFC 5322.
var emailPattern = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)

var validExerciseCategories = map[string]bool{
	"push": true, "pull": true, "legs": true, "arms": true, "core": true,
}

var validEquipment = map[string]bool{
	"barbell": true, "dumbbell": true, "bodyweight": true, "cable": true, "machine": true,
}

// validBodyMetricTypes mirrors the mobile client's MeasurementType list.
var validBodyMetricTypes = map[string]bool{
	"bodyweight_kg": true,
	"waist_cm":      true,
	"chest_cm":      true,
	"arm_cm":        true,
	"thigh_cm":      true,
	"hip_cm":        true,
}

// isBodyweight reports whether an exercise is performed against body weight,
// so its logged weight is treated as *added* load and may be zero or
// negative (assisted).
func isBodyweight(e *domain.Exercise) bool {
	return e != nil && e.Equipment == "bodyweight"
}

// ValidateSetInput checks reps/weight/RPE for a logged or edited set.
// allowNonPositiveWeight is true for bodyweight exercises, where the weight
// field means *added* load (0 = bodyweight, negative = assisted).
func ValidateSetInput(reps int, weightKg float64, rpe *float64, allowNonPositiveWeight bool) error {
	if reps < 1 || reps > maxReps {
		return domain.ErrInvalidSetValues
	}
	if math.IsNaN(weightKg) || math.IsInf(weightKg, 0) || weightKg > maxWeightKg {
		return domain.ErrInvalidSetValues
	}
	minWeight := 0.0
	if allowNonPositiveWeight {
		minWeight = minAssistedKg
	}
	if weightKg < minWeight {
		return domain.ErrInvalidSetValues
	}
	if rpe != nil {
		v := *rpe
		if math.IsNaN(v) || v < 1.0 || v > 10.0 || math.Mod(v*2, 1) != 0 {
			return domain.ErrInvalidRPE
		}
	}
	return nil
}

// ValidateEmail trims, lowercases and format-checks an email, returning the
// normalized form callers should persist and look up by.
func ValidateEmail(email string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(email))
	if !emailPattern.MatchString(normalized) || len(normalized) > 254 {
		return "", domain.ErrInvalidEmail
	}
	return normalized, nil
}

func ValidatePassword(password string) error {
	if len(password) < minPasswordLen {
		return domain.ErrWeakPassword
	}
	return nil
}

// ValidateDisplayName returns the trimmed name to persist.
func ValidateDisplayName(name string) (string, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" || len(trimmed) > maxDisplayName {
		return "", domain.ErrEmptyDisplayName
	}
	return trimmed, nil
}

func ValidateBodyMetric(metricType string, value float64) error {
	if !validBodyMetricTypes[metricType] {
		return domain.ErrInvalidMetricType
	}
	if math.IsNaN(value) || math.IsInf(value, 0) || value <= 0 || value > maxMetricValue {
		return domain.ErrInvalidMetricValue
	}
	return nil
}

// ValidateTemplateName returns the trimmed template name to persist.
func ValidateTemplateName(name string) (string, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return "", domain.ErrEmptyTemplateName
	}
	return trimmed, nil
}

func ValidateNotes(notes string) error {
	if len(notes) > maxNotesLen {
		return domain.ErrNotesTooLong
	}
	return nil
}

// ValidateExerciseInput checks a custom exercise's fields and returns the
// trimmed name to persist. category and equipment must be values the
// program generator and UI understand.
func ValidateExerciseInput(name, category, equipment string) (string, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" || len(trimmed) > 80 {
		return "", domain.ErrInvalidExercise
	}
	if !validExerciseCategories[category] || !validEquipment[equipment] {
		return "", domain.ErrInvalidExercise
	}
	return trimmed, nil
}

// normalizeStrings trims, lowercases, de-dupes and drops empties — used for
// muscle-group tags so "Chest", " chest " and "chest" collapse to one.
func normalizeStrings(in []string) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, s := range in {
		v := strings.ToLower(strings.TrimSpace(s))
		if v == "" || seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
	}
	return out
}
