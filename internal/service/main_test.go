package service_test

import (
	"os"
	"testing"

	"workouttracker/internal/service"
)

// Lower the argon2id cost for the whole package: several auth tests hash or
// verify passwords dozens of times, and the production cost (64 MiB, t=3)
// would make the suite take minutes under -race. The hashing code path is
// unchanged — only the work factor differs.
func TestMain(m *testing.M) {
	restore := service.SetArgon2CostForTest(8*1024, 1, 1)
	code := m.Run()
	restore()
	os.Exit(code)
}
