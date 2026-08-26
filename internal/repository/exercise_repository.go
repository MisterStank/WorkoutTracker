package repository

import (
	"context"
	"errors"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ExerciseRepository struct {
	db *pgxpool.Pool
}

func NewExerciseRepository(db *pgxpool.Pool) *ExerciseRepository {
	return &ExerciseRepository{db: db}
}

func (r *ExerciseRepository) List(ctx context.Context, search string) ([]*domain.Exercise, error) {
	query := `SELECT id, name, category, muscle_groups, equipment, is_custom, created_at, instructions FROM exercises`
	args := []any{}
	if search != "" {
		query += ` WHERE name ILIKE $1`
		args = append(args, "%"+search+"%")
	}
	query += ` ORDER BY name`

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var exercises []*domain.Exercise
	for rows.Next() {
		var e domain.Exercise
		if err := rows.Scan(&e.ID, &e.Name, &e.Category, &e.MuscleGroups, &e.Equipment, &e.IsCustom, &e.CreatedAt, &e.Instructions); err != nil {
			return nil, err
		}
		exercises = append(exercises, &e)
	}
	return exercises, rows.Err()
}

// ListFiltered is the program generator's exercise picker. An empty
// equipment slice matches any equipment; excludeMuscleGroups skips any
// exercise whose muscle_groups overlaps it at all (uses the GIN index via
// the && operator); an empty category matches any category. Ordered by
// name for deterministic, testable selection.
func (r *ExerciseRepository) ListFiltered(ctx context.Context, equipment []string, excludeMuscleGroups []string, category string) ([]*domain.Exercise, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, name, category, muscle_groups, equipment, is_custom, created_at, instructions
		 FROM exercises
		 WHERE ($1::text[] = '{}' OR equipment = ANY($1))
		   AND NOT (muscle_groups && $2::text[])
		   AND ($3 = '' OR category = $3)
		 ORDER BY name`,
		equipment, excludeMuscleGroups, category,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var exercises []*domain.Exercise
	for rows.Next() {
		var e domain.Exercise
		if err := rows.Scan(&e.ID, &e.Name, &e.Category, &e.MuscleGroups, &e.Equipment, &e.IsCustom, &e.CreatedAt, &e.Instructions); err != nil {
			return nil, err
		}
		exercises = append(exercises, &e)
	}
	return exercises, rows.Err()
}

func (r *ExerciseRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Exercise, error) {
	var e domain.Exercise
	err := r.db.QueryRow(ctx,
		`SELECT id, name, category, muscle_groups, equipment, is_custom, created_at, instructions
		 FROM exercises WHERE id = $1`, id,
	).Scan(&e.ID, &e.Name, &e.Category, &e.MuscleGroups, &e.Equipment, &e.IsCustom, &e.CreatedAt, &e.Instructions)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrExerciseNotFound
	}
	if err != nil {
		return nil, err
	}
	return &e, nil
}
