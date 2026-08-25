-- Which program the user is actually following right now. Without this,
-- "next workout" had to guess (most recently created program), and the
-- Programs list was just a read-only catalog with no way to say "this is
-- the one I'm using" — see ProgramService.SetActiveProgram.
ALTER TABLE programs ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT false;

-- At most one active program per user, enforced in the database rather
-- than only in application code.
CREATE UNIQUE INDEX idx_programs_one_active_per_user ON programs (user_id) WHERE is_active;
