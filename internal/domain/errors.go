package domain

import "errors"

var (
	ErrUserNotFound        = errors.New("user not found")
	ErrEmailTaken          = errors.New("email already registered")
	ErrInvalidCredentials  = errors.New("invalid email or password")
	ErrRefreshTokenInvalid = errors.New("refresh token invalid or expired")

	ErrExerciseNotFound     = errors.New("exercise not found")
	ErrWorkoutNotFound      = errors.New("workout not found")
	ErrWorkoutNotOwned      = errors.New("workout does not belong to this user")
	ErrWorkoutNotActive     = errors.New("workout is not in progress")
	ErrWorkoutAlreadyActive = errors.New("user already has a workout in progress")
	ErrWorkoutSetNotFound   = errors.New("workout set not found")

	ErrTemplateNotFound = errors.New("workout template not found")
	ErrTemplateNotOwned = errors.New("workout template does not belong to this user")
)
