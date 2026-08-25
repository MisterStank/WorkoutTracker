package repository

import (
	"context"
	"errors"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ProgramRepository struct {
	db        *pgxpool.Pool
	templates *WorkoutTemplateRepository
}

func NewProgramRepository(db *pgxpool.Pool, templates *WorkoutTemplateRepository) *ProgramRepository {
	return &ProgramRepository{db: db, templates: templates}
}

func (r *ProgramRepository) Create(ctx context.Context, p *domain.Program) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`INSERT INTO programs (id, user_id, name, goal, days_per_week, notes, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		p.ID, p.UserID, p.Name, p.Goal, p.DaysPerWeek, p.Notes, p.CreatedAt,
	); err != nil {
		return err
	}

	for _, day := range p.Days {
		if _, err := tx.Exec(ctx,
			`INSERT INTO program_days (id, program_id, day_label, position, template_id) VALUES ($1, $2, $3, $4, $5)`,
			day.ID, p.ID, day.DayLabel, day.Position, day.TemplateID,
		); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *ProgramRepository) ListForUser(ctx context.Context, userID uuid.UUID) ([]*domain.Program, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, user_id, name, goal, days_per_week, notes, created_at FROM programs WHERE user_id = $1 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var programs []*domain.Program
	for rows.Next() {
		var p domain.Program
		if err := rows.Scan(&p.ID, &p.UserID, &p.Name, &p.Goal, &p.DaysPerWeek, &p.Notes, &p.CreatedAt); err != nil {
			return nil, err
		}
		programs = append(programs, &p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	for _, p := range programs {
		days, err := r.daysForProgram(ctx, p.ID)
		if err != nil {
			return nil, err
		}
		p.Days = days
	}
	return programs, nil
}

func (r *ProgramRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Program, error) {
	var p domain.Program
	err := r.db.QueryRow(ctx,
		`SELECT id, user_id, name, goal, days_per_week, notes, created_at FROM programs WHERE id = $1`, id,
	).Scan(&p.ID, &p.UserID, &p.Name, &p.Goal, &p.DaysPerWeek, &p.Notes, &p.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrProgramNotFound
	}
	if err != nil {
		return nil, err
	}

	days, err := r.daysForProgram(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	p.Days = days
	return &p, nil
}

func (r *ProgramRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM programs WHERE id = $1`, id)
	return err
}

// daysForProgram hydrates each day's full WorkoutTemplate via the existing
// template repository rather than hand-rolling the join — an N+1 here is
// fine, a program has at most a handful of days and this isn't a hot path.
func (r *ProgramRepository) daysForProgram(ctx context.Context, programID uuid.UUID) ([]*domain.ProgramDay, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, program_id, day_label, position, template_id FROM program_days WHERE program_id = $1 ORDER BY position`,
		programID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var days []*domain.ProgramDay
	for rows.Next() {
		var d domain.ProgramDay
		if err := rows.Scan(&d.ID, &d.ProgramID, &d.DayLabel, &d.Position, &d.TemplateID); err != nil {
			return nil, err
		}
		days = append(days, &d)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	for _, d := range days {
		tmpl, err := r.templates.FindByID(ctx, d.TemplateID)
		if err != nil {
			return nil, err
		}
		d.Template = tmpl
	}
	return days, nil
}
