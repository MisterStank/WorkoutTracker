package service

// Test-only hooks (export_test.go is compiled only under `go test`).

// SetArgon2CostForTest lowers the argon2id work factor so auth tests that
// hash many passwords don't dominate the suite runtime. Production cost is
// restored by the returned function.
func SetArgon2CostForTest(memoryKiB, iterations uint32, parallelism uint8) (restore func()) {
	prev := argon2Params
	argon2Params.memory = memoryKiB
	argon2Params.iterations = iterations
	argon2Params.parallelism = parallelism
	// dummyPasswordHash was computed with the production cost at init; recompute
	// it at the test cost so the unknown-email path matches too.
	prevDummy := dummyPasswordHash
	dummyPasswordHash = mustHashPassword("qX9$dummy-not-a-real-password-7fL2")
	return func() {
		argon2Params = prev
		dummyPasswordHash = prevDummy
	}
}
