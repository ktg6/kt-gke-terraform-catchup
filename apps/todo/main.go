// Command todo は学習用の最小 Todo API。解説は docs/go.md。
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	migrateOnly := flag.Bool("migrate", false, "マイグレーションのみ実行して終了")
	flag.Parse()

	// SIGTERM (Pod 停止時に kubelet が送る) で ctx がキャンセルされる
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := run(ctx, *migrateOnly); err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, migrateOnly bool) error {
	// 接続プール。接続は初回クエリ時に張られる
	pool, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer pool.Close()

	if migrateOnly {
		return migrate(ctx, pool)
	}

	srv := &http.Server{
		Addr:              ":8080",
		Handler:           newHandler(pool, os.Getenv("APP_VERSION")),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// graceful shutdown: 処理中リクエストを待ってから終了
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	slog.Info("listening", "addr", srv.Addr)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
