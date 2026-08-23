package graphql

// THIS CODE WILL BE UPDATED WITH SCHEMA CHANGES. PREVIOUS IMPLEMENTATION FOR SCHEMA CHANGES WILL BE KEPT IN THE COMMENT SECTION. IMPLEMENTATION FOR UNCHANGED SCHEMA WILL BE KEPT.

import (
	"context"

	"workouttracker/internal/domain"
	appmiddleware "workouttracker/internal/middleware"
	"workouttracker/internal/realtime"
	"workouttracker/internal/service"

	"github.com/google/uuid"
)

// Resolver is the composition root for GraphQL: it holds only the service
// dependencies and translates GraphQL <-> service calls. No business logic
// or SQL lives here (Single Responsibility) — that belongs in internal/service.
type Resolver struct {
	Auth      *service.AuthService
	Workout   *service.WorkoutService
	Analytics *service.AnalyticsService
	Events    *realtime.RedisEventBus
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

func toExerciseModel(e *domain.Exercise) *Exercise {
	return &Exercise{
		ID:           e.ID,
		Name:         e.Name,
		Category:     e.Category,
		MuscleGroups: e.MuscleGroups,
		Equipment:    e.Equipment,
		IsCustom:     e.IsCustom,
	}
}

func toWorkoutSetModel(s *domain.WorkoutSet) *WorkoutSet {
	if s == nil {
		return nil
	}
	return &WorkoutSet{
		ID:          s.ID,
		ExerciseID:  s.ExerciseID,
		SetNumber:   s.SetNumber,
		Reps:        s.Reps,
		WeightKg:    s.WeightKg,
		Rpe:         s.RPE,
		IsWarmup:    s.IsWarmup,
		PerformedAt: s.PerformedAt,
	}
}

func toWorkoutSetModels(sets []*domain.WorkoutSet) []*WorkoutSet {
	out := make([]*WorkoutSet, len(sets))
	for i, s := range sets {
		out[i] = toWorkoutSetModel(s)
	}
	return out
}

func toWorkoutStatus(s domain.WorkoutStatus) WorkoutStatus {
	if s == domain.WorkoutCompleted {
		return WorkoutStatusCompleted
	}
	return WorkoutStatusInProgress
}

func toPersonalRecordModel(pr *domain.PersonalRecord) *PersonalRecord {
	return &PersonalRecord{
		ID:           pr.ID,
		ExerciseID:   pr.ExerciseID,
		RecordType:   pr.RecordType,
		Value:        pr.Value,
		AchievedAt:   pr.AchievedAt,
		WorkoutSetID: pr.WorkoutSetID,
	}
}

func toLogSetResult(logged *domain.LoggedSet) *LogSetResult {
	newRecords := make([]*PersonalRecord, len(logged.NewRecords))
	for i, pr := range logged.NewRecords {
		newRecords[i] = toPersonalRecordModel(pr)
	}
	return &LogSetResult{Set: toWorkoutSetModel(logged.Set), NewRecords: newRecords}
}

func toProgressPointModel(p *domain.ProgressPoint) *ProgressPoint {
	return &ProgressPoint{
		Day:         p.Day,
		TotalVolume: p.TotalVolume,
		MaxWeight:   p.MaxWeight,
		SetCount:    p.SetCount,
	}
}

func toBodyMetricModel(m *domain.BodyMetric) *BodyMetric {
	return &BodyMetric{
		ID:         m.ID,
		MetricType: m.MetricType,
		Value:      m.Value,
		RecordedAt: m.RecordedAt,
	}
}

// toWorkoutModel fetches the workout's sets to populate the nested field.
// This is a known N+1 spot if a query fans out over many workouts at once
// (e.g. workoutHistory); acceptable for now since history is paginated to
// a small page size, but a dataloader would be the fix if that changes.
func (r *Resolver) toWorkoutModel(ctx context.Context, userID uuid.UUID, w *domain.Workout) (*Workout, error) {
	sets, err := r.Workout.SetsForWorkout(ctx, userID, w.ID)
	if err != nil {
		return nil, err
	}
	return &Workout{
		ID:        w.ID,
		StartedAt: w.StartedAt,
		EndedAt:   w.EndedAt,
		Notes:     w.Notes,
		Status:    toWorkoutStatus(w.Status),
		Sets:      toWorkoutSetModels(sets),
	}, nil
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

// StartWorkout is the resolver for the startWorkout field.
func (r *mutationResolver) StartWorkout(ctx context.Context) (*Workout, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	w, err := r.Workout.StartWorkout(ctx, userID)
	if err != nil {
		return nil, err
	}
	return r.toWorkoutModel(ctx, userID, w)
}

// LogSet is the resolver for the logSet field.
func (r *mutationResolver) LogSet(ctx context.Context, workoutID uuid.UUID, exerciseID uuid.UUID, reps int, weightKg float64, rpe *float64, isWarmup *bool) (*LogSetResult, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	warmup := isWarmup != nil && *isWarmup
	logged, err := r.Workout.LogSet(ctx, userID, workoutID, exerciseID, reps, weightKg, rpe, warmup)
	if err != nil {
		return nil, err
	}
	return toLogSetResult(logged), nil
}

// FinishWorkout is the resolver for the finishWorkout field.
func (r *mutationResolver) FinishWorkout(ctx context.Context, workoutID uuid.UUID, notes *string) (*Workout, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	notesVal := ""
	if notes != nil {
		notesVal = *notes
	}
	w, err := r.Workout.FinishWorkout(ctx, userID, workoutID, notesVal)
	if err != nil {
		return nil, err
	}
	return r.toWorkoutModel(ctx, userID, w)
}

// LogBodyMetric is the resolver for the logBodyMetric field.
func (r *mutationResolver) LogBodyMetric(ctx context.Context, metricType string, value float64) (*BodyMetric, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	m, err := r.Analytics.LogBodyMetric(ctx, userID, metricType, value)
	if err != nil {
		return nil, err
	}
	return toBodyMetricModel(m), nil
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

// Exercises is the resolver for the exercises field.
func (r *queryResolver) Exercises(ctx context.Context, search *string) ([]*Exercise, error) {
	searchVal := ""
	if search != nil {
		searchVal = *search
	}
	exercises, err := r.Workout.ListExercises(ctx, searchVal)
	if err != nil {
		return nil, err
	}
	out := make([]*Exercise, len(exercises))
	for i, e := range exercises {
		out[i] = toExerciseModel(e)
	}
	return out, nil
}

// ActiveWorkout is the resolver for the activeWorkout field.
func (r *queryResolver) ActiveWorkout(ctx context.Context) (*Workout, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	w, err := r.Workout.ActiveWorkout(ctx, userID)
	if err != nil {
		return nil, err
	}
	if w == nil {
		return nil, nil
	}
	return r.toWorkoutModel(ctx, userID, w)
}

// WorkoutHistory is the resolver for the workoutHistory field.
func (r *queryResolver) WorkoutHistory(ctx context.Context, first int, after *string) (*WorkoutConnection, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	afterVal := ""
	if after != nil {
		afterVal = *after
	}
	page, err := r.Workout.WorkoutHistory(ctx, userID, first, afterVal)
	if err != nil {
		return nil, err
	}

	edges := make([]*WorkoutEdge, len(page.Workouts))
	for i, w := range page.Workouts {
		node, err := r.toWorkoutModel(ctx, userID, w)
		if err != nil {
			return nil, err
		}
		edges[i] = &WorkoutEdge{Cursor: service.EncodeWorkoutCursor(w), Node: node}
	}

	var endCursor *string
	if page.EndCursor != "" {
		endCursor = &page.EndCursor
	}

	return &WorkoutConnection{
		Edges:    edges,
		PageInfo: &PageInfo{HasNextPage: page.HasMore, EndCursor: endCursor},
	}, nil
}

// PersonalRecords is the resolver for the personalRecords field.
func (r *queryResolver) PersonalRecords(ctx context.Context) ([]*PersonalRecord, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	records, err := r.Workout.PersonalRecords(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]*PersonalRecord, len(records))
	for i, pr := range records {
		out[i] = toPersonalRecordModel(pr)
	}
	return out, nil
}

// LastSetForExercise is the resolver for the lastSetForExercise field.
func (r *queryResolver) LastSetForExercise(ctx context.Context, exerciseID uuid.UUID) (*WorkoutSet, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	set, err := r.Workout.LastSetForExercise(ctx, userID, exerciseID)
	if err != nil {
		return nil, err
	}
	return toWorkoutSetModel(set), nil
}

// ProgressOverTime is the resolver for the progressOverTime field.
func (r *queryResolver) ProgressOverTime(ctx context.Context, exerciseID uuid.UUID, days int) ([]*ProgressPoint, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	points, err := r.Analytics.ProgressOverTime(ctx, userID, exerciseID, days)
	if err != nil {
		return nil, err
	}
	out := make([]*ProgressPoint, len(points))
	for i, p := range points {
		out[i] = toProgressPointModel(p)
	}
	return out, nil
}

// VolumeTrend is the resolver for the volumeTrend field.
func (r *queryResolver) VolumeTrend(ctx context.Context, days int) ([]*ProgressPoint, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	points, err := r.Analytics.VolumeTrend(ctx, userID, days)
	if err != nil {
		return nil, err
	}
	out := make([]*ProgressPoint, len(points))
	for i, p := range points {
		out[i] = toProgressPointModel(p)
	}
	return out, nil
}

// BodyMetrics is the resolver for the bodyMetrics field.
func (r *queryResolver) BodyMetrics(ctx context.Context, metricType string, days int) ([]*BodyMetric, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	metrics, err := r.Analytics.BodyMetrics(ctx, userID, metricType, days)
	if err != nil {
		return nil, err
	}
	out := make([]*BodyMetric, len(metrics))
	for i, m := range metrics {
		out[i] = toBodyMetricModel(m)
	}
	return out, nil
}

// WorkoutProgressUpdated is the resolver for the workoutProgressUpdated field.
func (r *subscriptionResolver) WorkoutProgressUpdated(ctx context.Context, workoutID uuid.UUID) (<-chan *LogSetResult, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	// Verify the caller owns this workout before subscribing — SetsForWorkout
	// does the same ownership check WorkoutService already applies elsewhere.
	if _, err := r.Workout.SetsForWorkout(ctx, userID, workoutID); err != nil {
		return nil, err
	}

	events, cleanup, err := r.Events.Subscribe(ctx, workoutID)
	if err != nil {
		return nil, err
	}

	out := make(chan *LogSetResult)
	go func() {
		defer close(out)
		defer cleanup()
		for {
			select {
			case logged, ok := <-events:
				if !ok {
					return
				}
				select {
				case out <- toLogSetResult(logged):
				case <-ctx.Done():
					return
				}
			case <-ctx.Done():
				return
			}
		}
	}()

	return out, nil
}

// Mutation returns MutationResolver implementation.
func (r *Resolver) Mutation() MutationResolver { return &mutationResolver{r} }

// Query returns QueryResolver implementation.
func (r *Resolver) Query() QueryResolver { return &queryResolver{r} }

// Subscription returns SubscriptionResolver implementation.
func (r *Resolver) Subscription() SubscriptionResolver { return &subscriptionResolver{r} }

type (
	mutationResolver     struct{ *Resolver }
	queryResolver        struct{ *Resolver }
	subscriptionResolver struct{ *Resolver }
)

// !!! WARNING !!!
// The code below was going to be deleted when updating resolvers. It has been copied here so you have
// one last chance to move it out of harms way if you want. There are two reasons this happens:
//  - When renaming or deleting a resolver the old code will be put in here. You can safely delete
//    it when you're done.
//  - You have helper methods in this file. Move them out to keep these resolver files clean.
/*
	type Resolver struct {
	Auth      *service.AuthService
	Workout   *service.WorkoutService
	Analytics *service.AnalyticsService
	Events    *realtime.RedisEventBus
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
func toExerciseModel(e *domain.Exercise) *Exercise {
	return &Exercise{
		ID:           e.ID,
		Name:         e.Name,
		Category:     e.Category,
		MuscleGroups: e.MuscleGroups,
		Equipment:    e.Equipment,
		IsCustom:     e.IsCustom,
	}
}
func toWorkoutSetModel(s *domain.WorkoutSet) *WorkoutSet {
	return &WorkoutSet{
		ID:          s.ID,
		ExerciseID:  s.ExerciseID,
		SetNumber:   s.SetNumber,
		Reps:        s.Reps,
		WeightKg:    s.WeightKg,
		Rpe:         s.RPE,
		PerformedAt: s.PerformedAt,
	}
}
func toWorkoutSetModels(sets []*domain.WorkoutSet) []*WorkoutSet {
	out := make([]*WorkoutSet, len(sets))
	for i, s := range sets {
		out[i] = toWorkoutSetModel(s)
	}
	return out
}
func toWorkoutStatus(s domain.WorkoutStatus) WorkoutStatus {
	if s == domain.WorkoutCompleted {
		return WorkoutStatusCompleted
	}
	return WorkoutStatusInProgress
}
func toPersonalRecordModel(pr *domain.PersonalRecord) *PersonalRecord {
	return &PersonalRecord{
		ID:           pr.ID,
		ExerciseID:   pr.ExerciseID,
		RecordType:   pr.RecordType,
		Value:        pr.Value,
		AchievedAt:   pr.AchievedAt,
		WorkoutSetID: pr.WorkoutSetID,
	}
}
func toLogSetResult(logged *domain.LoggedSet) *LogSetResult {
	newRecords := make([]*PersonalRecord, len(logged.NewRecords))
	for i, pr := range logged.NewRecords {
		newRecords[i] = toPersonalRecordModel(pr)
	}
	return &LogSetResult{Set: toWorkoutSetModel(logged.Set), NewRecords: newRecords}
}
func toProgressPointModel(p *domain.ProgressPoint) *ProgressPoint {
	return &ProgressPoint{
		Day:         p.Day,
		TotalVolume: p.TotalVolume,
		MaxWeight:   p.MaxWeight,
		SetCount:    p.SetCount,
	}
}
func toBodyMetricModel(m *domain.BodyMetric) *BodyMetric {
	return &BodyMetric{
		ID:         m.ID,
		MetricType: m.MetricType,
		Value:      m.Value,
		RecordedAt: m.RecordedAt,
	}
}
func (r *Resolver) toWorkoutModel(ctx context.Context, userID uuid.UUID, w *domain.Workout) (*Workout, error) {
	sets, err := r.Workout.SetsForWorkout(ctx, userID, w.ID)
	if err != nil {
		return nil, err
	}
	return &Workout{
		ID:        w.ID,
		StartedAt: w.StartedAt,
		EndedAt:   w.EndedAt,
		Notes:     w.Notes,
		Status:    toWorkoutStatus(w.Status),
		Sets:      toWorkoutSetModels(sets),
	}, nil
}
*/
