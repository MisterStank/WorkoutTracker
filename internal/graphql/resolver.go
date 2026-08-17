package graphql

// THIS CODE WILL BE UPDATED WITH SCHEMA CHANGES. PREVIOUS IMPLEMENTATION FOR SCHEMA CHANGES WILL BE KEPT IN THE COMMENT SECTION. IMPLEMENTATION FOR UNCHANGED SCHEMA WILL BE KEPT.

import (
	"context"

	"workouttracker/internal/domain"
	appmiddleware "workouttracker/internal/middleware"
	"workouttracker/internal/service"
)

// Resolver is the composition root for GraphQL: it holds only the service
// dependencies and translates GraphQL <-> service calls. No business logic
// or SQL lives here (Single Responsibility) — that belongs in internal/service.
type Resolver struct {
	Auth *service.AuthService
}

func toUserModel(u *domain.User) *User {
	if u == nil {
		return nil
	}
	return &User{
		ID:          u.ID,
		Email:       u.Email,
		DisplayName: u.DisplayName,
		Timezone:    u.Timezone,
		CreatedAt:   u.CreatedAt,
	}
}

func toAuthPayload(res *service.AuthResult) *AuthPayload {
	return &AuthPayload{
		User:         toUserModel(res.User),
		AccessToken:  res.AccessToken,
		RefreshToken: res.RefreshToken,
	}
}

// Signup is the resolver for the signup field.
func (r *mutationResolver) Signup(ctx context.Context, email string, password string, displayName string) (*AuthPayload, error) {
	res, err := r.Auth.SignUp(ctx, email, password, displayName)
	if err != nil {
		return nil, err
	}
	return toAuthPayload(res), nil
}

// Login is the resolver for the login field.
func (r *mutationResolver) Login(ctx context.Context, email string, password string) (*AuthPayload, error) {
	res, err := r.Auth.Login(ctx, email, password)
	if err != nil {
		return nil, err
	}
	return toAuthPayload(res), nil
}

// RefreshToken is the resolver for the refreshToken field.
func (r *mutationResolver) RefreshToken(ctx context.Context, refreshToken string) (*AuthPayload, error) {
	res, err := r.Auth.Refresh(ctx, refreshToken)
	if err != nil {
		return nil, err
	}
	return toAuthPayload(res), nil
}

// Logout is the resolver for the logout field.
func (r *mutationResolver) Logout(ctx context.Context, refreshToken string) (bool, error) {
	if err := r.Auth.Logout(ctx, refreshToken); err != nil {
		return false, err
	}
	return true, nil
}

// Me is the resolver for the me field.
func (r *queryResolver) Me(ctx context.Context) (*User, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	u, err := r.Auth.UserByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	return toUserModel(u), nil
}

// Mutation returns MutationResolver implementation.
func (r *Resolver) Mutation() MutationResolver { return &mutationResolver{r} }

// Query returns QueryResolver implementation.
func (r *Resolver) Query() QueryResolver { return &queryResolver{r} }

type (
	mutationResolver struct{ *Resolver }
	queryResolver    struct{ *Resolver }
)
