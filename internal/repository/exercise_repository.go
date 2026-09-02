package repository

import (
	"context"
	"errors"

	"gymon/internal/domain"

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

const exerciseColumns = `id, name, category, muscle_groups, equipment, is_custom, created_by, created_at, instructions`

func scanExercise(row pgx.Row) (*domain.Exercise, error) {
	var e domain.Exercise
	if err := row.Scan(&e.ID, &e.Name, &e.Category, &e.MuscleGroups, &e.Equipment, &e.IsCustom, &e.CreatedBy, &e.CreatedAt, &e.Instructions); err != nil {
		return nil, err
	}
	return &e, nil
}

func collectExercises(rows pgx.Rows) ([]*domain.Exercise, error) {
	defer rows.Close()
	var exercises []*domain.Exercise
	for rows.Next() {
		e, err := scanExercise(rows)
		if err != nil {
			return nil, err
		}
		exercises = append(exercises, e)
	}
	return exercises, rows.Err()
}

// ownershipClause matches built-in exercises (created_by IS NULL) plus the
// caller's own custom ones. uuid.Nil is fine — it just matches nothing extra.
const ownershipClause = `(created_by IS NULL OR created_by = $1)`

func (r *ExerciseRepository) List(ctx context.Context, userID uuid.UUID, search string) ([]*domain.Exercise, error) {
	query := `SELECT ` + exerciseColumns + ` FROM exercises WHERE ` + ownershipClause
	args := []any{userID}
	if search != "" {
		query += ` AND name ILIKE $2`
		args = append(args, "%"+search+"%")
	}
	query += ` ORDER BY name`

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	return collectExercises(rows)
}

// ListFiltered is the program generator's exercise picker. An empty
// equipment slice matches any equipment; excludeMuscleGroups skips any
// exercise whose muscle_groups overlaps it at all (uses the GIN index via
// the && operator); an empty category matches any category. Ordered by
// name for deterministic, testable selection.
func (r *ExerciseRepository) ListFiltered(ctx context.Context, userID uuid.UUID, equipment []string, excludeMuscleGroups []string, category string) ([]*domain.Exercise, error) {
	rows, err := r.db.Query(ctx,
		`SELECT `+exerciseColumns+`
		 FROM exercises
		 WHERE `+ownershipClause+`
		   AND ($2::text[] = '{}' OR equipment = ANY($2))
		   AND NOT (muscle_groups && $3::text[])
		   AND ($4 = '' OR category = $4)
		 ORDER BY name`,
		userID, equipment, excludeMuscleGroups, category,
	)
	if err != nil {
		return nil, err
	}
	return collectExercises(rows)
}

func (r *ExerciseRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Exercise, error) {
	e, err := scanExercise(r.db.QueryRow(ctx,
		`SELECT `+exerciseColumns+` FROM exercises WHERE id = $1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrExerciseNotFound
	}
	if err != nil {
		return nil, err
	}
	return e, nil
}

func (r *ExerciseRepository) Create(ctx context.Context, e *domain.Exercise) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO exercises (id, name, category, muscle_groups, equipment, is_custom, created_by, created_at, instructions)
		 VALUES ($1, $2, $3, $4, $5, true, $6, $7, '')`,
		e.ID, e.Name, e.Category, e.MuscleGroups, e.Equipment, e.CreatedBy, e.CreatedAt,
	)
	if isUniqueViolation(err) {
		return domain.ErrExerciseNameTaken
	}
	return err
}

func (r *ExerciseRepository) Update(ctx context.Context, e *domain.Exercise) error {
	tag, err := r.db.Exec(ctx,
		`UPDATE exercises SET name = $2, category = $3, muscle_groups = $4, equipment = $5
		 WHERE id = $1`,
		e.ID, e.Name, e.Category, e.MuscleGroups, e.Equipment,
	)
	if isUniqueViolation(err) {
		return domain.ErrExerciseNameTaken
	}
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrExerciseNotFound
	}
	return nil
}

func (r *ExerciseRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM exercises WHERE id = $1`, id)
	return err
}

func (r *ExerciseRepository) CountReferences(ctx context.Context, exerciseID uuid.UUID) (int, error) {
	var count int
	err := r.db.QueryRow(ctx,
		`SELECT
		   (SELECT count(*) FROM workout_sets WHERE exercise_id = $1)
		 + (SELECT count(*) FROM workout_template_exercises WHERE exercise_id = $1)`,
		exerciseID,
	).Scan(&count)
	return count, err
}
