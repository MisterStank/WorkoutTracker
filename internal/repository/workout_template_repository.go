package repository

import (
	"context"
	"errors"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type WorkoutTemplateRepository struct {
	db *pgxpool.Pool
}

func NewWorkoutTemplateRepository(db *pgxpool.Pool) *WorkoutTemplateRepository {
	return &WorkoutTemplateRepository{db: db}
}

func (r *WorkoutTemplateRepository) Create(ctx context.Context, t *domain.WorkoutTemplate) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`INSERT INTO workout_templates (id, user_id, name, created_at) VALUES ($1, $2, $3, $4)`,
		t.ID, t.UserID, t.Name, t.CreatedAt,
	); err != nil {
		return err
	}

	for _, ex := range t.Exercises {
		if _, err := tx.Exec(ctx,
			`INSERT INTO workout_template_exercises (id, template_id, exercise_id, position, target_sets, target_reps, superset_group)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			ex.ID, t.ID, ex.ExerciseID, ex.Position, ex.TargetSets, ex.TargetReps, ex.SupersetGroup,
		); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *WorkoutTemplateRepository) Update(ctx context.Context, t *domain.WorkoutTemplate) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx, `UPDATE workout_templates SET name = $2 WHERE id = $1`, t.ID, t.Name)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrTemplateNotFound
	}

	if _, err := tx.Exec(ctx, `DELETE FROM workout_template_exercises WHERE template_id = $1`, t.ID); err != nil {
		return err
	}
	for _, ex := range t.Exercises {
		if _, err := tx.Exec(ctx,
			`INSERT INTO workout_template_exercises (id, template_id, exercise_id, position, target_sets, target_reps, superset_group)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			ex.ID, t.ID, ex.ExerciseID, ex.Position, ex.TargetSets, ex.TargetReps, ex.SupersetGroup,
		); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *WorkoutTemplateRepository) ListForUser(ctx context.Context, userID uuid.UUID) ([]*domain.WorkoutTemplate, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, user_id, name, created_at FROM workout_templates WHERE user_id = $1 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var templates []*domain.WorkoutTemplate
	for rows.Next() {
		var t domain.WorkoutTemplate
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.CreatedAt); err != nil {
			return nil, err
		}
		templates = append(templates, &t)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	for _, t := range templates {
		exercises, err := r.exercisesForTemplate(ctx, t.ID)
		if err != nil {
			return nil, err
		}
		t.Exercises = exercises
	}
	return templates, nil
}

func (r *WorkoutTemplateRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.WorkoutTemplate, error) {
	var t domain.WorkoutTemplate
	err := r.db.QueryRow(ctx,
		`SELECT id, user_id, name, created_at FROM workout_templates WHERE id = $1`, id,
	).Scan(&t.ID, &t.UserID, &t.Name, &t.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrTemplateNotFound
	}
	if err != nil {
		return nil, err
	}

	exercises, err := r.exercisesForTemplate(ctx, t.ID)
	if err != nil {
		return nil, err
	}
	t.Exercises = exercises
	return &t, nil
}

func (r *WorkoutTemplateRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM workout_templates WHERE id = $1`, id)
	return err
}

func (r *WorkoutTemplateRepository) exercisesForTemplate(ctx context.Context, templateID uuid.UUID) ([]*domain.TemplateExercise, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, exercise_id, position, target_sets, target_reps, superset_group
		 FROM workout_template_exercises WHERE template_id = $1 ORDER BY position`,
		templateID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var exercises []*domain.TemplateExercise
	for rows.Next() {
		var e domain.TemplateExercise
		if err := rows.Scan(&e.ID, &e.ExerciseID, &e.Position, &e.TargetSets, &e.TargetReps, &e.SupersetGroup); err != nil {
			return nil, err
		}
		exercises = append(exercises, &e)
	}
	return exercises, rows.Err()
}
