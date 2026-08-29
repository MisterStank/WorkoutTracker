package graphql_test

import (
	"testing"

	"github.com/99designs/gqlgen/client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// These exercise the thin auth/mutation resolver wrappers over HTTP — the
// service logic they call is unit-tested in internal/service, but this
// confirms the resolver plumbing (arg parsing, context, error mapping) too.

func TestLoginResolver(t *testing.T) {
	c, _ := newTestClient(t)
	email := uniqueEmail()

	var su struct{ Signup struct{ RefreshToken string } }
	require.NoError(t, c.Post(
		`mutation ($e:String!){ signup(email:$e, password:"correct-horse-staple", displayName:"T"){ refreshToken } }`,
		&su, client.Var("e", email)))

	var login struct {
		Login struct {
			AccessToken string
			User        struct{ Email string }
		}
	}
	require.NoError(t, c.Post(
		`mutation ($e:String!){ login(email:$e, password:"correct-horse-staple"){ accessToken user{ email } } }`,
		&login, client.Var("e", email)))
	assert.NotEmpty(t, login.Login.AccessToken)
	assert.Equal(t, email, login.Login.User.Email)

	// wrong password -> user-facing error
	err := c.Post(`mutation ($e:String!){ login(email:$e, password:"nope"){ accessToken } }`,
		&login, client.Var("e", email))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "invalid email or password")
}

func TestRefreshAndLogoutResolvers(t *testing.T) {
	c, _ := newTestClient(t)
	var su struct{ Signup struct{ RefreshToken string } }
	require.NoError(t, c.Post(
		`mutation ($e:String!){ signup(email:$e, password:"correct-horse-staple", displayName:"T"){ refreshToken } }`,
		&su, client.Var("e", uniqueEmail())))
	rt := su.Signup.RefreshToken

	var refreshed struct {
		RefreshToken struct{ RefreshToken string }
	}
	require.NoError(t, c.Post(`mutation ($r:String!){ refreshToken(refreshToken:$r){ refreshToken } }`,
		&refreshed, client.Var("r", rt)))
	assert.NotEqual(t, rt, refreshed.RefreshToken.RefreshToken, "refresh rotates the token")

	// the rotated token can be logged out
	var out struct{ Logout bool }
	require.NoError(t, c.Post(`mutation ($r:String!){ logout(refreshToken:$r) }`,
		&out, client.Var("r", refreshed.RefreshToken.RefreshToken)))
	assert.True(t, out.Logout)

	// and is then rejected
	err := c.Post(`mutation ($r:String!){ refreshToken(refreshToken:$r){ refreshToken } }`,
		&refreshed, client.Var("r", refreshed.RefreshToken.RefreshToken))
	require.Error(t, err)
}

func TestUpdateAndDeleteSetResolvers(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	var ex struct{ Exercises []struct{ ID string } }
	require.NoError(t, c.Post(`{ exercises(search:"Barbell Bench Press"){ id } }`, &ex, authHeader(token)))
	var start struct{ StartWorkout struct{ ID string } }
	require.NoError(t, c.Post(`mutation { startWorkout { id } }`, &start, authHeader(token)))

	var logged struct {
		LogSet struct {
			Set struct{ ID string }
		}
	}
	require.NoError(t, c.Post(
		`mutation ($w:UUID!,$e:UUID!){ logSet(workoutId:$w, exerciseId:$e, reps:5, weightKg:100){ set{ id } } }`,
		&logged, client.Var("w", start.StartWorkout.ID), client.Var("e", ex.Exercises[0].ID), authHeader(token)))
	setID := logged.LogSet.Set.ID

	var updated struct {
		UpdateSet struct {
			Reps     int
			WeightKg float64
		}
	}
	require.NoError(t, c.Post(
		`mutation ($s:UUID!){ updateSet(setId:$s, reps:8, weightKg:90){ reps weightKg } }`,
		&updated, client.Var("s", setID), authHeader(token)))
	assert.Equal(t, 8, updated.UpdateSet.Reps)
	assert.InDelta(t, 90.0, updated.UpdateSet.WeightKg, 0.001)

	var del struct{ DeleteSet bool }
	require.NoError(t, c.Post(`mutation ($s:UUID!){ deleteSet(setId:$s) }`,
		&del, client.Var("s", setID), authHeader(token)))
	assert.True(t, del.DeleteSet)

	var active struct {
		ActiveWorkout *struct {
			ID string
		}
	}
	require.NoError(t, c.Post(`{ activeWorkout { id } }`, &active, authHeader(token)))
	require.NotNil(t, active.ActiveWorkout)
	assert.Equal(t, start.StartWorkout.ID, active.ActiveWorkout.ID)
}

func TestDeleteWorkoutResolver(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	var start struct{ StartWorkout struct{ ID string } }
	require.NoError(t, c.Post(`mutation { startWorkout { id } }`, &start, authHeader(token)))

	var del struct{ DeleteWorkout bool }
	require.NoError(t, c.Post(`mutation ($w:UUID!){ deleteWorkout(workoutId:$w) }`,
		&del, client.Var("w", start.StartWorkout.ID), authHeader(token)))
	assert.True(t, del.DeleteWorkout)

	var active struct{ ActiveWorkout *struct{ ID string } }
	require.NoError(t, c.Post(`{ activeWorkout { id } }`, &active, authHeader(token)))
	assert.Nil(t, active.ActiveWorkout)
}

func TestProgressQueriesResolvers(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	var ex struct{ Exercises []struct{ ID string } }
	require.NoError(t, c.Post(`{ exercises(search:"Barbell Back Squat"){ id } }`, &ex, authHeader(token)))
	var start struct{ StartWorkout struct{ ID string } }
	require.NoError(t, c.Post(`mutation { startWorkout { id } }`, &start, authHeader(token)))
	require.NoError(t, c.Post(
		`mutation ($w:UUID!,$e:UUID!){ logSet(workoutId:$w, exerciseId:$e, reps:5, weightKg:100){ set{ id } } }`,
		&struct {
			LogSet struct {
				Set struct{ ID string }
			}
		}{}, client.Var("w", start.StartWorkout.ID), client.Var("e", ex.Exercises[0].ID), authHeader(token)))

	var prog struct {
		ProgressOverTime []struct {
			MaxWeight float64
			SetCount  int
		}
	}
	require.NoError(t, c.Post(
		`query ($e:UUID!){ progressOverTime(exerciseId:$e, days:30){ maxWeight setCount } }`,
		&prog, client.Var("e", ex.Exercises[0].ID), authHeader(token)))
	require.Len(t, prog.ProgressOverTime, 1)
	assert.Equal(t, 100.0, prog.ProgressOverTime[0].MaxWeight)

	var vol struct {
		VolumeTrend []struct{ TotalVolume float64 }
	}
	require.NoError(t, c.Post(`{ volumeTrend(days:30){ totalVolume } }`, &vol, authHeader(token)))
	require.Len(t, vol.VolumeTrend, 1)
	assert.InDelta(t, 500.0, vol.VolumeTrend[0].TotalVolume, 0.001)

	var last struct {
		LastSetForExercise *struct{ Reps int }
	}
	require.NoError(t, c.Post(
		`query ($e:UUID!){ lastSetForExercise(exerciseId:$e){ reps } }`,
		&last, client.Var("e", ex.Exercises[0].ID), authHeader(token)))
	require.NotNil(t, last.LastSetForExercise)
	assert.Equal(t, 5, last.LastSetForExercise.Reps)
}
