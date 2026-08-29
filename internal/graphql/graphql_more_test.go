package graphql_test

import (
	"testing"

	"github.com/99designs/gqlgen/client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTemplateLifecycleThroughTheAPI(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	var ex struct{ Exercises []struct{ ID string } }
	require.NoError(t, c.Post(`{ exercises(search:"Barbell Bench Press"){ id } }`, &ex, authHeader(token)))
	require.NotEmpty(t, ex.Exercises)
	exID := ex.Exercises[0].ID

	var created struct {
		CreateWorkoutTemplate struct {
			ID        string
			Name      string
			Exercises []struct{ TargetSets int }
		}
	}
	err := c.Post(
		`mutation ($e:UUID!){ createWorkoutTemplate(name:"Test Day", exercises:[{exerciseId:$e, targetSets:4, targetReps:8}]){ id name exercises{ targetSets } } }`,
		&created, client.Var("e", exID), authHeader(token))
	require.NoError(t, err)
	assert.Equal(t, "Test Day", created.CreateWorkoutTemplate.Name)
	require.Len(t, created.CreateWorkoutTemplate.Exercises, 1)
	assert.Equal(t, 4, created.CreateWorkoutTemplate.Exercises[0].TargetSets)

	var list struct {
		WorkoutTemplates []struct {
			ID   string
			Name string
		}
	}
	require.NoError(t, c.Post(`{ workoutTemplates { id name } }`, &list, authHeader(token)))
	require.Len(t, list.WorkoutTemplates, 1)

	var del struct{ DeleteWorkoutTemplate bool }
	require.NoError(t, c.Post(`mutation ($t:UUID!){ deleteWorkoutTemplate(templateId:$t) }`,
		&del, client.Var("t", created.CreateWorkoutTemplate.ID), authHeader(token)))
	assert.True(t, del.DeleteWorkoutTemplate)

	require.NoError(t, c.Post(`{ workoutTemplates { id } }`, &list, authHeader(token)))
	assert.Empty(t, list.WorkoutTemplates)
}

func TestBodyMetricsRoundTripThroughTheAPI(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	var logged struct {
		LogBodyMetric struct {
			MetricType string
			Value      float64
		}
	}
	require.NoError(t, c.Post(
		`mutation { logBodyMetric(metricType:"bodyweight_kg", value:81.5){ metricType value } }`,
		&logged, authHeader(token)))
	assert.Equal(t, "bodyweight_kg", logged.LogBodyMetric.MetricType)
	assert.InDelta(t, 81.5, logged.LogBodyMetric.Value, 0.001)

	var read struct {
		BodyMetrics []struct{ Value float64 }
	}
	require.NoError(t, c.Post(
		`{ bodyMetrics(metricType:"bodyweight_kg", days:30){ value } }`,
		&read, authHeader(token)))
	require.Len(t, read.BodyMetrics, 1)
	assert.InDelta(t, 81.5, read.BodyMetrics[0].Value, 0.001)
}

func TestInvalidBodyMetricIsRejectedWithAUserFacingMessage(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	var out struct{ LogBodyMetric *struct{ Value float64 } }
	err := c.Post(`mutation { logBodyMetric(metricType:"not_a_real_type", value:10){ value } }`, &out, authHeader(token))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unknown body measurement type")
}

func TestFinishWorkoutAndHistory(t *testing.T) {
	c, _ := newTestClient(t)
	_, token := signup(t, c, uniqueEmail())

	var start struct{ StartWorkout struct{ ID string } }
	require.NoError(t, c.Post(`mutation { startWorkout { id } }`, &start, authHeader(token)))

	var ex struct{ Exercises []struct{ ID string } }
	require.NoError(t, c.Post(`{ exercises(search:"Barbell Back Squat"){ id } }`, &ex, authHeader(token)))
	require.NoError(t, c.Post(
		`mutation ($w:UUID!,$e:UUID!){ logSet(workoutId:$w, exerciseId:$e, reps:5, weightKg:80){ set{ reps } } }`,
		&struct {
			LogSet struct {
				Set struct{ Reps int }
			}
		}{}, client.Var("w", start.StartWorkout.ID), client.Var("e", ex.Exercises[0].ID), authHeader(token)))

	var fin struct{ FinishWorkout struct{ ID string } }
	require.NoError(t, c.Post(
		`mutation ($w:UUID!){ finishWorkout(workoutId:$w, notes:"done"){ id } }`,
		&fin, client.Var("w", start.StartWorkout.ID), authHeader(token)))
	assert.Equal(t, start.StartWorkout.ID, fin.FinishWorkout.ID)

	var hist struct {
		WorkoutHistory struct {
			Edges []struct {
				Node struct{ ID string }
			}
		}
	}
	require.NoError(t, c.Post(`{ workoutHistory(first:10){ edges { node { id } } } }`, &hist, authHeader(token)))
	require.Len(t, hist.WorkoutHistory.Edges, 1)
	assert.Equal(t, start.StartWorkout.ID, hist.WorkoutHistory.Edges[0].Node.ID)

	var prs struct {
		PersonalRecords []struct{ RecordType string }
	}
	require.NoError(t, c.Post(`{ personalRecords { recordType } }`, &prs, authHeader(token)))
	assert.NotEmpty(t, prs.PersonalRecords)
}
