-- Generalizes the warm-up-only flag into a set type (Hevy has warm-up, drop
-- set, and failure set, not just warm-up), and adds superset grouping.
ALTER TABLE workout_sets ADD COLUMN set_type TEXT NOT NULL DEFAULT 'normal';
UPDATE workout_sets SET set_type = 'warmup' WHERE is_warmup;
ALTER TABLE workout_sets DROP COLUMN is_warmup;

-- Sets sharing a non-null superset_id (within the same workout) are logged
-- as one superset. Purely a display/grouping tag — doesn't affect PR or
-- rollup computation, so no FK or extra validation needed.
ALTER TABLE workout_sets ADD COLUMN superset_id UUID;
CREATE INDEX idx_workout_sets_superset ON workout_sets (workout_id, superset_id) WHERE superset_id IS NOT NULL;

-- Template exercises sharing a non-null superset_group are planned as a
-- superset when a workout is started from that template.
ALTER TABLE workout_template_exercises ADD COLUMN superset_group INT;
