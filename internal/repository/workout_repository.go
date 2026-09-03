package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"gymon/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type WorkoutRepository struct {
	db *pgxpool.Pool
}

func NewWorkoutRepository(db *pgxpool.Pool) *WorkoutRepository {
	return &WorkoutRepository{db: db}
}

func (r *WorkoutRepository) Create(ctx context.Context, w *domain.Workout) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO workouts (id, user_id, started_at, notes, status, template_id)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		w.ID, w.UserID, w.StartedAt, w.Notes, w.Status, w.TemplateID,
	)
	return err
}

func (r *WorkoutRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Workout, error) {
	return r.scanWorkout(r.db.QueryRow(ctx,
		`SELECT id, user_id, started_at, ended_at, notes, status, template_id FROM workouts WHERE id = $1`, id))
}

func (r *WorkoutRepository) FindActiveForUser(ctx context.Context, userID uuid.UUID) (*domain.Workout, error) {
	return r.scanWorkout(r.db.QueryRow(ctx,
		`SELECT id, user_id, started_at, ended_at, notes, status, template_id
		 FROM workouts WHERE user_id = $1 AND status = 'in_progress'`, userID))
}

func (r *WorkoutRepository) Finish(ctx context.Context, id uuid.UUID, endedAt time.Time, notes string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE workouts SET ended_at = $2, notes = $3, status = 'completed' WHERE id = $1`,
		id, endedAt, notes,
	)
	return err
}

func (r *WorkoutRepository) ListForUser(ctx context.Context, userID uuid.UUID, limit int, afterStartedAt *time.Time, afterID *uuid.UUID) ([]*domain.Workout, error) {
	query := `SELECT id, user_id, started_at, ended_at, notes, status, template_id FROM workouts WHERE user_id = $1`
	args := []any{userID}
	if afterStartedAt != nil && afterID != nil {
		query += ` AND (started_at, id) < ($2, $3)`
		args = append(args, *afterStartedAt, *afterID)
	}
	query += fmt.Sprintf(` ORDER BY started_at DESC, id DESC LIMIT $%d`, len(args)+1)
	args = append(args, limit)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var workouts []*domain.Workout
	for rows.Next() {
		var w domain.Workout
		if err := rows.Scan(&w.ID, &w.UserID, &w.StartedAt, &w.EndedAt, &w.Notes, &w.Status, &w.TemplateID); err != nil {
			return nil, err
		}
		workouts = append(workouts, &w)
	}
	return workouts, rows.Err()
}

func (r *WorkoutRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM workouts WHERE id = $1`, id)
	return err
}

func (r *WorkoutRepository) FindMostRecentFinishedByTemplateIDs(ctx context.Context, userID uuid.UUID, templateIDs []uuid.UUID) (*domain.Workout, error) {
	row := r.db.QueryRow(ctx,
		`SELECT id, user_id, started_at, ended_at, notes, status, template_id
		 FROM workouts
		 WHERE user_id = $1 AND status = 'completed' AND template_id = ANY($2)
		 ORDER BY ended_at DESC LIMIT 1`,
		userID, templateIDs,
	)
	var w domain.Workout
	err := row.Scan(&w.ID, &w.UserID, &w.StartedAt, &w.EndedAt, &w.Notes, &w.Status, &w.TemplateID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &w, nil
}

func (r *WorkoutRepository) scanWorkout(row pgx.Row) (*domain.Workout, error) {
	var w domain.Workout
	err := row.Scan(&w.ID, &w.UserID, &w.StartedAt, &w.EndedAt, &w.Notes, &w.Status, &w.TemplateID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrWorkoutNotFound
	}
	if err != nil {
		return nil, err
	}
	return &w, nil
}
