package graphql

import (
	"context"
	"fmt"
	"strings"

	"gymon/internal/domain"
	appmiddleware "gymon/internal/middleware"
	"gymon/internal/service"

	"github.com/google/uuid"
)

// Pet resolvers and mappers live in their own file (not resolver.go) so a
// gqlgen regenerate — which rewrites resolver.go and strips free-standing
// helpers from it — leaves them untouched.

// Pet is the resolver for the pet query.
func (r *queryResolver) Pet(ctx context.Context, tzOffsetMinutes *int) (*Pet, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	offset := 0
	if tzOffsetMinutes != nil {
		offset = *tzOffsetMinutes
	}
	view, err := r.Pets.MyPet(ctx, userID, offset)
	if err != nil {
		return nil, err
	}
	if view == nil {
		return nil, nil
	}
	return toPetModel(view), nil
}

// CreatePet is the resolver for the createPet mutation.
func (r *mutationResolver) CreatePet(ctx context.Context, name string, species PetSpecies, color PetColor) (*Pet, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	view, err := r.Pets.CreatePet(ctx, userID, name, strings.ToLower(species.String()), strings.ToLower(color.String()))
	if err != nil {
		return nil, err
	}
	return toPetModel(view), nil
}

// RenamePet is the resolver for the renamePet mutation.
func (r *mutationResolver) RenamePet(ctx context.Context, name string) (*Pet, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	view, err := r.Pets.RenamePet(ctx, userID, name)
	if err != nil {
		return nil, err
	}
	return toPetModel(view), nil
}

// SetPetColor is the resolver for the setPetColor mutation.
func (r *mutationResolver) SetPetColor(ctx context.Context, color PetColor) (*Pet, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	view, err := r.Pets.SetPetColor(ctx, userID, strings.ToLower(color.String()))
	if err != nil {
		return nil, err
	}
	return toPetModel(view), nil
}

// EquipAccessory is the resolver for the equipAccessory mutation.
func (r *mutationResolver) EquipAccessory(ctx context.Context, accessoryID uuid.UUID) (*Pet, error) {
	return r.setAccessoryEquipped(ctx, accessoryID, true)
}

// UnequipAccessory is the resolver for the unequipAccessory mutation.
func (r *mutationResolver) UnequipAccessory(ctx context.Context, accessoryID uuid.UUID) (*Pet, error) {
	return r.setAccessoryEquipped(ctx, accessoryID, false)
}

func (r *mutationResolver) setAccessoryEquipped(ctx context.Context, accessoryID uuid.UUID, equipped bool) (*Pet, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	var view *service.PetView
	var err error
	if equipped {
		view, err = r.Pets.EquipAccessory(ctx, userID, accessoryID)
	} else {
		view, err = r.Pets.UnequipAccessory(ctx, userID, accessoryID)
	}
	if err != nil {
		return nil, err
	}
	return toPetModel(view), nil
}

var domainToGraphQLStage = map[domain.PetStage]PetStage{
	domain.PetStageEgg:       PetStageEgg,
	domain.PetStageHatchling: PetStageHatchling,
	domain.PetStageJuvenile:  PetStageJuvenile,
	domain.PetStageAdult:     PetStageAdult,
	domain.PetStageChampion:  PetStageChampion,
}

var stageLabels = map[domain.PetStage]string{
	domain.PetStageEgg:       "Egg",
	domain.PetStageHatchling: "Hatchling",
	domain.PetStageJuvenile:  "Juvenile",
	domain.PetStageAdult:     "Adult",
	domain.PetStageChampion:  "Champion",
}

var domainToGraphQLMood = map[domain.MoodState]MoodState{
	domain.MoodHappy:     MoodStateHappy,
	domain.MoodContent:   MoodStateContent,
	domain.MoodLow:       MoodStateLow,
	domain.MoodNeglected: MoodStateNeglected,
}

func toAccessoryModel(a domain.Accessory) *Accessory {
	return &Accessory{ID: a.ID, Code: a.Code, Name: a.Name, Slot: a.Slot, UnlockHint: a.UnlockHint}
}

func toPetAccessoryModels(owned []*domain.OwnedAccessory) []*PetAccessory {
	out := make([]*PetAccessory, 0, len(owned))
	for _, o := range owned {
		out = append(out, &PetAccessory{
			Accessory:  toAccessoryModel(o.Accessory),
			UnlockedAt: o.UnlockedAt,
			Equipped:   o.Equipped,
		})
	}
	return out
}

func toPetModel(v *service.PetView) *Pet {
	p := v.Pet
	stage := domainToGraphQLStage[p.Stage]
	mood := domainToGraphQLMood[v.Computed.MoodState]

	var equippedLayers []string
	for _, o := range v.Accessories {
		if o.Equipped {
			equippedLayers = append(equippedLayers, "acc/"+o.Accessory.Code)
		}
	}

	return &Pet{
		ID:                  p.ID,
		Name:                p.Name,
		Species:             PetSpecies(strings.ToUpper(p.Species)),
		Color:               PetColor(strings.ToUpper(p.Color)),
		Stage:               stage,
		StageLabel:          stageLabels[p.Stage],
		Mood:                v.Computed.Mood,
		MoodState:           mood,
		CurrentStreak:       v.Computed.CurrentStreak,
		LongestStreak:       p.LongestStreak,
		WorkoutsToNextStage: v.Computed.WorkoutsToNextStage,
		HatchedAt:           p.HatchedAt,
		Appearance: &PetAppearance{
			BodyAssetKey:       fmt.Sprintf("pet/%s/%s", p.Species, strings.ToLower(string(stage))),
			ExpressionAssetKey: "expr/" + strings.ToLower(string(mood)),
			Tint:               p.Color,
			Layers:             equippedLayers,
		},
		Accessories:   toPetAccessoryModels(v.Accessories),
		NewlyUnlocked: toPetAccessoryModels(v.NewlyUnlocked),
	}
}
