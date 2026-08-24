package domain

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type Goal string

const (
	GoalStrength       Goal = "strength"
	GoalHypertrophy    Goal = "hypertrophy"
	GoalFatLoss        Goal = "fat_loss"
	GoalGeneralFitness Goal = "general_fitness"
)

type ExperienceLevel string

const (
	ExperienceBeginner     ExperienceLevel = "beginner"
	ExperienceIntermediate ExperienceLevel = "intermediate"
	ExperienceAdvanced     ExperienceLevel = "advanced"
)

// UserFitnessProfile is the saved input a program is generated from —
// overwritten in place on save, not versioned, since regenerating a
// program always means "using whatever I've told the app about myself
// most recently."
type UserFitnessProfile struct {
	UserID            uuid.UUID
	Goal              Goal
	ExperienceLevel   ExperienceLevel
	DaysPerWeek       int
	EquipmentAccess   []string
	AvoidMuscleGroups []string
	UpdatedAt         time.Time
}

type UserFitnessProfileRepository interface {
	// Get returns ErrFitnessProfileNotFound if the user has never saved one.
	Get(ctx context.Context, userID uuid.UUID) (*UserFitnessProfile, error)
	Upsert(ctx context.Context, p *UserFitnessProfile) error
}
