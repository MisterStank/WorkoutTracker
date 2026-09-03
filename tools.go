//go:build tools

// Package tools pins the code-generation tools (gqlgen) as module
// dependencies so `go mod tidy` keeps their transitive packages in go.sum and
// `go run github.com/99designs/gqlgen generate` works from a clean checkout.
package tools

import (
	_ "github.com/99designs/gqlgen"
	_ "github.com/99designs/gqlgen/graphql/introspection"
)
