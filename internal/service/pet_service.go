package service

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"gymon/internal/domain"

	"github.com/google/uuid"
)

// PetService owns the virtual-companion feature — the app's headline
// motivation mechanic. It depends only on domain interfaces (a pet repo, an
// accessory repo, and a narrow read-only training-stats repo), never on
// WorkoutService, so the pet's game rules stay testable against in-memory
// fakes exactly like AuthService and WorkoutService.
//
// Mood, current streak and newly-unlocked accessories are computed on every
// read from the user's finished-workout history (see pet_rules.go). The only
// writes a read performs are forward-only: bumping the stored evolution
// stage, the longest-streak record, hatching the egg, and inserting
// ownership rows for freshly-earned accessories.
type PetService struct {
	pets   domain.PetRepository
	acc    domain.AccessoryRepository
	stats  domain.PetStatsRepository
	tuning PetTuning
}

func NewPetService(pets domain.PetRepository, acc domain.AccessoryRepository, stats domain.PetStatsRepository, tuning PetTuning) *PetService {
	if tuning.WeeklyTarget == 0 {
		tuning = DefaultPetTuning
	}
	return &PetService{pets: pets, acc: acc, stats: stats, tuning: tuning}
}

var (
	petSpecies = map[string]bool{"sprout": true, "ember": true, "pebble": true, "drift": true}
	petColors  = map[string]bool{"green": true, "red": true, "blue": true, "amber": true, "violet": true}
)

// PetView is the full read model for one pet: the stored row plus everything
// derived for this read.
type PetView struct {
	Pet           *domain.Pet
	Computed      PetComputed
	Accessories   []*domain.OwnedAccessory
	NewlyUnlocked []*domain.OwnedAccessory
}

