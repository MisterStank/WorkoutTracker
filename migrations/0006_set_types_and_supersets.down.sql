ALTER TABLE workout_template_exercises DROP COLUMN superset_group;
ALTER TABLE workout_sets DROP COLUMN superset_id;

ALTER TABLE workout_sets ADD COLUMN is_warmup BOOLEAN NOT NULL DEFAULT false;
UPDATE workout_sets SET is_warmup = true WHERE set_type = 'warmup';
ALTER TABLE workout_sets DROP COLUMN set_type;
