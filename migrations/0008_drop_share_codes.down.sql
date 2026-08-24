ALTER TABLE workouts ADD COLUMN share_code TEXT;
CREATE UNIQUE INDEX idx_workouts_share_code_active ON workouts (share_code) WHERE status = 'in_progress';
