package service

// White-box test (package service, not service_test) so it can exercise the
// unexported decodeCursor directly — the encode/decode pair is a matched
// unit and only EncodeWorkoutCursor is exported.

import (
	"testing"
	"time"

	"gymon/internal/domain"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWorkoutCursorRoundTrip(t *testing.T) {
	id := uuid.New()
	started := time.Now().UTC().Truncate(time.Nanosecond)

	cursor := EncodeWorkoutCursor(&domain.Workout{ID: id, StartedAt: started})

	gotTime, gotID, err := decodeCursor(cursor)
	require.NoError(t, err)
	assert.Equal(t, id, gotID)
	assert.True(t, started.Equal(gotTime), "want %v got %v", started, gotTime)
}

func TestDecodeCursorRejectsGarbage(t *testing.T) {
	for _, bad := range []string{"", "!!!not-base64!!!", "bm9waXBl", "MTIzNDU2"} {
		_, _, err := decodeCursor(bad)
		assert.ErrorIs(t, err, errInvalidCursor, "input %q", bad)
	}
}
