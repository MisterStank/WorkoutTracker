DROP INDEX idx_programs_one_active_per_user;
ALTER TABLE programs DROP COLUMN is_active;
