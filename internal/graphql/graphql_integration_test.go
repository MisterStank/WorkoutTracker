package graphql_test

// End-to-end tests that drive the real gqlgen schema over HTTP against a
// real Postgres (see package dbtest), with every service and repository
// wired exactly as cmd/api does. These cover the resolver layer and the
// service→repository seam that the fake-based unit tests in internal/service
// can't reach — notably that auth context and ownership checks actually hold
// when a request comes in over the wire.

import (
	"context"
	"net/http"
	"os"
	"testing"

	"gymon/internal/dbtest"
	"gymon/internal/domain"
	gql "gymon/internal/graphql"
	appmiddleware "gymon/internal/middleware"
	"gymon/internal/ratelimit"
	"gymon/internal/repository"
	"gymon/internal/service"

	"github.com/99designs/gqlgen/client"
	"github.com/99designs/gqlgen/graphql/handler"
	"github.com/99designs/gqlgen/graphql/handler/transport"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMain(m *testing.M) {
	dbtest.Start()
	code := m.Run()
	dbtest.Stop()
	os.Exit(code)
}

// noopEvents satisfies domain.WorkoutEventPublisher without a Redis.
type noopEvents struct{}

func (noopEvents) PublishSetLogged(context.Context, uuid.UUID, *domain.LoggedSet) error { return nil }

func newTestClient(t *testing.T) (*client.Client, *service.TokenIssuer) {
	t.Helper()
	pool := dbtest.Pool(t)

	tokens := service.NewTokenIssuer([]byte("integration-test-secret"))
	limiter := ratelimit.NewMemoryLimiter()

	userRepo := repository.NewUserRepository(pool)
	refreshRepo := repository.NewRefreshTokenRepository(pool)
	authSvc := service.NewAuthService(userRepo, refreshRepo, tokens, limiter)

	rollupRepo := repository.NewProgressRollupRepository(pool)
	bodyRepo := repository.NewBodyMetricRepository(pool)
	analyticsSvc := service.NewAnalyticsService(rollupRepo, bodyRepo, nil) // nil cache = caching disabled

	exRepo := repository.NewExerciseRepository(pool)
	woRepo := repository.NewWorkoutRepository(pool)
	setRepo := repository.NewWorkoutSetRepository(pool)
	prRepo := repository.NewPersonalRecordRepository(pool)
	tmplRepo := repository.NewWorkoutTemplateRepository(pool)
	workoutSvc := service.NewWorkoutService(exRepo, woRepo, setRepo, prRepo, tmplRepo, analyticsSvc, noopEvents{})

	profileRepo := repository.NewFitnessProfileRepository(pool)
	programRepo := repository.NewProgramRepository(pool, tmplRepo)
	programSvc := service.NewProgramService(profileRepo, programRepo, exRepo, workoutSvc)

	resolver := &gql.Resolver{Auth: authSvc, Workout: workoutSvc, Analytics: analyticsSvc, Program: programSvc}

	srv := handler.New(gql.NewExecutableSchema(gql.Config{Resolvers: resolver}))
	srv.AddTransport(transport.POST{})

	// Same middleware chain cmd/api puts in front of /graphql.
	h := appmiddleware.ClientIP(appmiddleware.Auth(tokens)(srv))
	return client.New(http.Handler(h)), tokens
}

func authHeader(token string) client.Option {
	return client.AddHeader("Authorization", "Bearer "+token)
}

func signup(t *testing.T, c *client.Client, email string) (userID, accessToken string) {
	t.Helper()
	var resp struct {
		Signup struct {
			User        struct{ ID string }
			AccessToken string
		}
	}
	err := c.Post(`mutation ($e:String!){ signup(email:$e, password:"correct-horse-staple", displayName:"Tester"){ user{ id } accessToken } }`,
		&resp, client.Var("e", email))
	require.NoError(t, err)
	return resp.Signup.User.ID, resp.Signup.AccessToken
}

func uniqueEmail() string { return "gql-" + uuid.NewString() + "@test.local" }

func TestSignupThenMeReturnsTheSameUser(t *testing.T) {
	c, _ := newTestClient(t)
	email := uniqueEmail()
	userID, token := signup(t, c, email)
	require.NotEmpty(t, token)

	var me struct {
		Me struct {
			ID    string
			Email string
		}
	}
	require.NoError(t, c.Post(`{ me { id email } }`, &me, authHeader(token)))
	assert.Equal(t, userID, me.Me.ID)
	assert.Equal(t, email, me.Me.Email)
}

func TestMeWithoutATokenIsRejected(t *testing.T) {
	c, _ := newTestClient(t)
	var me struct{ Me *struct{ ID string } }
	err := c.Post(`{ me { id } }`, &me)
	require.Error(t, err, "an unauthenticated `me` query must not return a user")
	assert.Nil(t, me.Me)
}

func TestLogSetFlowRecordsAPersonalRecord(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	// pick a seeded exercise
	var exResp struct {
		Exercises []struct {
			ID   string
			Name string
		}
	}
	require.NoError(t, c.Post(`{ exercises(search:"Barbell Bench Press"){ id name } }`, &exResp, authHeader(token)))
	require.NotEmpty(t, exResp.Exercises)
	exID := exResp.Exercises[0].ID

	var startResp struct{ StartWorkout struct{ ID string } }
	require.NoError(t, c.Post(`mutation { startWorkout { id } }`, &startResp, authHeader(token)))
	workoutID := startResp.StartWorkout.ID

	var logResp struct {
		LogSet struct {
			Set        struct{ Reps int }
			NewRecords []struct{ RecordType string }
		}
	}
	err := c.Post(
		`mutation ($w:UUID!, $e:UUID!){ logSet(workoutId:$w, exerciseId:$e, reps:5, weightKg:100){ set{ reps } newRecords{ recordType } } }`,
		&logResp, client.Var("w", workoutID), client.Var("e", exID), authHeader(token))
	require.NoError(t, err)
	assert.Equal(t, 5, logResp.LogSet.Set.Reps)
	assert.NotEmpty(t, logResp.LogSet.NewRecords, "first ever set should be a PR")
}

func TestCannotLogSetIntoAnotherUsersWorkout(t *testing.T) {
	c, _ := newTestClient(t)
	_, aliceToken := signup(t, c, uniqueEmail())
	_, bobToken := signup(t, c, uniqueEmail())

	var startResp struct{ StartWorkout struct{ ID string } }
	require.NoError(t, c.Post(`mutation { startWorkout { id } }`, &startResp, authHeader(aliceToken)))
	aliceWorkout := startResp.StartWorkout.ID

	var exResp struct{ Exercises []struct{ ID string } }
	require.NoError(t, c.Post(`{ exercises(search:"Barbell Back Squat"){ id } }`, &exResp, authHeader(bobToken)))
	require.NotEmpty(t, exResp.Exercises)

	var out struct {
		LogSet *struct {
			Set struct{ Reps int }
		}
	}
	err := c.Post(
		`mutation ($w:UUID!, $e:UUID!){ logSet(workoutId:$w, exerciseId:$e, reps:5, weightKg:60){ set{ reps } } }`,
		&out, client.Var("w", aliceWorkout), client.Var("e", exResp.Exercises[0].ID), authHeader(bobToken))
	require.Error(t, err, "Bob must not be able to log a set into Alice's workout")
	assert.Contains(t, err.Error(), "does not belong")
}

func TestUnauthenticatedMutationIsRejected(t *testing.T) {
	c, _ := newTestClient(t)
	var out struct{ StartWorkout *struct{ ID string } }
	err := c.Post(`mutation { startWorkout { id } }`, &out)
	require.Error(t, err)
}
