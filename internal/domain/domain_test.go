package domain_test

import (
	"errors"
	"fmt"
	"testing"

	"workouttracker/internal/domain"

	"github.com/stretchr/testify/assert"
)

func TestIsUserFacing(t *testing.T) {
	assert.True(t, domain.IsUserFacing(domain.ErrEmailTaken))
	assert.True(t, domain.IsUserFacing(domain.ErrWorkoutNotOwned))
	assert.True(t, domain.IsUserFacing(domain.ErrTooManyRequests))

	// wrapped sentinels are still recognised
	assert.True(t, domain.IsUserFacing(fmt.Errorf("context: %w", domain.ErrInvalidRPE)))

	// unknown / infrastructure errors are not
	assert.False(t, domain.IsUserFacing(errors.New("pq: SQLSTATE 22003")))
	assert.False(t, domain.IsUserFacing(nil))
}

func TestProgressionRuleForGoal(t *testing.T) {
	cases := map[domain.Goal]domain.ProgressionRule{
		domain.GoalStrength:       domain.ProgressionLinear,
		domain.GoalHypertrophy:    domain.ProgressionDouble,
		domain.GoalFatLoss:        domain.ProgressionNone,
		domain.GoalGeneralFitness: domain.ProgressionNone,
		domain.Goal("nonsense"):   domain.ProgressionNone,
	}
	for goal, want := range cases {
		assert.Equal(t, want, domain.ProgressionRuleForGoal(goal), "goal=%s", goal)
	}
}
