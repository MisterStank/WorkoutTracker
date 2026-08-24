-- Live workout sharing (watch-a-friend via share code) has been removed in
-- favor of sharing a workout summary/PR as a static image to social media.
DROP INDEX idx_workouts_share_code_active;
ALTER TABLE workouts DROP COLUMN share_code;
