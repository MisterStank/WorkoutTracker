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

type Resolver struct {
	Auth      *service.AuthService
	Workout   *service.WorkoutService
	Analytics *service.AnalyticsService
	Program   *service.ProgramService
	Events    *realtime.RedisEventBus
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
func (r *mutationResolver) StartWorkout(ctx context.Context, templateID *uuid.UUID) (*Workout, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	w, err := r.Workout.StartWorkout(ctx, userID, templateID)
	if err != nil {
		return nil, err
	}
	return r.toWorkoutModel(ctx, userID, w)
}

// LogSet is the resolver for the logSet field.
func (r *mutationResolver) LogSet(ctx context.Context, workoutID uuid.UUID, exerciseID uuid.UUID, reps int, weightKg float64, rpe *float64, setType *SetType, supersetID *uuid.UUID) (*LogSetResult, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	domainSetType := domain.SetTypeNormal
	if setType != nil {
		if mapped, ok := graphqlToDomainSetType[*setType]; ok {
			domainSetType = mapped
		}
	}
	logged, err := r.Workout.LogSet(ctx, userID, workoutID, exerciseID, reps, weightKg, rpe, domainSetType, supersetID)
	if err != nil {
		return nil, err
	}
	return toLogSetResult(logged), nil
}

// UpdateSet is the resolver for the updateSet field.
func (r *mutationResolver) UpdateSet(ctx context.Context, setID uuid.UUID, reps int, weightKg float64, rpe *float64, setType *SetType) (*WorkoutSet, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	domainSetType := domain.SetTypeNormal
	if setType != nil {
		if mapped, ok := graphqlToDomainSetType[*setType]; ok {
			domainSetType = mapped
		}
	}
	set, err := r.Workout.UpdateSet(ctx, userID, setID, reps, weightKg, rpe, domainSetType)
	if err != nil {
		return nil, err
	}
	return toWorkoutSetModel(set), nil
}

// DeleteSet is the resolver for the deleteSet field.
func (r *mutationResolver) DeleteSet(ctx context.Context, setID uuid.UUID) (bool, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return false, domain.ErrInvalidCredentials
	}
	if err := r.Workout.DeleteSet(ctx, userID, setID); err != nil {
		return false, err
	}
	return true, nil
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

// DeleteWorkout is the resolver for the deleteWorkout field.
func (r *mutationResolver) DeleteWorkout(ctx context.Context, workoutID uuid.UUID) (bool, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return false, domain.ErrInvalidCredentials
	}
	if err := r.Workout.DeleteWorkout(ctx, userID, workoutID); err != nil {
		return false, err
	}
	return true, nil
}

// CreateWorkoutTemplate is the resolver for the createWorkoutTemplate field.
func (r *mutationResolver) CreateWorkoutTemplate(ctx context.Context, name string, exercises []*TemplateExerciseInput) (*WorkoutTemplate, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	domainExercises := make([]*domain.TemplateExercise, len(exercises))
	for i, e := range exercises {
		domainExercises[i] = &domain.TemplateExercise{
			ExerciseID:    e.ExerciseID,
			TargetSets:    e.TargetSets,
			TargetReps:    e.TargetReps,
			SupersetGroup: e.SupersetGroup,
		}
	}
	t, err := r.Workout.CreateTemplate(ctx, userID, name, domainExercises)
	if err != nil {
		return nil, err
	}
	return toWorkoutTemplateModel(t), nil
}

// DeleteWorkoutTemplate is the resolver for the deleteWorkoutTemplate field.
func (r *mutationResolver) DeleteWorkoutTemplate(ctx context.Context, templateID uuid.UUID) (bool, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return false, domain.ErrInvalidCredentials
	}
	if err := r.Workout.DeleteTemplate(ctx, userID, templateID); err != nil {
		return false, err
	}
	return true, nil
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

// SaveFitnessProfile is the resolver for the saveFitnessProfile field.
func (r *mutationResolver) SaveFitnessProfile(ctx context.Context, input FitnessProfileInput) (*UserFitnessProfile, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	goal := graphqlToDomainGoal[input.Goal]
	experience := graphqlToDomainExperience[input.ExperienceLevel]
	profile, err := r.Program.SaveFitnessProfile(ctx, userID, domain.UserFitnessProfile{
		Goal:              goal,
		ExperienceLevel:   experience,
		DaysPerWeek:       input.DaysPerWeek,
		EquipmentAccess:   input.EquipmentAccess,
		AvoidMuscleGroups: input.AvoidMuscleGroups,
	})
	if err != nil {
		return nil, err
	}
	return toFitnessProfileModel(profile), nil
}

// GenerateProgram is the resolver for the generateProgram field.
func (r *mutationResolver) GenerateProgram(ctx context.Context) (*Program, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	program, err := r.Program.GenerateProgram(ctx, userID)
	if err != nil {
		return nil, err
	}
	return toProgramModel(program), nil
}

