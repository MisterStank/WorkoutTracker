package service_test

import (
	"testing"

	"gymon/internal/domain"
	"gymon/internal/service"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func rpePtr(v float64) *float64 { return &v }

func TestValidateSetInput(t *testing.T) {
	tests := []struct {
		name       string
		reps       int
		weightKg   float64
		rpe        *float64
		bodyweight bool
		wantErr    error
	}{
		{name: "ok normal", reps: 5, weightKg: 100, rpe: rpePtr(8)},
		{name: "ok no rpe", reps: 10, weightKg: 60},
		{name: "ok bodyweight zero", reps: 8, weightKg: 0, bodyweight: true},
		{name: "ok bodyweight assisted", reps: 8, weightKg: -15, bodyweight: true},
		{name: "reps zero", reps: 0, weightKg: 100, wantErr: domain.ErrInvalidSetValues},
		{name: "reps negative", reps: -5, weightKg: 100, wantErr: domain.ErrInvalidSetValues},
		{name: "reps too high", reps: 101, weightKg: 100, wantErr: domain.ErrInvalidSetValues},
		{name: "weight negative non-bodyweight", reps: 5, weightKg: -100, wantErr: domain.ErrInvalidSetValues},
		{name: "weight overflow", reps: 1, weightKg: 10000, wantErr: domain.ErrInvalidSetValues},
		{name: "rpe too high", reps: 5, weightKg: 100, rpe: rpePtr(99), wantErr: domain.ErrInvalidRPE},
		{name: "rpe not half step", reps: 5, weightKg: 100, rpe: rpePtr(8.3), wantErr: domain.ErrInvalidRPE},
		{name: "rpe zero", reps: 5, weightKg: 100, rpe: rpePtr(0), wantErr: domain.ErrInvalidRPE},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			err := service.ValidateSetInput(tc.reps, tc.weightKg, tc.rpe, tc.bodyweight)
			if tc.wantErr == nil {
				assert.NoError(t, err)
			} else {
				assert.ErrorIs(t, err, tc.wantErr)
			}
		})
	}
}

func TestValidateEmail(t *testing.T) {
	got, err := service.ValidateEmail("  Demo@Example.COM ")
	require.NoError(t, err)
	assert.Equal(t, "demo@example.com", got)

	for _, bad := range []string{"", "notanemail", "a@b", "no domain@", "@nolocal.com", "two@@at.com"} {
		_, err := service.ValidateEmail(bad)
		assert.ErrorIs(t, err, domain.ErrInvalidEmail, bad)
	}
}

func TestValidatePassword(t *testing.T) {
	assert.NoError(t, service.ValidatePassword("longenough"))
	assert.ErrorIs(t, service.ValidatePassword("short"), domain.ErrWeakPassword)
	assert.ErrorIs(t, service.ValidatePassword(""), domain.ErrWeakPassword)
}

func TestValidateDisplayName(t *testing.T) {
	got, err := service.ValidateDisplayName("  Alex  ")
	require.NoError(t, err)
	assert.Equal(t, "Alex", got)

	_, err = service.ValidateDisplayName("   ")
	assert.ErrorIs(t, err, domain.ErrEmptyDisplayName)
}

func TestValidateBodyMetric(t *testing.T) {
	assert.NoError(t, service.ValidateBodyMetric("bodyweight_kg", 80))
	assert.ErrorIs(t, service.ValidateBodyMetric("banana", 5), domain.ErrInvalidMetricType)
	assert.ErrorIs(t, service.ValidateBodyMetric("bodyweight_kg", -50), domain.ErrInvalidMetricValue)
	assert.ErrorIs(t, service.ValidateBodyMetric("bodyweight_kg", 0), domain.ErrInvalidMetricValue)
	assert.ErrorIs(t, service.ValidateBodyMetric("waist_cm", 5000), domain.ErrInvalidMetricValue)
}

func TestValidateTemplateName(t *testing.T) {
	got, err := service.ValidateTemplateName("  Push Day ")
	require.NoError(t, err)
	assert.Equal(t, "Push Day", got)

	_, err = service.ValidateTemplateName("  ")
	assert.ErrorIs(t, err, domain.ErrEmptyTemplateName)
}
