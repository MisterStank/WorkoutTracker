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

// ProgramDay is one day of a Program, pointing at an ordinary
// WorkoutTemplate — a program doesn't duplicate the template concept, it
// just names and orders a set of them. Template is populated by the
// repository for convenience; nil if not hydrated.
type ProgramDay struct {
	ID         uuid.UUID
	ProgramID  uuid.UUID
	DayLabel   string
	Position   int
	TemplateID uuid.UUID
	Template   *WorkoutTemplate
}

// Program is a generated or hand-built multi-day split. Notes carries any
// skipped-muscle-group explanations from generation (e.g. "no eligible
// chest exercises for your equipment") rather than failing outright — see
// ProgramService. Hand-built programs (assembled from existing templates
// rather than generated) default Goal to GoalGeneralFitness since there's
// no questionnaire to derive one from.
type Program struct {
	ID          uuid.UUID
	UserID      uuid.UUID
	Name        string
	Goal        Goal
	DaysPerWeek int
	Notes       string
	CreatedAt   time.Time
	Days        []*ProgramDay
	// IsActive marks the one program (at most) the user is currently
	// following — NextWorkout is derived from this program, not just
	// whichever was created most recently. See ProgramService.SetActiveProgram.
	IsActive bool
}

// NextWorkout is "what should I train next" for a user's most recently
// created program: Day is the ProgramDay after whichever one was most
// recently finished (wrapping around), or the first day if none of this
// program's days have been done yet. Derived fresh each time from workout
// history rather than a stored counter, so it can't desync if a workout
// gets edited or deleted.
type NextWorkout struct {
	Program *Program
	Day     *ProgramDay
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
	// ListFiltered is the program generator's exercise picker: equipment
	// (empty = any), excludeMuscleGroups (skips any exercise touching one
	// of these), and category (empty = any). Ordered by name so the
	// generator's "pick the first N" selection is deterministic.
	ListFiltered(ctx context.Context, equipment []string, excludeMuscleGroups []string, category string) ([]*Exercise, error)
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
	// Delete removes a workout and, via ON DELETE CASCADE, its sets and any
	// personal_records rows keyed to those sets. Callers are responsible
	// for recomputing rollups/records afterward — the cascade only cleans
	// up rows, it doesn't know what should replace a lost personal best.
	Delete(ctx context.Context, id uuid.UUID) error
	// FindMostRecentFinishedByTemplateIDs powers NextWorkout: which of a
	// program's day-templates did the user most recently complete? Returns
	// nil (not an error) if none of the given templates has ever been
	// finished by this user.
	FindMostRecentFinishedByTemplateIDs(ctx context.Context, userID uuid.UUID, templateIDs []uuid.UUID) (*Workout, error)
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

type ProgramRepository interface {
	Create(ctx context.Context, p *Program) error
	ListForUser(ctx context.Context, userID uuid.UUID) ([]*Program, error)
	FindByID(ctx context.Context, id uuid.UUID) (*Program, error)
	Delete(ctx context.Context, id uuid.UUID) error
	// SetActive marks programID as the sole active program for userID,
	// deactivating any previously-active program for that same user in the
	// same transaction.
	SetActive(ctx context.Context, userID, programID uuid.UUID) error
	// FindActiveForUser returns nil, nil (not an error) if the user has no
	// active program — an expected state (never generated/built one yet, or
	// explicitly has none selected), not a failure.
	FindActiveForUser(ctx context.Context, userID uuid.UUID) (*Program, error)
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
