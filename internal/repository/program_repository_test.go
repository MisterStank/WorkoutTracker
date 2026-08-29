package repository_test

import (
	"context"
	"testing"
	"time"

	"workouttracker/internal/domain"
	"workouttracker/internal/repository"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func makeProgram(t *testing.T, pool *pgxpool.Pool, userID uuid.UUID, name string, dayLabels ...string) *domain.Program {
	t.Helper()
	tmplRepo := repository.NewWorkoutTemplateRepository(pool)
	progRepo := repository.NewProgramRepository(pool, tmplRepo)
	bench := anyExerciseID(t, pool, "Barbell Bench Press")

	p := &domain.Program{
		ID: uuid.New(), UserID: userID, Name: name, Goal: domain.GoalHypertrophy,
		DaysPerWeek: len(dayLabels), CreatedAt: time.Now(),
	}
	for i, label := range dayLabels {
		tmpl := makeTemplate(t, tmplRepo, userID, name+" - "+label, bench)
		p.Days = append(p.Days, &domain.ProgramDay{
			ID: uuid.New(), DayLabel: label, Position: i, TemplateID: tmpl.ID,
		})
	}
	require.NoError(t, progRepo.Create(context.Background(), p))
	return p
}

func TestProgramRepository_CreateFindWithHydratedDays(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	tmplRepo := repository.NewWorkoutTemplateRepository(pool)
	repo := repository.NewProgramRepository(pool, tmplRepo)
	ctx := context.Background()

	p := makeProgram(t, pool, user.ID, "PPL "+uuid.NewString()[:6], "Push", "Pull", "Legs")

	got, err := repo.FindByID(ctx, p.ID)
	require.NoError(t, err)
	require.Len(t, got.Days, 3)
	assert.Equal(t, "Push", got.Days[0].DayLabel)
	require.NotNil(t, got.Days[0].Template, "each day's template is hydrated")
	assert.Len(t, got.Days[0].Template.Exercises, 1)
}

func TestProgramRepository_SetActiveIsExclusivePerUser(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	tmplRepo := repository.NewWorkoutTemplateRepository(pool)
	repo := repository.NewProgramRepository(pool, tmplRepo)
	ctx := context.Background()

	a := makeProgram(t, pool, user.ID, "A "+uuid.NewString()[:6], "Full Body")
	b := makeProgram(t, pool, user.ID, "B "+uuid.NewString()[:6], "Full Body")

	require.NoError(t, repo.SetActive(ctx, user.ID, a.ID))
	active, err := repo.FindActiveForUser(ctx, user.ID)
	require.NoError(t, err)
	require.NotNil(t, active)
	assert.Equal(t, a.ID, active.ID)

	// switching activates b and deactivates a
	require.NoError(t, repo.SetActive(ctx, user.ID, b.ID))
	active, err = repo.FindActiveForUser(ctx, user.ID)
	require.NoError(t, err)
	assert.Equal(t, b.ID, active.ID)

	gotA, err := repo.FindByID(ctx, a.ID)
	require.NoError(t, err)
	assert.False(t, gotA.IsActive)
}

func TestProgramRepository_FindMissing(t *testing.T) {
	pool := requireDB(t)
	repo := repository.NewProgramRepository(pool, repository.NewWorkoutTemplateRepository(pool))

	_, err := repo.FindByID(context.Background(), uuid.New())
	assert.ErrorIs(t, err, domain.ErrProgramNotFound)

	// no active program is not an error, just a nil result
	user := makeUser(t, pool)
	active, err := repo.FindActiveForUser(context.Background(), user.ID)
	require.NoError(t, err)
	assert.Nil(t, active)
}

func TestProgramRepository_ListForUserScoped(t *testing.T) {
	pool := requireDB(t)
	user := makeUser(t, pool)
	stranger := makeUser(t, pool)
	repo := repository.NewProgramRepository(pool, repository.NewWorkoutTemplateRepository(pool))

	makeProgram(t, pool, user.ID, "Mine "+uuid.NewString()[:6], "Day 1")
	makeProgram(t, pool, stranger.ID, "Theirs "+uuid.NewString()[:6], "Day 1")

	list, err := repo.ListForUser(context.Background(), user.ID)
	require.NoError(t, err)
	require.Len(t, list, 1)
	assert.Equal(t, user.ID, list[0].UserID)
}
