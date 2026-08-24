CREATE TABLE workout_templates (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_workout_templates_user ON workout_templates (user_id);

CREATE TABLE workout_template_exercises (
    id          UUID PRIMARY KEY,
    template_id UUID NOT NULL REFERENCES workout_templates(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    position    INT NOT NULL,
    target_sets INT NOT NULL DEFAULT 3,
    target_reps INT,
    UNIQUE (template_id, position)
);

CREATE INDEX idx_template_exercises_template ON workout_template_exercises (template_id);

-- Nullable: a workout started "from scratch" has no template.
ALTER TABLE workouts ADD COLUMN template_id UUID REFERENCES workout_templates(id) ON DELETE SET NULL;
