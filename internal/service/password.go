package service

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// argon2Params are OWASP-recommended baseline parameters for argon2id.
var argon2Params = struct {
	memory      uint32
	iterations  uint32
	parallelism uint8
	saltLength  uint32
	keyLength   uint32
}{memory: 64 * 1024, iterations: 3, parallelism: 2, saltLength: 16, keyLength: 32}

// dummyPasswordHash is a valid argon2id hash of a random string, verified
// against on the "email not found" login path so an unknown email costs the
// same wall-clock time as a real one (defeats user enumeration by timing).
var dummyPasswordHash = mustHashPassword("qX9$dummy-not-a-real-password-7fL2")

func mustHashPassword(p string) string {
	h, err := HashPassword(p)
	if err != nil {
		panic(err)
	}
	return h
}

func HashPassword(password string) (string, error) {
	salt := make([]byte, argon2Params.saltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	hash := argon2.IDKey([]byte(password), salt, argon2Params.iterations, argon2Params.memory, argon2Params.parallelism, argon2Params.keyLength)

	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argon2Params.memory, argon2Params.iterations, argon2Params.parallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	), nil
}

func VerifyPassword(password, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 {
		return false, errors.New("invalid encoded hash format")
	}

	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return false, err
	}
	if version != argon2.Version {
		return false, errors.New("incompatible argon2 version")
	}

	var memory, iterations uint32
	var parallelism uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &iterations, &parallelism); err != nil {
		return false, err
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, err
	}
	storedHash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false, err
	}

	computedHash := argon2.IDKey([]byte(password), salt, iterations, memory, parallelism, uint32(len(storedHash)))
	return subtle.ConstantTimeCompare(storedHash, computedHash) == 1, nil
}
