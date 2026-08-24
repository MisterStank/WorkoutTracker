-- A short, ephemeral code that lets someone else watch this workout live
-- (read-only) without a friends/follow system — just "type this code to
-- watch". Only meaningful while the workout is in_progress; not unique
-- forever, just unique among currently-active codes (enforced at the
-- application layer via retry-on-collision, since a global UNIQUE would
-- block reissuing a short code once its workout finishes).
ALTER TABLE workouts ADD COLUMN share_code TEXT;
CREATE UNIQUE INDEX idx_workouts_share_code_active ON workouts (share_code) WHERE status = 'in_progress';
