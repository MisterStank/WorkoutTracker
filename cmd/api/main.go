package main

import (
	"context"
	"log"
	"net/http"
	"strings"
	"time"

	"workouttracker/internal/cache"
	"workouttracker/internal/graphql"
	appmiddleware "workouttracker/internal/middleware"
	"workouttracker/internal/platform"
	"workouttracker/internal/realtime"
	"workouttracker/internal/repository"
	"workouttracker/internal/service"

	"github.com/99designs/gqlgen/graphql/handler"
	"github.com/99designs/gqlgen/graphql/handler/extension"
	"github.com/99designs/gqlgen/graphql/handler/lru"
	"github.com/99designs/gqlgen/graphql/handler/transport"
	"github.com/99designs/gqlgen/graphql/playground"
	coderws "github.com/coder/websocket"
	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/vektah/gqlparser/v2/ast"
)

func main() {
	cfg := platform.LoadConfig()

	ctx := context.Background()
	db, err := platform.NewPostgresPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("failed to connect to postgres: %v", err)
	}
	defer db.Close()

	redisClient, err := platform.NewRedisClient(ctx, cfg.RedisURL)
	if err != nil {
		log.Fatalf("failed to connect to redis: %v", err)
	}
	defer redisClient.Close()

	tokens := service.NewTokenIssuer([]byte(cfg.JWTSecret))
	userRepo := repository.NewUserRepository(db)
	refreshTokenRepo := repository.NewRefreshTokenRepository(db)
	authService := service.NewAuthService(userRepo, refreshTokenRepo, tokens)

	analyticsCache := cache.NewRedisCache(redisClient)
	rollupRepo := repository.NewProgressRollupRepository(db)
	bodyMetricRepo := repository.NewBodyMetricRepository(db)
	analyticsService := service.NewAnalyticsService(rollupRepo, bodyMetricRepo, analyticsCache)

	eventBus := realtime.NewRedisEventBus(redisClient)

	exerciseRepo := repository.NewExerciseRepository(db)
	workoutRepo := repository.NewWorkoutRepository(db)
	workoutSetRepo := repository.NewWorkoutSetRepository(db)
	personalRecordRepo := repository.NewPersonalRecordRepository(db)
	templateRepo := repository.NewWorkoutTemplateRepository(db)
	workoutService := service.NewWorkoutService(exerciseRepo, workoutRepo, workoutSetRepo, personalRecordRepo, templateRepo, analyticsService, eventBus)

	resolver := &graphql.Resolver{Auth: authService, Workout: workoutService, Analytics: analyticsService, Events: eventBus}
	gqlHandler := newGraphQLServer(resolver, tokens)

	r := chi.NewRouter()
	r.Use(chimiddleware.RequestID)
	r.Use(chimiddleware.RealIP)
	r.Use(chimiddleware.Logger)
	r.Use(chimiddleware.Recoverer)
	// Flutter web's dev server runs on a random localhost port each run, so
	// the origin can't be pinned to one value in local development.
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"http://localhost:*", "http://127.0.0.1:*"},
		AllowedMethods:   []string{"GET", "POST", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type"},
		AllowCredentials: false,
	}))
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

// newGraphQLServer replicates gqlgenhandler.NewDefaultServer's transport
// setup but with a custom Websocket transport: OriginPatterns matching the
// same local-dev origins as the HTTP CORS policy (browsers don't apply CORS
// to WebSocket upgrades, but gqlgen's coder/websocket backend does its own
// origin check), and an InitFunc that authenticates the subscription from
// the connection_init payload — a WS handshake can't carry a normal
// Authorization header the way the HTTP transport's auth middleware expects.
func newGraphQLServer(resolver *graphql.Resolver, tokens *service.TokenIssuer) *handler.Server {
	srv := handler.New(graphql.NewExecutableSchema(graphql.Config{Resolvers: resolver}))

	srv.AddTransport(transport.Websocket{
		KeepAlivePingInterval: 10 * time.Second,
		Implementation: transport.CoderWebsocketImplementation{
			AcceptOptions: coderws.AcceptOptions{
				OriginPatterns: []string{"localhost:*", "127.0.0.1:*"},
			},
		},
		InitFunc: func(ctx context.Context, initPayload transport.InitPayload) (context.Context, *transport.InitPayload, error) {
			authHeader, _ := initPayload["Authorization"].(string)
			tokenString := strings.TrimPrefix(authHeader, "Bearer ")
			if tokenString == "" {
				return ctx, nil, nil // unauthenticated subscriptions are rejected by resolvers, not here
			}
			claims, err := tokens.ParseAccessToken(tokenString)
			if err != nil {
				return ctx, nil, err
			}
			return appmiddleware.WithUserID(ctx, claims.UserID), nil, nil
		},
	})
	srv.AddTransport(transport.Options{})
	srv.AddTransport(transport.GET{})
	srv.AddTransport(transport.POST{})
	srv.AddTransport(transport.MultipartForm{})

	srv.SetQueryCache(lru.New[*ast.QueryDocument](1000))

	srv.Use(extension.Introspection{})
	srv.Use(extension.AutomaticPersistedQuery{
		Cache: lru.New[string](100),
	})

	return srv
}
