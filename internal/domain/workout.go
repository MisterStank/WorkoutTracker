package domain

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type WorkoutStatus string

const (
	WorkoutInProgress WorkoutStatus = "in_progress"
	WorkoutCompleted  WorkoutStatus = "completed"
)

// Record types tracked per exercise. MaxWeight rewards heavier lifts,
// MaxVolume (weight * reps) rewards a strong single set even at lighter
// weight — both are computed on every set so neither needs a backfill job.
const (
	RecordTypeMaxWeight = "max_weight"
	RecordTypeMaxVolume = "max_volume"
)

type Exercise struct {
	ID           uuid.UUID
	Name         string
	Category     string
	MuscleGroups []string
	Equipment    string
	IsCustom     bool
	CreatedAt    time.Time
}

type Workout struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	StartedAt time.Time
	EndedAt   *time.Time
	Notes     string
	Status    WorkoutStatus
}

type WorkoutSet struct {
	ID          uuid.UUID
	WorkoutID   uuid.UUID
	ExerciseID  uuid.UUID
	SetNumber   int
	Reps        int
	WeightKg    float64
	RPE         *float64
	PerformedAt time.Time
}

type PersonalRecord struct {
	ID           uuid.UUID
	UserID       uuid.UUID
	ExerciseID   uuid.UUID
	RecordType   string
	Value        float64
	AchievedAt   time.Time
	WorkoutSetID uuid.UUID
}

// LoggedSet is the result of logging a set: the persisted set plus any PRs
// it broke, computed in the same transaction as the insert so a concurrent
// write can't read a stale personal-best.
type LoggedSet struct {
	Set        *WorkoutSet
	NewRecords []*PersonalRecord
}

type ExerciseRepository interface {
	List(ctx context.Context, search string) ([]*Exercise, error)
	FindByID(ctx context.Context, id uuid.UUID) (*Exercise, error)
}

type WorkoutRepository interface {
	Create(ctx context.Context, w *Workout) error
	FindByID(ctx context.Context, id uuid.UUID) (*Workout, error)
	FindActiveForUser(ctx context.Context, userID uuid.UUID) (*Workout, error)
	Finish(ctx context.Context, id uuid.UUID, endedAt time.Time, notes string) error
	// ListForUser uses keyset (cursor) pagination on (started_at, id) rather
	// than OFFSET, so page N stays cheap regardless of how far in the user
	// has paged.
	ListForUser(ctx context.Context, userID uuid.UUID, limit int, afterStartedAt *time.Time, afterID *uuid.UUID) ([]*Workout, error)
}

type WorkoutSetRepository interface {
	ListForWorkout(ctx context.Context, workoutID uuid.UUID) ([]*WorkoutSet, error)
	// LogSet inserts a set and atomically upserts any personal records it
	// breaks, in the same transaction as the insert.
	LogSet(ctx context.Context, userID uuid.UUID, set *WorkoutSet) (*LoggedSet, error)
}

type PersonalRecordRepository interface {
	ListForUser(ctx context.Context, userID uuid.UUID) ([]*PersonalRecord, error)
}
