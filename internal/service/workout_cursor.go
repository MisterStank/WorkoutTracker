package service

import (
	"encoding/base64"
	"errors"
	"strconv"
	"strings"
	"time"

	"workouttracker/internal/domain"

	"github.com/google/uuid"
)

// EncodeWorkoutCursor exposes the cursor encoding for the GraphQL layer,
// which needs a per-edge cursor for each workout in a page.
func EncodeWorkoutCursor(w *domain.Workout) string {
	return encodeCursor(w.StartedAt, w.ID)
}

var errInvalidCursor = errors.New("invalid cursor")

// encodeCursor/decodeCursor implement Relay-style opaque cursors over the
// (started_at, id) keyset used for workout history pagination.
func encodeCursor(startedAt time.Time, id uuid.UUID) string {
	raw := strconv.FormatInt(startedAt.UnixNano(), 10) + "|" + id.String()
	return base64.URLEncoding.EncodeToString([]byte(raw))
}

func decodeCursor(cursor string) (time.Time, uuid.UUID, error) {
	raw, err := base64.URLEncoding.DecodeString(cursor)
	if err != nil {
		return time.Time{}, uuid.Nil, errInvalidCursor
	}
	parts := strings.SplitN(string(raw), "|", 2)
	if len(parts) != 2 {
		return time.Time{}, uuid.Nil, errInvalidCursor
	}
	ns, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return time.Time{}, uuid.Nil, errInvalidCursor
	}
	id, err := uuid.Parse(parts[1])
	if err != nil {
		return time.Time{}, uuid.Nil, errInvalidCursor
	}
	return time.Unix(0, ns), id, nil
}