// CreateProgramFromTemplates is the resolver for the createProgramFromTemplates field.
func (r *mutationResolver) CreateProgramFromTemplates(ctx context.Context, input CreateProgramInput) (*Program, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	days := make([]service.DayInput, len(input.Days))
	for i, d := range input.Days {
		days[i] = service.DayInput{DayLabel: d.DayLabel, TemplateID: d.TemplateID}
	}
	program, err := r.Program.CreateFromTemplates(ctx, userID, input.Name, days)
	if err != nil {
		return nil, err
	}
	return toProgramModel(program), nil
}

// SetActiveProgram is the resolver for the setActiveProgram field.
func (r *mutationResolver) SetActiveProgram(ctx context.Context, programID uuid.UUID) (*Program, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	program, err := r.Program.SetActiveProgram(ctx, userID, programID)
	if err != nil {
		return nil, err
	}
	return toProgramModel(program), nil
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

// WorkoutTemplates is the resolver for the workoutTemplates field.
func (r *queryResolver) WorkoutTemplates(ctx context.Context) ([]*WorkoutTemplate, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	templates, err := r.Workout.ListTemplates(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]*WorkoutTemplate, len(templates))
	for i, t := range templates {
		out[i] = toWorkoutTemplateModel(t)
	}
	return out, nil
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

// ProgressionSuggestion is the resolver for the progressionSuggestion field.
func (r *queryResolver) ProgressionSuggestion(ctx context.Context, exerciseID uuid.UUID) (*ProgressionSuggestion, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	suggestion, err := r.Workout.SuggestNextSet(ctx, userID, exerciseID)
	if err != nil {
		return nil, err
	}
	return toProgressionSuggestionModel(suggestion), nil
}

// PlateauStatus is the resolver for the plateauStatus field.
func (r *queryResolver) PlateauStatus(ctx context.Context, exerciseID uuid.UUID) (*PlateauStatus, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	status, err := r.Analytics.DetectPlateau(ctx, userID, exerciseID)
	if err != nil {
		return nil, err
	}
	return toPlateauStatusModel(status), nil
}

// MyFitnessProfile is the resolver for the myFitnessProfile field.
func (r *queryResolver) MyFitnessProfile(ctx context.Context) (*UserFitnessProfile, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	profile, err := r.Program.MyFitnessProfile(ctx, userID)
	if err != nil {
		return nil, err
	}
	return toFitnessProfileModel(profile), nil
}

// MyPrograms is the resolver for the myPrograms field.
func (r *queryResolver) MyPrograms(ctx context.Context) ([]*Program, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	programs, err := r.Program.MyPrograms(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]*Program, len(programs))
	for i, p := range programs {
		out[i] = toProgramModel(p)
	}
	return out, nil
}

// NextWorkout is the resolver for the nextWorkout field.
func (r *queryResolver) NextWorkout(ctx context.Context) (*NextWorkout, error) {
	userID, ok := appmiddleware.FromContext(ctx)
	if !ok {
		return nil, domain.ErrInvalidCredentials
	}
	nw, err := r.Program.NextWorkout(ctx, userID)
	if err != nil {
		return nil, err
	}
	if nw == nil {
		return nil, nil
	}
	return &NextWorkout{
		Program: toProgramModel(nw.Program),
		Day:     toProgramDayModel(nw.Day),
	}, nil
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
	return r.streamWorkoutEvents(ctx, workoutID)
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
		Instructions: e.Instructions,
	}
}

var domainToGraphQLSetType = map[domain.SetType]SetType{
	domain.SetTypeNormal:  SetTypeNormal,
	domain.SetTypeWarmup:  SetTypeWarmup,
	domain.SetTypeDropset: SetTypeDropset,
	domain.SetTypeFailure: SetTypeFailure,
}
var graphqlToDomainSetType = map[SetType]domain.SetType{
	SetTypeNormal:  domain.SetTypeNormal,
	SetTypeWarmup:  domain.SetTypeWarmup,
	SetTypeDropset: domain.SetTypeDropset,
	SetTypeFailure: domain.SetTypeFailure,
}
var domainToGraphQLGoal = map[domain.Goal]FitnessGoal{
	domain.GoalStrength:       FitnessGoalStrength,
	domain.GoalHypertrophy:    FitnessGoalHypertrophy,
	domain.GoalFatLoss:        FitnessGoalFatLoss,
	domain.GoalGeneralFitness: FitnessGoalGeneralFitness,
}
var graphqlToDomainGoal = map[FitnessGoal]domain.Goal{
	FitnessGoalStrength:       domain.GoalStrength,
	FitnessGoalHypertrophy:    domain.GoalHypertrophy,
	FitnessGoalFatLoss:        domain.GoalFatLoss,
	FitnessGoalGeneralFitness: domain.GoalGeneralFitness,
}
var graphqlToDomainExperience = map[ExperienceLevel]domain.ExperienceLevel{
	ExperienceLevelBeginner:     domain.ExperienceBeginner,
	ExperienceLevelIntermediate: domain.ExperienceIntermediate,
	ExperienceLevelAdvanced:     domain.ExperienceAdvanced,
}
var domainToGraphQLExperience = map[domain.ExperienceLevel]ExperienceLevel{
	domain.ExperienceBeginner:     ExperienceLevelBeginner,
	domain.ExperienceIntermediate: ExperienceLevelIntermediate,
	domain.ExperienceAdvanced:     ExperienceLevelAdvanced,
}

