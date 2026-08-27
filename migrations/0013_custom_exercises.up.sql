-- Custom exercises reuse the existing exercises.created_by column (added in
-- 0002) as the owner: NULL = built-in catalog entry, set = a user's own.
-- This index enforces "one custom exercise name per user" (case-insensitive)
-- so the create/update flow can return a clean "you already have an
-- exercise called X" instead of silently duplicating.
CREATE UNIQUE INDEX idx_exercises_owner_name
    ON exercises (created_by, lower(name))
    WHERE created_by IS NOT NULL;