// MyPet returns the caller's pet, or nil (not an error) if they haven't
// created one yet — the client shows onboarding in that case. Every call
// recomputes the derived state and persists any forward-only progress.
func (s *PetService) MyPet(ctx context.Context, userID uuid.UUID, tzOffsetMinutes int) (*PetView, error) {
	pet, err := s.pets.FindByUser(ctx, userID)
	if errors.Is(err, domain.ErrPetNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return s.hydrate(ctx, pet, tzOffsetMinutes)
}

// CreatePet runs the onboarding choice. Returns ErrPetAlreadyExists if the
// user already has one.
func (s *PetService) CreatePet(ctx context.Context, userID uuid.UUID, name, species, color string) (*PetView, error) {
	if _, err := s.pets.FindByUser(ctx, userID); err == nil {
		return nil, domain.ErrPetAlreadyExists
	} else if !errors.Is(err, domain.ErrPetNotFound) {
		return nil, err
	}

	name, err := validatePetName(name)
	if err != nil {
		return nil, err
	}
	species = strings.ToLower(strings.TrimSpace(species))
	color = strings.ToLower(strings.TrimSpace(color))
	if !petSpecies[species] {
		return nil, domain.ErrInvalidPetSpecies
	}
	if !petColors[color] {
		return nil, domain.ErrInvalidPetColor
	}

	now := time.Now()
	pet := &domain.Pet{
		ID:             uuid.New(),
		UserID:         userID,
		Name:           name,
		Species:        species,
		Color:          color,
		Stage:          domain.PetStageEgg,
		StageUpdatedAt: now,
		CreatedAt:      now,
	}
	if err := s.pets.Create(ctx, pet); err != nil {
		return nil, err
	}
	return s.hydrate(ctx, pet, 0)
}

func (s *PetService) RenamePet(ctx context.Context, userID uuid.UUID, name string) (*PetView, error) {
	pet, err := s.ownedPet(ctx, userID)
	if err != nil {
		return nil, err
	}
	name, err = validatePetName(name)
	if err != nil {
		return nil, err
	}
	pet.Name = name
	if err := s.pets.Update(ctx, pet); err != nil {
		return nil, err
	}
	return s.hydrate(ctx, pet, 0)
}

func (s *PetService) SetPetColor(ctx context.Context, userID uuid.UUID, color string) (*PetView, error) {
	pet, err := s.ownedPet(ctx, userID)
	if err != nil {
		return nil, err
	}
	color = strings.ToLower(strings.TrimSpace(color))
	if !petColors[color] {
		return nil, domain.ErrInvalidPetColor
	}
	pet.Color = color
	if err := s.pets.Update(ctx, pet); err != nil {
		return nil, err
	}
	return s.hydrate(ctx, pet, 0)
}

// EquipAccessory equips an unlocked accessory, unequipping any other item in
// the same slot. accessoryID is the catalog id.
func (s *PetService) EquipAccessory(ctx context.Context, userID, accessoryID uuid.UUID) (*PetView, error) {
	return s.setEquipped(ctx, userID, accessoryID, true)
}

func (s *PetService) UnequipAccessory(ctx context.Context, userID, accessoryID uuid.UUID) (*PetView, error) {
	return s.setEquipped(ctx, userID, accessoryID, false)
}

func (s *PetService) setEquipped(ctx context.Context, userID, accessoryID uuid.UUID, equipped bool) (*PetView, error) {
	pet, err := s.ownedPet(ctx, userID)
	if err != nil {
		return nil, err
	}
	owned, err := s.acc.ListOwned(ctx, pet.ID)
	if err != nil {
		return nil, err
	}
	found := false
	for _, o := range owned {
		if o.Accessory.ID == accessoryID {
			found = true
			break
		}
	}
	if !found {
		return nil, domain.ErrAccessoryNotUnlocked
	}
	if err := s.acc.SetEquipped(ctx, pet.ID, accessoryID, equipped); err != nil {
		return nil, err
	}
	return s.hydrate(ctx, pet, 0)
}

func (s *PetService) ownedPet(ctx context.Context, userID uuid.UUID) (*domain.Pet, error) {
	return s.pets.FindByUser(ctx, userID)
}

// hydrate computes the derived state, persists forward-only progress, grants
// any newly-earned accessories, and assembles the view.
func (s *PetService) hydrate(ctx context.Context, pet *domain.Pet, tzOffsetMinutes int) (*PetView, error) {
	snap, err := s.stats.GatherStats(ctx, pet.UserID)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	computed := ComputePet(s.tuning, pet, snap, now, tzOffsetMinutes)

	// Persist forward-only progress if anything advanced.
	dirty := false
	if int(computed.Stage) > int(pet.Stage) {
		pet.Stage = computed.Stage
		pet.StageUpdatedAt = now
		dirty = true
	}
	if computed.CurrentStreak > pet.LongestStreak {
		pet.LongestStreak = computed.CurrentStreak
		dirty = true
	}
	if pet.HatchedAt == nil && len(snap.FinishedWorkoutEndTimes) > 0 {
		hatched := now
		pet.HatchedAt = &hatched
		dirty = true
	}
	if dirty {
		if err := s.pets.Update(ctx, pet); err != nil {
			return nil, err
		}
	}

	catalog, err := s.acc.ListCatalog(ctx)
	if err != nil {
		return nil, err
	}
	owned, err := s.acc.ListOwned(ctx, pet.ID)
	if err != nil {
		return nil, err
	}
	ownedByCode := map[string]bool{}
	for _, o := range owned {
		ownedByCode[o.Accessory.Code] = true
	}

	var newly []*domain.OwnedAccessory
	for _, cat := range catalog {
		if !computed.UnlockedCodes[cat.UnlockCode] || ownedByCode[cat.Code] {
			continue
		}
		if err := s.acc.Unlock(ctx, pet.ID, cat.ID, cat.Slot, now); err != nil {
			return nil, err
		}
		oa := &domain.OwnedAccessory{Accessory: *cat, UnlockedAt: now}
		owned = append(owned, oa)
		newly = append(newly, oa)
	}

	return &PetView{Pet: pet, Computed: computed, Accessories: owned, NewlyUnlocked: newly}, nil
}

func validatePetName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if c := utf8.RuneCountInString(name); c < 1 || c > 30 {
		return "", domain.ErrInvalidPetName
	}
	return name, nil
}
