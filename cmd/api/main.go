package main

import (
	"context"
	"log"
	"net/http"

	"workouttracker/internal/graphql"
	appmiddleware "workouttracker/internal/middleware"
	"workouttracker/internal/platform"
	"workouttracker/internal/repository"
	"workouttracker/internal/service"

	gqlgenhandler "github.com/99designs/gqlgen/graphql/handler"
	"github.com/99designs/gqlgen/graphql/playground"
	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
)

func main() {
	cfg := platform.LoadConfig()

	ctx := context.Background()
	db, err := platform.NewPostgresPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("failed to connect to postgres: %v", err)
	}
	defer db.Close()

	tokens := service.NewTokenIssuer([]byte(cfg.JWTSecret))
	userRepo := repository.NewUserRepository(db)
	refreshTokenRepo := repository.NewRefreshTokenRepository(db)
	authService := service.NewAuthService(userRepo, refreshTokenRepo, tokens)

	resolver := &graphql.Resolver{Auth: authService}
	gqlHandler := gqlgenhandler.NewDefaultServer(graphql.NewExecutableSchema(graphql.Config{Resolvers: resolver}))

	r := chi.NewRouter()
	r.Use(chimiddleware.RequestID)
	r.Use(chimiddleware.RealIP)
	r.Use(chimiddleware.Logger)
	r.Use(chimiddleware.Recoverer)
	r.Use(appmiddleware.Auth(tokens))

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	r.Handle("/graphql", gqlHandler)
	r.Handle("/playground", playground.Handler("GraphQL Playground", "/graphql"))

	log.Printf("listening on :%s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, r); err != nil {
		log.Fatal(err)
	}
}
