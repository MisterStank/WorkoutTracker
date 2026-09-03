package repository

import (
	"context"
	"errors"

	"gymon/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type FitnessProfileRepository struct {
	db *pgxpool.Pool
}

func NewFitnessProfileRepository(db *pgxpool.Pool) *FitnessProfileRepository {
	return &FitnessProfileRepository{db: db}
}

func (r *FitnessProfileRepository) Get(ctx context.Context, userID uuid.UUID) (*domain.UserFitnessProfile, error) {
	var p domain.UserFitnessProfile
	err := r.db.QueryRow(ctx,
		`SELECT user_id, goal, experience_level, days_per_week, equipment_access, avoid_muscle_groups, updated_at
		 FROM user_fitness_profiles WHERE user_id = $1`, userID,
	).Scan(&p.UserID, &p.Goal, &p.ExperienceLevel, &p.DaysPerWeek, &p.EquipmentAccess, &p.AvoidMuscleGroups, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrFitnessProfileNotFound
	}
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *FitnessProfileRepository) Upsert(ctx context.Context, p *domain.UserFitnessProfile) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO user_fitness_profiles (user_id, goal, experience_level, days_per_week, equipment_access, avoid_muscle_groups, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 ON CONFLICT (user_id) DO UPDATE
		   SET goal = EXCLUDED.goal, experience_level = EXCLUDED.experience_level, days_per_week = EXCLUDED.days_per_week,
		       equipment_access = EXCLUDED.equipment_access, avoid_muscle_groups = EXCLUDED.avoid_muscle_groups, updated_at = EXCLUDED.updated_at`,
		p.UserID, p.Goal, p.ExperienceLevel, p.DaysPerWeek, p.EquipmentAccess, p.AvoidMuscleGroups, p.UpdatedAt,
	)
	return err
}
