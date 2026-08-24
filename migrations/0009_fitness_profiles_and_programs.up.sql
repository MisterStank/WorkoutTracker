-- One saved set of inputs per user for generating a personalized program.
-- A single row (not versioned) — regenerating a program just re-reads
-- whatever is currently saved here.
CREATE TABLE user_fitness_profiles (
    user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    goal                TEXT NOT NULL,
    experience_level    TEXT NOT NULL,
    days_per_week       INT NOT NULL,
    equipment_access    TEXT[] NOT NULL DEFAULT '{}',
    avoid_muscle_groups TEXT[] NOT NULL DEFAULT '{}',
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A program is a named, ordered collection of existing single-day
-- workout_templates — deliberately not a new "workout plan" concept, so
-- starting a workout from a program day reuses the exact same
-- startWorkout(templateId:) path a manually-built template already uses.
CREATE TABLE programs (
    id            UUID PRIMARY KEY,
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    goal          TEXT NOT NULL,
    days_per_week INT NOT NULL,
    notes         TEXT NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_programs_user_id ON programs (user_id);

CREATE TABLE program_days (
    id          UUID PRIMARY KEY,
    program_id  UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
    day_label   TEXT NOT NULL,
    position    INT NOT NULL,
    template_id UUID NOT NULL REFERENCES workout_templates(id) ON DELETE CASCADE
);

CREATE INDEX idx_program_days_program_id ON program_days (program_id);
