-- The virtual companion pet — the app's headline motivation mechanic. Each
-- user has at most one pet. Its short-term "mood" is NOT stored here: it is
-- derived on read from the user's finished-workout timestamps (see
-- internal/service/pet_rules.go), so there is no snapshot to decay on a
-- schedule and nothing to reconcile after an offline workout. Only the
-- monotonic progress that must survive a bad day is persisted: the evolution
-- stage and the longest streak ever reached.
CREATE TABLE pets (
    id               UUID PRIMARY KEY,
    user_id          UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    species          TEXT NOT NULL,
    color            TEXT NOT NULL,
    -- Evolution stage 0..4 (egg, hatchling, juvenile, adult, champion).
    -- Monotonic: bumped forward when milestones are met, never decreased.
    stage            SMALLINT NOT NULL DEFAULT 0,
    stage_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Longest consecutive-training-day streak the user has ever reached,
    -- persisted because the current streak is derived and a missed day would
    -- otherwise erase the record that gates the final evolution stage.
    longest_streak   INT NOT NULL DEFAULT 0,
    -- Null until the egg hatches on the first finished workout.
    hatched_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The set of cosmetic accessories a pet can earn. Seeded here like the
-- exercise catalog. unlock_code identifies the rule in the rules engine
-- (internal/service/pet_rules.go) that decides whether a given pet has
-- earned it; slot enforces "one equipped item per slot".
CREATE TABLE accessory_catalog (
    id          UUID PRIMARY KEY,
    code        TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    slot        TEXT NOT NULL,
    unlock_code TEXT NOT NULL,
    unlock_hint TEXT NOT NULL DEFAULT '',
    sort_order  INT NOT NULL DEFAULT 0
);

CREATE TABLE pet_accessories (
    pet_id       UUID NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
    accessory_id UUID NOT NULL REFERENCES accessory_catalog(id) ON DELETE CASCADE,
    unlocked_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    equipped     BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (pet_id, accessory_id)
);

-- At most one equipped accessory per (pet, slot). The slot lives on
-- accessory_catalog, so enforce it with a trigger-free partial unique index
-- over a helper: a unique index on (pet_id, slot) filtered to equipped rows,
-- backed by a denormalized slot column kept in sync from the catalog.
ALTER TABLE pet_accessories ADD COLUMN slot TEXT NOT NULL DEFAULT '';
CREATE UNIQUE INDEX idx_pet_accessories_one_per_slot
    ON pet_accessories (pet_id, slot) WHERE equipped;

INSERT INTO accessory_catalog (id, code, name, slot, unlock_code, unlock_hint, sort_order) VALUES
    (gen_random_uuid(), 'starter_band',   'Sweatband',        'head',       'workouts_1',        'Finish your first workout',                 10),
    (gen_random_uuid(), 'streak_cap_3',   'Rookie Cap',       'head',       'streak_3',          'Reach a 3-day streak',                      20),
    (gen_random_uuid(), 'streak_cap_7',   'Weekly Warrior Hat','head',      'streak_7',          'Reach a 7-day streak',                      30),
    (gen_random_uuid(), 'streak_cap_14',  'Fortnight Crown',  'head',       'streak_14',         'Reach a 14-day streak',                     40),
    (gen_random_uuid(), 'streak_cap_30',  'Iron Halo',        'head',       'streak_30',         'Reach a 30-day streak',                     50),
    (gen_random_uuid(), 'streak_cap_100', 'Centurion Helm',   'head',       'streak_100',        'Reach a 100-day streak',                    60),
    (gen_random_uuid(), 'streak_cap_365', 'Year One Diadem',  'head',       'streak_365',        'Reach a 365-day streak',                    70),
    (gen_random_uuid(), 'collar_bronze',  'Bronze Collar',    'collar',     'workouts_10',       'Finish 10 workouts',                        80),
    (gen_random_uuid(), 'collar_silver',  'Silver Collar',    'collar',     'workouts_50',       'Finish 50 workouts',                        90),
    (gen_random_uuid(), 'collar_gold',    'Gold Collar',      'collar',     'workouts_100',      'Finish 100 workouts',                      100),
    (gen_random_uuid(), 'collar_plat',    'Platinum Collar',  'collar',     'workouts_250',      'Finish 250 workouts',                      110),
    (gen_random_uuid(), 'collar_diamond', 'Diamond Collar',   'collar',     'workouts_500',      'Finish 500 workouts',                      120),
    (gen_random_uuid(), 'medal_first_pr', 'First PR Medal',   'collar',     'pr_1',              'Set your first personal record',           130),
    (gen_random_uuid(), 'medal_pr_10',    'PR Streak Medal',  'collar',     'pr_10',             'Set 10 personal records',                  140),
    (gen_random_uuid(), 'medal_pr_25',    'Record Breaker Medal','collar',  'pr_25',             'Set 25 personal records',                  150),
    (gen_random_uuid(), 'medal_pr_100',   'Legend Medal',     'collar',     'pr_100',            'Set 100 personal records',                 160),
    (gen_random_uuid(), 'cape_explorer',  'Explorer Cape',    'back',       'exercises_10',      'Log 10 different exercises',               170),
    (gen_random_uuid(), 'cape_anatomist', 'Anatomist Cape',   'back',       'muscles_5',         'Train 5 different muscle groups',          180),
    (gen_random_uuid(), 'cape_architect', 'Architect Cape',   'back',       'template_1',        'Create your first template',               190),
    (gen_random_uuid(), 'cape_planner',   'Planner Cape',     'back',       'templates_5',       'Create 5 templates',                       200),
    (gen_random_uuid(), 'aura_scale',     'Scale Aura',       'aura',       'bodyweight_1',      'Log your body weight',                     210),
    (gen_random_uuid(), 'aura_dawn',      'Dawn Aura',        'aura',       'early_bird',        'Finish a workout before 7am',              220),
    (gen_random_uuid(), 'aura_weekend',   'Weekend Aura',     'aura',       'weekend_warrior',   'Train on both Saturday and Sunday',        230),
    (gen_random_uuid(), 'aura_consistent','Consistency Aura', 'aura',       'weeks4_ontarget',   'Hit 3 workouts a week for 4 weeks straight',240),
    (gen_random_uuid(), 'bg_gym',         'Home Gym',         'background', 'workouts_25',       'Finish 25 workouts',                       250),
    (gen_random_uuid(), 'bg_summit',      'Mountain Summit',  'background', 'streak_60',         'Reach a 60-day streak',                    260);
