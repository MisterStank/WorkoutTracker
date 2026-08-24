package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
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
		`INSERT INTO workouts (id, user_id, started_at, notes, status, template_id, share_code)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		w.ID, w.UserID, w.StartedAt, w.Notes, w.Status, w.TemplateID, w.ShareCode,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "idx_workouts_share_code_active" {
			return domain.ErrShareCodeTaken
		}
		return err
	}
	return nil
}

func (r *WorkoutRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Workout, error) {
	return r.scanWorkout(r.db.QueryRow(ctx,
		`SELECT id, user_id, started_at, ended_at, notes, status, template_id, share_code FROM workouts WHERE id = $1`, id))
}

func (r *WorkoutRepository) FindActiveForUser(ctx context.Context, userID uuid.UUID) (*domain.Workout, error) {
	return r.scanWorkout(r.db.QueryRow(ctx,
		`SELECT id, user_id, started_at, ended_at, notes, status, template_id, share_code
		 FROM workouts WHERE user_id = $1 AND status = 'in_progress'`, userID))
}

func (r *WorkoutRepository) FindByShareCode(ctx context.Context, code string) (*domain.Workout, error) {
	return r.scanWorkout(r.db.QueryRow(ctx,
		`SELECT id, user_id, started_at, ended_at, notes, status, template_id, share_code
		 FROM workouts WHERE share_code = $1 AND status = 'in_progress'`, code))
}

func (r *WorkoutRepository) Finish(ctx context.Context, id uuid.UUID, endedAt time.Time, notes string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE workouts SET ended_at = $2, notes = $3, status = 'completed' WHERE id = $1`,
		id, endedAt, notes,
	)
	return err
}

func (r *WorkoutRepository) ListForUser(ctx context.Context, userID uuid.UUID, limit int, afterStartedAt *time.Time, afterID *uuid.UUID) ([]*domain.Workout, error) {
	query := `SELECT id, user_id, started_at, ended_at, notes, status, template_id, share_code FROM workouts WHERE user_id = $1`
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
		if err := rows.Scan(&w.ID, &w.UserID, &w.StartedAt, &w.EndedAt, &w.Notes, &w.Status, &w.TemplateID, &w.ShareCode); err != nil {
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

func (r *WorkoutRepository) scanWorkout(row pgx.Row) (*domain.Workout, error) {
	var w domain.Workout
	err := row.Scan(&w.ID, &w.UserID, &w.StartedAt, &w.EndedAt, &w.Notes, &w.Status, &w.TemplateID, &w.ShareCode)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrWorkoutNotFound
	}
	if err != nil {
		return nil, err
	}
	return &w, nil
}
