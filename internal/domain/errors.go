package domain

import "errors"

var (
	ErrUserNotFound        = errors.New("user not found")
	ErrEmailTaken          = errors.New("email already registered")
	ErrInvalidCredentials  = errors.New("invalid email or password")
	ErrRefreshTokenInvalid = errors.New("refresh token invalid or expired")
	ErrTooManyRequests     = errors.New("too many attempts — wait a few minutes and try again")

	ErrExerciseNotFound     = errors.New("exercise not found")
	ErrExerciseNotOwned     = errors.New("that exercise can't be edited")
	ErrExerciseNameTaken    = errors.New("you already have an exercise with that name")
	ErrExerciseInUse        = errors.New("this exercise is used by a workout or template and can't be deleted")
	ErrInvalidExercise      = errors.New("enter a name, category and equipment for the exercise")
	ErrWorkoutNotFound      = errors.New("workout not found")
	ErrWorkoutNotOwned      = errors.New("workout does not belong to this user")
	ErrWorkoutNotActive     = errors.New("workout is not in progress")
	ErrWorkoutAlreadyActive = errors.New("user already has a workout in progress")
	ErrWorkoutSetNotFound   = errors.New("workout set not found")

	ErrTemplateNotFound = errors.New("workout template not found")
	ErrTemplateNotOwned = errors.New("workout template does not belong to this user")

	ErrFitnessProfileNotFound = errors.New("fitness profile not found")
	ErrProgramNotFound        = errors.New("program not found")
	ErrProgramNotOwned        = errors.New("program does not belong to this user")

	// Input-validation errors. These carry user-facing messages and are
	// passed through to GraphQL clients verbatim by the error presenter,
	// unlike infrastructure errors which are masked.
	ErrInvalidSetValues    = errors.New("reps must be between 1 and 100, and weight between 0 and 1000 kg")
	ErrInvalidRPE          = errors.New("RPE must be between 1 and 10, in steps of 0.5")
	ErrInvalidEmail        = errors.New("enter a valid email address")
	ErrWeakPassword        = errors.New("password must be at least 8 characters")
	ErrEmptyDisplayName    = errors.New("display name cannot be empty")
	ErrInvalidMetricType   = errors.New("unknown body measurement type")
	ErrInvalidMetricValue  = errors.New("measurement value must be between 0 and 1000")
	ErrEmptyTemplateName   = errors.New("template name cannot be empty")
	ErrTemplateNoExercises = errors.New("a template needs at least one exercise")
	ErrNotesTooLong        = errors.New("notes are too long")
)

// userFacingErrors are the sentinels whose messages are safe to send to
// clients as-is. Anything not in this set (pgx errors, driver errors,
// panics, bugs) is masked by the API's error presenter to avoid leaking
// internals like "ERROR: numeric field overflow (SQLSTATE 22003)".
var userFacingErrors = []error{
	ErrUserNotFound, ErrEmailTaken, ErrInvalidCredentials, ErrRefreshTokenInvalid,
	ErrTooManyRequests,
	ErrExerciseNotFound, ErrExerciseNotOwned, ErrExerciseNameTaken, ErrExerciseInUse,
	ErrInvalidExercise,
	ErrWorkoutNotFound, ErrWorkoutNotOwned, ErrWorkoutNotActive,
	ErrWorkoutAlreadyActive, ErrWorkoutSetNotFound,
	ErrTemplateNotFound, ErrTemplateNotOwned,
	ErrFitnessProfileNotFound, ErrProgramNotFound, ErrProgramNotOwned,
	ErrInvalidSetValues, ErrInvalidRPE, ErrInvalidEmail, ErrWeakPassword,
	ErrEmptyDisplayName, ErrInvalidMetricType, ErrInvalidMetricValue,
	ErrEmptyTemplateName, ErrTemplateNoExercises, ErrNotesTooLong,
}

// IsUserFacing reports whether err (or anything it wraps) is a known
// domain error whose message is safe to surface to API clients.
func IsUserFacing(err error) bool {
	for _, known := range userFacingErrors {
		if errors.Is(err, known) {
			return true
		}
	}
	return false
}
