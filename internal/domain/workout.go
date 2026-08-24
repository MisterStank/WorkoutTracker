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
// weight, Estimated1RM (Epley formula) estimates a true one-rep max from
// any rep range — all three are computed on every working set so none
// needs a backfill job.
const (
	RecordTypeMaxWeight    = "max_weight"
	RecordTypeMaxVolume    = "max_volume"
	RecordTypeEstimated1RM = "estimated_1rm"
)

type SetType string

const (
	SetTypeNormal  SetType = "normal"
	SetTypeWarmup  SetType = "warmup"
	SetTypeDropset SetType = "dropset"
	SetTypeFailure SetType = "failure"
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
	ID         uuid.UUID
	UserID     uuid.UUID
	StartedAt  time.Time
	EndedAt    *time.Time
	Notes      string
	Status     WorkoutStatus
	TemplateID *uuid.UUID
	// ShareCode lets someone else watch this workout live (read-only) via
	// sharedWorkout/sharedWorkoutProgressUpdated without a friends/follow
	// system. Only set while the workout is in progress.
	ShareCode *string
}

// TemplateExercise is one planned exercise within a WorkoutTemplate, in
// display order. Exercises sharing a non-nil SupersetGroup are planned as
// one superset (alternated back-to-back with shared rest).
type TemplateExercise struct {
	ID            uuid.UUID
	ExerciseID    uuid.UUID
	Position      int
	TargetSets    int
	TargetReps    *int
	SupersetGroup *int
}

type WorkoutTemplate struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	Name      string
	CreatedAt time.Time
	Exercises []*TemplateExercise
}

type WorkoutSet struct {
	ID          uuid.UUID
	WorkoutID   uuid.UUID
	ExerciseID  uuid.UUID
	SetNumber   int
	Reps        int
	WeightKg    float64
	RPE         *float64
	SetType     SetType
	SupersetID  *uuid.UUID
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
	// Create returns ErrShareCodeTaken if w.ShareCode collides with another
	// currently-in-progress workout's code — callers should regenerate and
	// retry rather than treating it as fatal.
	Create(ctx context.Context, w *Workout) error
	FindByID(ctx context.Context, id uuid.UUID) (*Workout, error)
	FindActiveForUser(ctx context.Context, userID uuid.UUID) (*Workout, error)
	// FindByShareCode only ever returns an in-progress workout — a finished
	// workout's code is no longer resolvable, even if reused by a new one.
	FindByShareCode(ctx context.Context, code string) (*Workout, error)
	Finish(ctx context.Context, id uuid.UUID, endedAt time.Time, notes string) error
	// ListForUser uses keyset (cursor) pagination on (started_at, id) rather
	// than OFFSET, so page N stays cheap regardless of how far in the user
	// has paged.
	ListForUser(ctx context.Context, userID uuid.UUID, limit int, afterStartedAt *time.Time, afterID *uuid.UUID) ([]*Workout, error)
	// Delete removes a workout and, via ON DELETE CASCADE, its sets and any
	// personal_records rows keyed to those sets. Callers are responsible
	// for recomputing rollups/records afterward — the cascade only cleans
	// up rows, it doesn't know what should replace a lost personal best.
	Delete(ctx context.Context, id uuid.UUID) error
}

type WorkoutTemplateRepository interface {
	Create(ctx context.Context, t *WorkoutTemplate) error
	ListForUser(ctx context.Context, userID uuid.UUID) ([]*WorkoutTemplate, error)
	FindByID(ctx context.Context, id uuid.UUID) (*WorkoutTemplate, error)
	Delete(ctx context.Context, id uuid.UUID) error
}

type WorkoutSetRepository interface {
	ListForWorkout(ctx context.Context, workoutID uuid.UUID) ([]*WorkoutSet, error)
	// LogSet inserts a set and, unless it's a warm-up set, atomically upserts
	// any personal records/rollup it breaks, in the same transaction as the
	// insert. Warm-up sets are excluded so they don't skew PRs or volume;
	// drop sets and failure sets are still real working effort and count
	// normally.
	LogSet(ctx context.Context, userID uuid.UUID, set *WorkoutSet) (*LoggedSet, error)
	// LastForExercise returns the most recent set logged for this exercise
	// (any workout), used to pre-fill the log-set form with the weight/reps
	// the user used last time. Returns ErrWorkoutSetNotFound if never logged.
	LastForExercise(ctx context.Context, userID, exerciseID uuid.UUID) (*WorkoutSet, error)
	// FindByID returns ErrWorkoutSetNotFound if no such set exists — used
	// by edit/delete to load a set before checking ownership via its
	// parent workout.
	FindByID(ctx context.Context, id uuid.UUID) (*WorkoutSet, error)
	// Update overwrites reps/weightKg/rpe/setType in place, leaving
	// id/workoutId/exerciseId/setNumber/supersetId/performedAt untouched.
	Update(ctx context.Context, set *WorkoutSet) error
	Delete(ctx context.Context, id uuid.UUID) error
}

type PersonalRecordRepository interface {
	ListForUser(ctx context.Context, userID uuid.UUID) ([]*PersonalRecord, error)
	// Recompute rebuilds all three record types for one user+exercise from
	// the current workout_sets from scratch (not an incremental "beat the
	// existing value" check like LogSet's upsert) — the only correct way
	// to recover the right personal best after the record-setting set
	// itself was edited or deleted. Removes the row for any record type no
	// longer held by any set.
	Recompute(ctx context.Context, userID, exerciseID uuid.UUID) error
}
