CREATE TABLE body_metrics (
    id          UUID PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    metric_type TEXT NOT NULL,
    value       NUMERIC(8,2) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_body_metrics_user_type_recorded ON body_metrics (user_id, metric_type, recorded_at);

-- Pre-aggregated per-day totals per exercise, maintained transactionally
-- alongside every set insert (see WorkoutSetRepository.LogSet) so progress
-- charts read this small table instead of scanning workout_sets.
CREATE TABLE progress_daily_rollup (
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exercise_id  UUID NOT NULL REFERENCES exercises(id),
    day          DATE NOT NULL,
    total_volume NUMERIC(10,2) NOT NULL DEFAULT 0,
    max_weight   NUMERIC(6,2) NOT NULL DEFAULT 0,
    set_count    INT NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, exercise_id, day)
);

CREATE INDEX idx_rollup_user_exercise_day ON progress_daily_rollup (user_id, exercise_id, day);
CREATE INDEX idx_rollup_user_day ON progress_daily_rollup (user_id, day);
