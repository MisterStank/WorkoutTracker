package repository

import (
	"context"
	"errors"
	"time"

	"gymon/internal/domain"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PetRepository struct {
	db *pgxpool.Pool
}

func NewPetRepository(db *pgxpool.Pool) *PetRepository {
	return &PetRepository{db: db}
}

func (r *PetRepository) FindByUser(ctx context.Context, userID uuid.UUID) (*domain.Pet, error) {
	var p domain.Pet
	var stage int16
	err := r.db.QueryRow(ctx,
		`SELECT id, user_id, name, species, color, stage, stage_updated_at, longest_streak, hatched_at, created_at
		 FROM pets WHERE user_id = $1`, userID,
	).Scan(&p.ID, &p.UserID, &p.Name, &p.Species, &p.Color, &stage, &p.StageUpdatedAt, &p.LongestStreak, &p.HatchedAt, &p.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrPetNotFound
	}
	if err != nil {
		return nil, err
	}
	p.Stage = domain.PetStage(stage)
	return &p, nil
}

func (r *PetRepository) Create(ctx context.Context, p *domain.Pet) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO pets (id, user_id, name, species, color, stage, stage_updated_at, longest_streak, hatched_at, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		p.ID, p.UserID, p.Name, p.Species, p.Color, int16(p.Stage), p.StageUpdatedAt, p.LongestStreak, p.HatchedAt, p.CreatedAt,
	)
	return err
}

func (r *PetRepository) Update(ctx context.Context, p *domain.Pet) error {
	_, err := r.db.Exec(ctx,
		`UPDATE pets
		 SET name = $2, color = $3, stage = $4, stage_updated_at = $5, longest_streak = $6, hatched_at = $7
		 WHERE id = $1`,
		p.ID, p.Name, p.Color, int16(p.Stage), p.StageUpdatedAt, p.LongestStreak, p.HatchedAt,
	)
	return err
}

type AccessoryRepository struct {
	db *pgxpool.Pool
}

func NewAccessoryRepository(db *pgxpool.Pool) *AccessoryRepository {
	return &AccessoryRepository{db: db}
}

func (r *AccessoryRepository) ListCatalog(ctx context.Context) ([]*domain.Accessory, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, code, name, slot, unlock_code, unlock_hint, sort_order
		 FROM accessory_catalog ORDER BY sort_order`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*domain.Accessory
	for rows.Next() {
		var a domain.Accessory
		if err := rows.Scan(&a.ID, &a.Code, &a.Name, &a.Slot, &a.UnlockCode, &a.UnlockHint, &a.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, &a)
	}
	return out, rows.Err()
}

func (r *AccessoryRepository) ListOwned(ctx context.Context, petID uuid.UUID) ([]*domain.OwnedAccessory, error) {
	rows, err := r.db.Query(ctx,
		`SELECT c.id, c.code, c.name, c.slot, c.unlock_code, c.unlock_hint, c.sort_order,
		        pa.unlocked_at, pa.equipped
		 FROM pet_accessories pa
		 JOIN accessory_catalog c ON c.id = pa.accessory_id
		 WHERE pa.pet_id = $1
		 ORDER BY c.sort_order`, petID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*domain.OwnedAccessory
	for rows.Next() {
		var o domain.OwnedAccessory
		if err := rows.Scan(
			&o.Accessory.ID, &o.Accessory.Code, &o.Accessory.Name, &o.Accessory.Slot,
			&o.Accessory.UnlockCode, &o.Accessory.UnlockHint, &o.Accessory.SortOrder,
			&o.UnlockedAt, &o.Equipped,
		); err != nil {
			return nil, err
		}
		out = append(out, &o)
	}
	return out, rows.Err()
}

func (r *AccessoryRepository) Unlock(ctx context.Context, petID, accessoryID uuid.UUID, slot string, at time.Time) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO pet_accessories (pet_id, accessory_id, slot, unlocked_at, equipped)
		 VALUES ($1, $2, $3, $4, false)
		 ON CONFLICT (pet_id, accessory_id) DO NOTHING`,
		petID, accessoryID, slot, at,
	)
	return err
}

// SetEquipped flips one owned accessory's equipped flag. Equipping first
// clears any other equipped accessory in the same slot, in one transaction,
// so the "one item per slot" partial unique index can never be violated.
func (r *AccessoryRepository) SetEquipped(ctx context.Context, petID, accessoryID uuid.UUID, equipped bool) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if equipped {
		if _, err := tx.Exec(ctx,
			`UPDATE pet_accessories SET equipped = false
			 WHERE pet_id = $1 AND equipped = true
			   AND slot = (SELECT slot FROM pet_accessories WHERE pet_id = $1 AND accessory_id = $2)`,
			petID, accessoryID,
		); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx,
		`UPDATE pet_accessories SET equipped = $3 WHERE pet_id = $1 AND accessory_id = $2`,
		petID, accessoryID, equipped,
	); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// PetStatsRepository gathers the read-only training-history facts the pet
// rules run on, in one round of queries.
type PetStatsRepository struct {
	db *pgxpool.Pool
}

func NewPetStatsRepository(db *pgxpool.Pool) *PetStatsRepository {
	return &PetStatsRepository{db: db}
}

func (r *PetStatsRepository) GatherStats(ctx context.Context, userID uuid.UUID) (*domain.PetStatsSnapshot, error) {
	snap := &domain.PetStatsSnapshot{}

	rows, err := r.db.Query(ctx,
		`SELECT ended_at FROM workouts
		 WHERE user_id = $1 AND status = 'completed' AND ended_at IS NOT NULL
		 ORDER BY ended_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var t time.Time
		if err := rows.Scan(&t); err != nil {
			rows.Close()
			return nil, err
		}
		snap.FinishedWorkoutEndTimes = append(snap.FinishedWorkoutEndTimes, t)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if err := r.db.QueryRow(ctx,
		`SELECT count(*) FROM personal_records WHERE user_id = $1`, userID,
	).Scan(&snap.PersonalRecordCount); err != nil {
		return nil, err
	}

	if err := r.db.QueryRow(ctx,
		`SELECT count(DISTINCT ws.exercise_id)
		 FROM workout_sets ws
		 JOIN workouts w ON w.id = ws.workout_id
		 WHERE w.user_id = $1 AND ws.set_type != 'warmup'`, userID,
	).Scan(&snap.DistinctExercisesLogged); err != nil {
		return nil, err
	}

	if err := r.db.QueryRow(ctx,
		`SELECT count(DISTINCT mg) FROM (
		   SELECT unnest(e.muscle_groups) AS mg
		   FROM workout_sets ws
		   JOIN workouts w ON w.id = ws.workout_id
		   JOIN exercises e ON e.id = ws.exercise_id
		   WHERE w.user_id = $1 AND ws.set_type != 'warmup'
		 ) t`, userID,
	).Scan(&snap.DistinctMuscleGroups); err != nil {
		return nil, err
	}

	if err := r.db.QueryRow(ctx,
		`SELECT count(*) FROM workout_templates WHERE user_id = $1`, userID,
	).Scan(&snap.TemplateCount); err != nil {
		return nil, err
	}

	if err := r.db.QueryRow(ctx,
		`SELECT count(*) FROM body_metrics WHERE user_id = $1`, userID,
	).Scan(&snap.BodyMetricCount); err != nil {
		return nil, err
	}

	return snap, nil
}
