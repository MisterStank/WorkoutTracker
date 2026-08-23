CREATE TABLE exercises (
    id            UUID PRIMARY KEY,
    name          TEXT NOT NULL,
    category      TEXT NOT NULL,
    muscle_groups TEXT[] NOT NULL DEFAULT '{}',
    equipment     TEXT NOT NULL DEFAULT '',
    is_custom     BOOLEAN NOT NULL DEFAULT false,
    created_by    UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_exercises_name ON exercises (lower(name));
CREATE INDEX idx_exercises_muscle_groups ON exercises USING GIN (muscle_groups);

CREATE TYPE workout_status AS ENUM ('in_progress', 'completed');

CREATE TABLE workouts (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at   TIMESTAMPTZ,
    notes      TEXT NOT NULL DEFAULT '',
    status     workout_status NOT NULL DEFAULT 'in_progress'
);

CREATE INDEX idx_workouts_user_started ON workouts (user_id, started_at DESC);
-- Only one workout can be in progress per user at a time.
CREATE UNIQUE INDEX idx_workouts_one_active_per_user ON workouts (user_id) WHERE status = 'in_progress';

CREATE TABLE workout_sets (
    id           UUID PRIMARY KEY,
    workout_id   UUID NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    exercise_id  UUID NOT NULL REFERENCES exercises(id),
    set_number   INT NOT NULL,
    reps         INT NOT NULL,
    weight_kg    NUMERIC(6,2) NOT NULL,
    rpe          NUMERIC(3,1),
    performed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_workout_sets_workout ON workout_sets (workout_id);
CREATE INDEX idx_workout_sets_exercise_workout ON workout_sets (exercise_id, workout_id);

CREATE TABLE personal_records (
    id             UUID PRIMARY KEY,
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exercise_id    UUID NOT NULL REFERENCES exercises(id),
    record_type    TEXT NOT NULL,
    value          NUMERIC(8,2) NOT NULL,
    achieved_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    workout_set_id UUID NOT NULL REFERENCES workout_sets(id) ON DELETE CASCADE,
    UNIQUE (user_id, exercise_id, record_type)
);

CREATE INDEX idx_personal_records_user_exercise ON personal_records (user_id, exercise_id, record_type);

INSERT INTO exercises (id, name, category, muscle_groups, equipment) VALUES
    (gen_random_uuid(), 'Barbell Bench Press', 'push', '{chest,triceps,shoulders}', 'barbell'),
    (gen_random_uuid(), 'Barbell Back Squat', 'legs', '{quads,glutes,hamstrings}', 'barbell'),
    (gen_random_uuid(), 'Conventional Deadlift', 'pull', '{hamstrings,glutes,back}', 'barbell'),
    (gen_random_uuid(), 'Overhead Press', 'push', '{shoulders,triceps}', 'barbell'),
    (gen_random_uuid(), 'Pull-Up', 'pull', '{back,biceps}', 'bodyweight'),
    (gen_random_uuid(), 'Barbell Row', 'pull', '{back,biceps}', 'barbell'),
    (gen_random_uuid(), 'Dumbbell Bicep Curl', 'arms', '{biceps}', 'dumbbell'),
    (gen_random_uuid(), 'Triceps Pushdown', 'arms', '{triceps}', 'cable'),
    (gen_random_uuid(), 'Leg Press', 'legs', '{quads,glutes}', 'machine'),
    (gen_random_uuid(), 'Plank', 'core', '{abs}', 'bodyweight');
