package domain

import (
	"context"
	"time"

	"github.com/google/uuid"
)

// PetStage is the pet's evolution stage. It only ever moves forward — a
// stretch of skipped workouts lowers the pet's mood, never its stage.
type PetStage int

const (
	PetStageEgg       PetStage = 0
	PetStageHatchling PetStage = 1
	PetStageJuvenile  PetStage = 2
	PetStageAdult     PetStage = 3
	PetStageChampion  PetStage = 4
)

// MoodState is the coarse bucket the derived 0..100 mood falls into, used to
// pick the pet's expression art and copy.
type MoodState string

const (
	MoodHappy     MoodState = "happy"
	MoodContent   MoodState = "content"
	MoodLow       MoodState = "low"
	MoodNeglected MoodState = "neglected"
)

// Pet is a user's single virtual companion. Mood and the current streak are
// deliberately absent: they are pure functions of the user's finished-workout
// history (see service.PetRules) and are computed on read, so there is no
// snapshot to keep decaying while the app is closed and nothing to reconcile
// after a workout is logged offline. Only Stage and LongestStreak — progress
// that must not evaporate on a bad week — are persisted.
type Pet struct {
	ID             uuid.UUID
	UserID         uuid.UUID
	Name           string
	Species        string
	Color          string
	Stage          PetStage
	StageUpdatedAt time.Time
	LongestStreak  int
	HatchedAt      *time.Time
	CreatedAt      time.Time
}

// Accessory is one catalog cosmetic. UnlockCode names the rule in
// service.PetRules that grants it.
type Accessory struct {
	ID         uuid.UUID
	Code       string
	Name       string
	Slot       string
	UnlockCode string
	UnlockHint string
	SortOrder  int
}

// OwnedAccessory is a catalog Accessory joined with one pet's ownership row.
type OwnedAccessory struct {
	Accessory  Accessory
	UnlockedAt time.Time
	Equipped   bool
}

// PetStatsSnapshot is everything the pet rules need about a user's training
// history, gathered in one shot so mood / streak / stage / unlock evaluation
// don't each hit the database. FinishedWorkoutEndTimes is every completed
// workout's ended_at, newest first.
type PetStatsSnapshot struct {
	FinishedWorkoutEndTimes []time.Time
	PersonalRecordCount     int
	DistinctExercisesLogged int
	DistinctMuscleGroups    int
	TemplateCount           int
	BodyMetricCount         int
}

type PetRepository interface {
	// FindByUser returns ErrPetNotFound if the user has not created one yet.
	FindByUser(ctx context.Context, userID uuid.UUID) (*Pet, error)
	Create(ctx context.Context, p *Pet) error
	// Update persists the mutable columns: name, color, stage,
	// stage_updated_at, longest_streak, hatched_at.
	Update(ctx context.Context, p *Pet) error
}

type AccessoryRepository interface {
	// ListCatalog returns every accessory, ordered by sort_order.
	ListCatalog(ctx context.Context) ([]*Accessory, error)
	// ListOwned returns the accessories this pet has unlocked.
	ListOwned(ctx context.Context, petID uuid.UUID) ([]*OwnedAccessory, error)
	// Unlock records that petID has earned accessoryID. Idempotent: a second
	// call for the same pair is a no-op.
	Unlock(ctx context.Context, petID, accessoryID uuid.UUID, slot string, at time.Time) error
	// SetEquipped equips or unequips one owned accessory. Equipping clears any
	// other equipped accessory in the same slot, in one transaction.
	SetEquipped(ctx context.Context, petID, accessoryID uuid.UUID, equipped bool) error
}

// PetStatsRepository gathers the read-only training-history facts the pet
// rules run on. It is a separate, narrow interface (not a dependency on
// WorkoutService) so PetService stays decoupled from the rest of the app.
type PetStatsRepository interface {
	GatherStats(ctx context.Context, userID uuid.UUID) (*PetStatsSnapshot, error)
}
