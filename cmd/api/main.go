package main

import (
	"context"
	"log"
	"net/http"
	"strings"
	"time"

	"gymon/internal/cache"
	"gymon/internal/domain"
	"gymon/internal/graphql"
	appmiddleware "gymon/internal/middleware"
	"gymon/internal/platform"
	"gymon/internal/ratelimit"
	"gymon/internal/realtime"
	"gymon/internal/repository"
	"gymon/internal/service"

	gqlgraphql "github.com/99designs/gqlgen/graphql"
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
	"github.com/vektah/gqlparser/v2/gqlerror"
)

func main() {
	cfg, err := platform.LoadConfig()
	if err != nil {
		log.Fatal(err)
	}

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
	authLimiter := ratelimit.NewRedisLimiter(redisClient)
	userRepo := repository.NewUserRepository(db)
	refreshTokenRepo := repository.NewRefreshTokenRepository(db)
	authService := service.NewAuthService(userRepo, refreshTokenRepo, tokens, authLimiter)

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

	fitnessProfileRepo := repository.NewFitnessProfileRepository(db)
	programRepo := repository.NewProgramRepository(db, templateRepo)
	programService := service.NewProgramService(fitnessProfileRepo, programRepo, exerciseRepo, workoutService)

	petRepo := repository.NewPetRepository(db)
	accessoryRepo := repository.NewAccessoryRepository(db)
	petStatsRepo := repository.NewPetStatsRepository(db)
	petService := service.NewPetService(petRepo, accessoryRepo, petStatsRepo, service.DefaultPetTuning)

	resolver := &graphql.Resolver{Auth: authService, Workout: workoutService, Analytics: analyticsService, Program: programService, Pets: petService, Events: eventBus}
	gqlHandler := newGraphQLServer(resolver, tokens, cfg.AllowedOrigins)

	r := chi.NewRouter()
	r.Use(chimiddleware.RequestID)
	// Deliberately no RealIP middleware: it blindly trusts X-Forwarded-For/
	// X-Real-IP, letting any client spoof the address that ends up in
	// r.RemoteAddr and the access log (see the deprecation notice on
	// chimiddleware.RealIP — GHSA-9g5q-2w5x-hmxf and related advisories).
	// Nothing here makes a security decision based on client IP, so the
	// access log just shows the real TCP peer (Render's proxy) instead.
	r.Use(chimiddleware.Logger)
	r.Use(chimiddleware.Recoverer)
	// Records the caller's IP in the request context for the auth rate
	// limiter (see internal/middleware/client_ip.go for the X-Forwarded-For
	// handling).
	r.Use(appmiddleware.ClientIP)
	// Origins are configurable via ALLOWED_ORIGINS (defaults to local-dev
	// patterns) since Flutter web's dev server runs on a random localhost
	// port each run, and production needs the real deployed web origin.
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   cfg.AllowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type"},
		AllowCredentials: false,
	}))
	r.Use(appmiddleware.Auth(tokens))

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
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
// same origins as the HTTP CORS policy (browsers don't apply CORS to
// WebSocket upgrades, but gqlgen's coder/websocket backend does its own
// origin check), and an InitFunc that authenticates the subscription from
// the connection_init payload — a WS handshake can't carry a normal
// Authorization header the way the HTTP transport's auth middleware expects.
func newGraphQLServer(resolver *graphql.Resolver, tokens *service.TokenIssuer, allowedOrigins []string) *handler.Server {
	srv := handler.New(graphql.NewExecutableSchema(graphql.Config{Resolvers: resolver}))

	srv.AddTransport(transport.Websocket{
		KeepAlivePingInterval: 10 * time.Second,
		Implementation: transport.CoderWebsocketImplementation{
			AcceptOptions: coderws.AcceptOptions{
				// coder/websocket's OriginPatterns are host:port globs, not
				// full URLs — strip the scheme CORS origins carry.
				OriginPatterns: stripSchemes(allowedOrigins),
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

	// Only known domain errors reach the client with their real message.
	// Everything else (pgx/driver errors, bugs) is logged and replaced with
	// a generic message so internals like "SQLSTATE 22003" don't leak.
	srv.SetErrorPresenter(func(ctx context.Context, e error) *gqlerror.Error {
		err := gqlgraphql.DefaultErrorPresenter(ctx, e)
		if domain.IsUserFacing(e) {
			return err
		}
		// gqlgen's own parse/validation errors (bad query text, unknown
		// field, wrong argument type) are about the request, not our
		// internals — safe and useful to pass through.
		if err.Extensions != nil {
			if code, _ := err.Extensions["code"].(string); strings.HasPrefix(code, "GRAPHQL_") {
				return err
			}
		}
		log.Printf("graphql: masking non-user-facing error: %v", e)
		err.Message = "something went wrong, please try again"
		return err
	})
	srv.SetRecoverFunc(func(ctx context.Context, err any) error {
		log.Printf("graphql: panic recovered: %v", err)
		return gqlerror.Errorf("something went wrong, please try again")
	})

	return srv
}

// stripSchemes converts CORS-style origins ("https://example.com") into the
// host:port glob patterns coder/websocket's OriginPatterns expects
// ("example.com"), leaving already-bare patterns untouched.
func stripSchemes(origins []string) []string {
	out := make([]string, len(origins))
	for i, o := range origins {
		o = strings.TrimPrefix(o, "http://")
		o = strings.TrimPrefix(o, "https://")
		out[i] = o
	}
	return out
}
