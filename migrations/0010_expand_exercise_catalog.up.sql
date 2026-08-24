-- Expands the exercise catalog from 10 to 46 rows so the program generator
-- (migration 0009) has enough variety to actually respond to equipment
-- access and avoided muscle groups — every muscle group used by the
-- generator has at least one bodyweight-only option, so an
-- equipment_access: [bodyweight] profile never yields zero eligible
-- exercises for a planned muscle group.
INSERT INTO exercises (id, name, category, muscle_groups, equipment) VALUES
    ('198508db-b3bb-41e0-8074-56b9a50ca98d', 'Incline Dumbbell Press', 'push', '{chest,shoulders,triceps}', 'dumbbell'),
    ('b0588021-e9b5-488a-b53c-432b792352b0', 'Dumbbell Shoulder Press', 'push', '{shoulders,triceps}', 'dumbbell'),
    ('4f721f42-c690-483a-88ac-fcf273d6213b', 'Push-Up', 'push', '{chest,triceps,shoulders}', 'bodyweight'),
    ('38a30b21-91f7-4ffa-8f18-e2a60cb3fa0a', 'Chest Press Machine', 'push', '{chest,triceps}', 'machine'),
    ('5ec41b7a-90ba-4f15-a8d9-5226da38b940', 'Cable Chest Fly', 'push', '{chest}', 'cable'),
    ('37121d3e-b2d5-45d5-b002-faa229f37e0f', 'Dips', 'push', '{triceps,chest}', 'bodyweight'),
    ('de517096-601e-4082-9432-ac1aa9ad3664', 'Lateral Raise', 'push', '{shoulders}', 'dumbbell'),
    ('8c53fee0-f2da-4416-96c9-bfbba87627ca', 'Pike Push-Up', 'push', '{shoulders,triceps}', 'bodyweight'),
    ('9e538794-faff-494f-b895-ab53ee61821a', 'Lat Pulldown', 'pull', '{back,biceps}', 'cable'),
    ('9ca891fb-6dfa-4472-b4b2-8ee42b313980', 'Seated Cable Row', 'pull', '{back,biceps}', 'cable'),
    ('b8ecc114-4fcc-4827-9627-04b4abc08334', 'Dumbbell Row', 'pull', '{back,biceps}', 'dumbbell'),
    ('40be20e0-e189-4ba1-9819-7183371196c3', 'Inverted Row', 'pull', '{back,biceps}', 'bodyweight'),
    ('219e04b6-feef-411b-b102-0496ae70c478', 'Chin-Up', 'pull', '{back,biceps}', 'bodyweight'),
    ('653393d6-ab76-4de3-b02b-143705a6329e', 'T-Bar Row Machine', 'pull', '{back,biceps}', 'machine'),
    ('f3eb480b-a54d-4eb9-88dc-6f24a922fc62', 'Face Pull', 'pull', '{back,shoulders}', 'cable'),
    ('c34f0b70-1280-4c95-85c2-7326a312a237', 'Barbell Curl', 'arms', '{biceps}', 'barbell'),
    ('1cecf759-7db1-48ff-8633-674a17f95d56', 'Hammer Curl', 'arms', '{biceps}', 'dumbbell'),
    ('cd618215-1e4c-41aa-911d-c5801199a228', 'Romanian Deadlift', 'legs', '{hamstrings,glutes}', 'barbell'),
    ('b98d6336-5ada-4f69-9963-48ac6fa020d0', 'Dumbbell Lunge', 'legs', '{quads,glutes}', 'dumbbell'),
    ('f53a7353-ffd2-4a92-9933-3acdd6c41483', 'Bodyweight Squat', 'legs', '{quads,glutes}', 'bodyweight'),
    ('b7c410cc-be12-4c10-83b8-6652d6c22719', 'Bulgarian Split Squat', 'legs', '{quads,glutes}', 'dumbbell'),
    ('bf99fa88-6e92-490c-8119-a203ef536c33', 'Leg Curl Machine', 'legs', '{hamstrings}', 'machine'),
    ('7d27080d-4d04-4526-885c-6fe3f2dc118e', 'Leg Extension Machine', 'legs', '{quads}', 'machine'),
    ('58bf85b1-20db-4605-b1aa-893a61b13da2', 'Hip Thrust', 'legs', '{glutes,hamstrings}', 'barbell'),
    ('62798498-78f2-4c78-a961-534a6c350f70', 'Glute Bridge', 'legs', '{glutes,hamstrings}', 'bodyweight'),
    ('cc194649-53b6-4807-8a3d-c441970867fd', 'Walking Lunge', 'legs', '{quads,glutes}', 'bodyweight'),
    ('056d6a26-3637-451e-a261-848173b4ac51', 'Goblet Squat', 'legs', '{quads,glutes}', 'dumbbell'),
    ('5ecdb8f8-2a9b-4679-9183-f4d76d5d4be0', 'Cable Curl', 'arms', '{biceps}', 'cable'),
    ('621466f7-584c-4360-94bb-e0f712ebf036', 'Overhead Triceps Extension', 'arms', '{triceps}', 'dumbbell'),
    ('0736f991-d19b-4125-ac4d-2dfba22264c4', 'Close-Grip Bench Press', 'arms', '{triceps,chest}', 'barbell'),
    ('a6d61e27-5efb-4f77-aa50-71f692b845cd', 'Diamond Push-Up', 'arms', '{triceps,chest}', 'bodyweight'),
    ('cb78a1fc-92ba-4266-a9a6-853a04a4ff67', 'Crunch', 'core', '{abs}', 'bodyweight'),
    ('5759c345-d066-4935-b886-6aead3d0ab73', 'Hanging Leg Raise', 'core', '{abs}', 'bodyweight'),
    ('05aaae97-e03c-49d9-946a-a2ce07e90fa6', 'Cable Woodchop', 'core', '{abs}', 'cable'),
    ('31f248a7-98a7-4ae7-9f28-07ab951771ec', 'Russian Twist', 'core', '{abs}', 'bodyweight'),
    ('6b38e0c8-00f6-4de7-bdca-c2c84d6805be', 'Dumbbell Bench Press', 'push', '{chest,triceps,shoulders}', 'dumbbell');
