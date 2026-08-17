package domain

import "errors"

var (
	ErrUserNotFound        = errors.New("user not found")
	ErrEmailTaken          = errors.New("email already registered")
	ErrInvalidCredentials  = errors.New("invalid email or password")
	ErrRefreshTokenInvalid = errors.New("refresh token invalid or expired")
)
