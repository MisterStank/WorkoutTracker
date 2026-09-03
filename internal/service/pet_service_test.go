package service_test

import (
	"context"
	"testing"
	"time"

	"gymon/internal/domain"
	"gymon/internal/service"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- in-memory fakes -------------------------------------------------------

type fakePetRepo struct {
	byUser map[uuid.UUID]*domain.Pet
}

func newFakePetRepo() *fakePetRepo { return &fakePetRepo{byUser: map[uuid.UUID]*domain.Pet{}} }

func (f *fakePetRepo) FindByUser(_ context.Context, userID uuid.UUID) (*domain.Pet, error) {
	p, ok := f.byUser[userID]
	if !ok {
		return nil, domain.ErrPetNotFound
	}
	cp := *p
	return &cp, nil
}
func (f *fakePetRepo) Create(_ context.Context, p *domain.Pet) error {
	cp := *p
	f.byUser[p.UserID] = &cp
	return nil
}
func (f *fakePetRepo) Update(_ context.Context, p *domain.Pet) error {
	cp := *p
	f.byUser[p.UserID] = &cp
	return nil
}

type fakeAccessoryRepo struct {
	catalog []*domain.Accessory
	owned   map[uuid.UUID]map[uuid.UUID]*domain.OwnedAccessory // petID -> accID -> row
}

func newFakeAccessoryRepo(catalog []*domain.Accessory) *fakeAccessoryRepo {
	return &fakeAccessoryRepo{catalog: catalog, owned: map[uuid.UUID]map[uuid.UUID]*domain.OwnedAccessory{}}
}

func (f *fakeAccessoryRepo) ListCatalog(context.Context) ([]*domain.Accessory, error) {
	return f.catalog, nil
}
func (f *fakeAccessoryRepo) ListOwned(_ context.Context, petID uuid.UUID) ([]*domain.OwnedAccessory, error) {
	var out []*domain.OwnedAccessory
	for _, o := range f.owned[petID] {
		cp := *o
		out = append(out, &cp)
	}
	return out, nil
}
func (f *fakeAccessoryRepo) Unlock(_ context.Context, petID, accessoryID uuid.UUID, slot string, at time.Time) error {
	if f.owned[petID] == nil {
		f.owned[petID] = map[uuid.UUID]*domain.OwnedAccessory{}
	}
	if _, exists := f.owned[petID][accessoryID]; exists {
		return nil
	}
	var acc domain.Accessory
	for _, c := range f.catalog {
		if c.ID == accessoryID {
			acc = *c
		}
	}
	f.owned[petID][accessoryID] = &domain.OwnedAccessory{Accessory: acc, UnlockedAt: at}
	return nil
}
func (f *fakeAccessoryRepo) SetEquipped(_ context.Context, petID, accessoryID uuid.UUID, equipped bool) error {
	target := f.owned[petID][accessoryID]
	if target == nil {
		return domain.ErrAccessoryNotUnlocked
	}
	if equipped {
		for _, o := range f.owned[petID] {
			if o.Accessory.Slot == target.Accessory.Slot {
				o.Equipped = false
			}
		}
	}
	target.Equipped = equipped
	return nil
}

type fakePetStatsRepo struct{ snap *domain.PetStatsSnapshot }

func (f *fakePetStatsRepo) GatherStats(context.Context, uuid.UUID) (*domain.PetStatsSnapshot, error) {
	return f.snap, nil
}

func testCatalog() []*domain.Accessory {
	return []*domain.Accessory{
		{ID: uuid.New(), Code: "starter_band", Name: "Sweatband", Slot: "head", UnlockCode: "workouts_1", SortOrder: 10},
		{ID: uuid.New(), Code: "streak_cap_7", Name: "Hat", Slot: "head", UnlockCode: "streak_7", SortOrder: 20},
		{ID: uuid.New(), Code: "collar_bronze", Name: "Bronze Collar", Slot: "collar", UnlockCode: "workouts_10", SortOrder: 30},
	}
}

func newTestPetService(snap *domain.PetStatsSnapshot, cat []*domain.Accessory) (*service.PetService, *fakePetRepo, *fakeAccessoryRepo) {
	pets := newFakePetRepo()
	acc := newFakeAccessoryRepo(cat)
	return service.NewPetService(pets, acc, &fakePetStatsRepo{snap: snap}, service.PetTuning{}), pets, acc
}

// --- pure rule tests -----------------------------------------------------

func daysAgo(n int) time.Time { return time.Now().AddDate(0, 0, -n) }

func TestComputeMood_RecentTrainingIsHappy(t *testing.T) {
	snap := &domain.PetStatsSnapshot{FinishedWorkoutEndTimes: []time.Time{daysAgo(0), daysAgo(2), daysAgo(4)}}
	c := service.ComputePet(service.DefaultPetTuning, &domain.Pet{}, snap, time.Now(), 0)
	assert.GreaterOrEqual(t, c.Mood, 75)
	assert.Equal(t, domain.MoodHappy, c.MoodState)
}

func TestComputeMood_LongAbsenceFloorsAtZero(t *testing.T) {
	snap := &domain.PetStatsSnapshot{FinishedWorkoutEndTimes: []time.Time{daysAgo(40)}}
	c := service.ComputePet(service.DefaultPetTuning, &domain.Pet{}, snap, time.Now(), 0)
	assert.Equal(t, 0, c.Mood)
	assert.Equal(t, domain.MoodNeglected, c.MoodState)
}

func TestComputeStage_MonotonicAndStreakGated(t *testing.T) {
	tn := service.DefaultPetTuning
	// 60 workouts but never a 14-day streak -> capped at Adult, not Champion.
	ends := make([]time.Time, 60)
	for i := range ends {
		ends[i] = daysAgo(i * 3)
	}
	c := service.ComputePet(tn, &domain.Pet{LongestStreak: 5}, &domain.PetStatsSnapshot{FinishedWorkoutEndTimes: ends[:60]}, time.Now(), 0)
	assert.Equal(t, domain.PetStageAdult, c.Stage)

	// 120 workouts + a 14-day streak on record -> Champion.
	ends2 := make([]time.Time, 120)
	for i := range ends2 {
		ends2[i] = daysAgo(i)
	}
	c2 := service.ComputePet(tn, &domain.Pet{LongestStreak: 20}, &domain.PetStatsSnapshot{FinishedWorkoutEndTimes: ends2}, time.Now(), 0)
	assert.Equal(t, domain.PetStageChampion, c2.Stage)
}

func TestCurrentStreak_ForgivesOneMissedDay(t *testing.T) {
	// trained today, yesterday, then skipped one day, then two more days.
	snap := &domain.PetStatsSnapshot{FinishedWorkoutEndTimes: []time.Time{
		daysAgo(0), daysAgo(1), daysAgo(3), daysAgo(4),
	}}
	c := service.ComputePet(service.DefaultPetTuning, &domain.Pet{}, snap, time.Now(), 0)
	assert.Equal(t, 4, c.CurrentStreak)
}

func TestCurrentStreak_BreaksAfterTwoMissedDays(t *testing.T) {
	snap := &domain.PetStatsSnapshot{FinishedWorkoutEndTimes: []time.Time{daysAgo(0), daysAgo(3)}}
	c := service.ComputePet(service.DefaultPetTuning, &domain.Pet{}, snap, time.Now(), 0)
	assert.Equal(t, 1, c.CurrentStreak)
}

// --- service tests -----------------------------------------------------

func TestMyPet_NilWhenNoneCreated(t *testing.T) {
	svc, _, _ := newTestPetService(&domain.PetStatsSnapshot{}, testCatalog())
	view, err := svc.MyPet(context.Background(), uuid.New(), 0)
	require.NoError(t, err)
	assert.Nil(t, view)
}

func TestCreatePet_ValidatesInput(t *testing.T) {
	svc, _, _ := newTestPetService(&domain.PetStatsSnapshot{}, testCatalog())
	ctx := context.Background()

	_, err := svc.CreatePet(ctx, uuid.New(), "  ", "sprout", "green")
	assert.ErrorIs(t, err, domain.ErrInvalidPetName)

	_, err = svc.CreatePet(ctx, uuid.New(), "Rex", "dragon", "green")
	assert.ErrorIs(t, err, domain.ErrInvalidPetSpecies)

	_, err = svc.CreatePet(ctx, uuid.New(), "Rex", "sprout", "chartreuse")
	assert.ErrorIs(t, err, domain.ErrInvalidPetColor)
}

func TestCreatePet_RejectsSecondPet(t *testing.T) {
	svc, _, _ := newTestPetService(&domain.PetStatsSnapshot{}, testCatalog())
	ctx := context.Background()
	uid := uuid.New()
	_, err := svc.CreatePet(ctx, uid, "Rex", "sprout", "green")
	require.NoError(t, err)
	_, err = svc.CreatePet(ctx, uid, "Max", "ember", "red")
	assert.ErrorIs(t, err, domain.ErrPetAlreadyExists)
}

func TestMyPet_PersistsStageAndGrantsAccessories(t *testing.T) {
	ends := make([]time.Time, 12)
	for i := range ends {
		ends[i] = daysAgo(i)
	}
	snap := &domain.PetStatsSnapshot{FinishedWorkoutEndTimes: ends}
	svc, pets, _ := newTestPetService(snap, testCatalog())
	ctx := context.Background()
	uid := uuid.New()

	_, err := svc.CreatePet(ctx, uid, "Rex", "sprout", "green")
	require.NoError(t, err)

	view, err := svc.MyPet(ctx, uid, 0)
	require.NoError(t, err)

	// 12 workouts -> at least Hatchling, and the row is persisted.
	assert.GreaterOrEqual(t, int(view.Pet.Stage), int(domain.PetStageHatchling))
	assert.Equal(t, view.Pet.Stage, pets.byUser[uid].Stage)
	assert.NotNil(t, pets.byUser[uid].HatchedAt)

	// workouts_1 and workouts_10 unlocked; streak_7 depends on the run.
	codes := map[string]bool{}
	for _, a := range view.Accessories {
		codes[a.Accessory.Code] = true
	}
	assert.True(t, codes["starter_band"])
	assert.True(t, codes["collar_bronze"])

	// Second read: nothing new to unlock.
	view2, err := svc.MyPet(ctx, uid, 0)
	require.NoError(t, err)
	assert.Empty(t, view2.NewlyUnlocked)
}

func TestEquipAccessory_OnePerSlot(t *testing.T) {
	ends := make([]time.Time, 12)
	for i := range ends {
		ends[i] = daysAgo(i)
	}
	svc, _, acc := newTestPetService(&domain.PetStatsSnapshot{FinishedWorkoutEndTimes: ends}, testCatalog())
	ctx := context.Background()
	uid := uuid.New()
	_, err := svc.CreatePet(ctx, uid, "Rex", "sprout", "green")
	require.NoError(t, err)
	view, err := svc.MyPet(ctx, uid, 0)
	require.NoError(t, err)

	var head1 uuid.UUID
	for _, a := range view.Accessories {
		if a.Accessory.Slot == "head" {
			head1 = a.Accessory.ID
		}
	}
	require.NotEqual(t, uuid.Nil, head1)

	_, err = svc.EquipAccessory(ctx, uid, head1)
	require.NoError(t, err)

	equipped := 0
	for _, o := range acc.owned {
		for _, row := range o {
			if row.Equipped {
				equipped++
			}
		}
	}
	assert.Equal(t, 1, equipped)
}

func TestEquipAccessory_RejectsLockedAccessory(t *testing.T) {
	svc, _, _ := newTestPetService(&domain.PetStatsSnapshot{}, testCatalog())
	ctx := context.Background()
	uid := uuid.New()
	_, err := svc.CreatePet(ctx, uid, "Rex", "sprout", "green")
	require.NoError(t, err)

	_, err = svc.EquipAccessory(ctx, uid, uuid.New())
	assert.ErrorIs(t, err, domain.ErrAccessoryNotUnlocked)
}