func toWorkoutSetModel(s *domain.WorkoutSet) *WorkoutSet {
	if s == nil {
		return nil
	}
	setType, ok := domainToGraphQLSetType[s.SetType]
	if !ok {
		setType = SetTypeNormal
	}
	return &WorkoutSet{
		ID:          s.ID,
		ExerciseID:  s.ExerciseID,
		SetNumber:   s.SetNumber,
		Reps:        s.Reps,
		WeightKg:    s.WeightKg,
		Rpe:         s.RPE,
		SetType:     setType,
		SupersetID:  s.SupersetID,
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
func toTemplateExerciseModel(e *domain.TemplateExercise) *TemplateExercise {
	return &TemplateExercise{
		ID:            e.ID,
		ExerciseID:    e.ExerciseID,
		Position:      e.Position,
		TargetSets:    e.TargetSets,
		TargetReps:    e.TargetReps,
		SupersetGroup: e.SupersetGroup,
	}
}
func toWorkoutTemplateModel(t *domain.WorkoutTemplate) *WorkoutTemplate {
	exercises := make([]*TemplateExercise, len(t.Exercises))
	for i, e := range t.Exercises {
		exercises[i] = toTemplateExerciseModel(e)
	}
	return &WorkoutTemplate{
		ID:        t.ID,
		Name:      t.Name,
		CreatedAt: t.CreatedAt,
		Exercises: exercises,
	}
}
func toProgressionSuggestionModel(s *service.ProgressionSuggestion) *ProgressionSuggestion {
	if s == nil {
		return nil
	}
	return &ProgressionSuggestion{
		SuggestedWeightKg: s.SuggestedWeightKg,
		SuggestedReps:     s.SuggestedReps,
		Reasoning:         s.Reasoning,
		BasedOnRpe:        s.BasedOnRPE,
	}
}
func toPlateauStatusModel(s *service.PlateauStatus) *PlateauStatus {
	return &PlateauStatus{
		IsPlateaued:   s.IsPlateaued,
		CurrentBestKg: s.CurrentBestKg,
		Message:       s.Message,
	}
}
func toFitnessProfileModel(p *domain.UserFitnessProfile) *UserFitnessProfile {
	if p == nil {
		return nil
	}
	goal, ok := domainToGraphQLGoal[p.Goal]
	if !ok {
		goal = FitnessGoalGeneralFitness
	}
	experience, ok := domainToGraphQLExperience[p.ExperienceLevel]
	if !ok {
		experience = ExperienceLevelBeginner
	}
	return &UserFitnessProfile{
		Goal:              goal,
		ExperienceLevel:   experience,
		DaysPerWeek:       p.DaysPerWeek,
		EquipmentAccess:   p.EquipmentAccess,
		AvoidMuscleGroups: p.AvoidMuscleGroups,
		UpdatedAt:         p.UpdatedAt,
	}
}
func toProgramDayModel(d *domain.ProgramDay) *ProgramDay {
	return &ProgramDay{
		ID:       d.ID,
		DayLabel: d.DayLabel,
		Position: d.Position,
		Template: toWorkoutTemplateModel(d.Template),
	}
}
func toProgramModel(p *domain.Program) *Program {
	goal, ok := domainToGraphQLGoal[p.Goal]
	if !ok {
		goal = FitnessGoalGeneralFitness
	}
	days := make([]*ProgramDay, len(p.Days))
	for i, d := range p.Days {
		days[i] = toProgramDayModel(d)
	}
	return &Program{
		ID:          p.ID,
		Name:        p.Name,
		Goal:        goal,
		DaysPerWeek: p.DaysPerWeek,
		Notes:       p.Notes,
		CreatedAt:   p.CreatedAt,
		Days:        days,
		IsActive:    p.IsActive,
	}
}
func (r *Resolver) toWorkoutModel(ctx context.Context, userID uuid.UUID, w *domain.Workout) (*Workout, error) {
	sets, err := r.Workout.SetsForWorkout(ctx, userID, w.ID)
	if err != nil {
		return nil, err
	}
	return &Workout{
		ID:         w.ID,
		StartedAt:  w.StartedAt,
		EndedAt:    w.EndedAt,
		Notes:      w.Notes,
		Status:     toWorkoutStatus(w.Status),
		Sets:       toWorkoutSetModels(sets),
		TemplateID: w.TemplateID,
	}, nil
}
func (r *Resolver) streamWorkoutEvents(ctx context.Context, workoutID uuid.UUID) (<-chan *LogSetResult, error) {
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
