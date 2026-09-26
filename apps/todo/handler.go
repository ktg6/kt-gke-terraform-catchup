package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// 認証は対象外。全タスクをシードのデモユーザー(id=1)に紐付ける
const demoUserID = 1

// フィールド順は listTasks の SELECT 列順と一致させる (RowToStructByPos)
type Task struct {
	ID        int64     `json:"id"`
	Title     string    `json:"title"`
	Done      bool      `json:"done"`
	Tags      []string  `json:"tags"`
	CreatedAt time.Time `json:"created_at"`
}

type createTaskRequest struct {
	Title string   `json:"title"`
	Tags  []string `json:"tags"`
}

func (r createTaskRequest) validate() error {
	if n := utf8.RuneCountInString(r.Title); n < 1 || n > 200 {
		return errors.New("title must be 1-200 chars")
	}
	if len(r.Tags) > 10 {
		return errors.New("tags must be <= 10")
	}
	for _, t := range r.Tags {
		if n := utf8.RuneCountInString(t); n < 1 || n > 50 {
			return errors.New("tag must be 1-50 chars")
		}
	}
	return nil
}

type server struct {
	db      *pgxpool.Pool
	version string
}

func newHandler(db *pgxpool.Pool, version string) http.Handler {
	s := &server{db: db, version: version}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", s.index)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("GET /readyz", s.readyz)
	mux.HandleFunc("GET /tasks", s.listTasks)
	mux.HandleFunc("POST /tasks", s.createTask)
	return mux
}

// カナリア確認用にバージョンを返す
func (s *server) index(w http.ResponseWriter, _ *http.Request) {
	fmt.Fprintf(w, "todo %s\n", s.version)
}

func (s *server) readyz(w http.ResponseWriter, r *http.Request) {
	if err := s.db.Ping(r.Context()); err != nil {
		http.Error(w, "db unavailable", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (s *server) listTasks(w http.ResponseWriter, r *http.Request) {
	// LEFT JOIN + array_agg でタスクごとのタグを1行に集約 (N+1 回避)
	rows, err := s.db.Query(r.Context(), `
		SELECT t.id, t.title, t.done,
		       COALESCE(array_agg(g.name ORDER BY g.name) FILTER (WHERE g.name IS NOT NULL), '{}'),
		       t.created_at
		FROM tasks t
		LEFT JOIN task_tags tt ON tt.task_id = t.id
		LEFT JOIN tags g ON g.id = tt.tag_id
		WHERE t.user_id = $1
		GROUP BY t.id
		ORDER BY t.created_at DESC
		LIMIT 100`, demoUserID)
	if err != nil {
		serverError(w, err)
		return
	}
	tasks, err := pgx.CollectRows(rows, pgx.RowToStructByPos[Task])
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, tasks)
}

func (s *server) createTask(w http.ResponseWriter, r *http.Request) {
	var req createTaskRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if err := req.validate(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	t := Task{Tags: []string{}}
	// タスク・タグ・中間テーブルを1トランザクションで登録。エラー時は自動ロールバック
	err := pgx.BeginFunc(r.Context(), s.db, func(tx pgx.Tx) error {
		err := tx.QueryRow(r.Context(),
			`INSERT INTO tasks (user_id, title) VALUES ($1, $2) RETURNING id, title, done, created_at`,
			demoUserID, req.Title).Scan(&t.ID, &t.Title, &t.Done, &t.CreatedAt)
		if err != nil {
			return err
		}
		for _, name := range req.Tags {
			// タグは UPSERT で取得/作成し、そのまま中間テーブルへ
			_, err := tx.Exec(r.Context(), `
				WITH tag AS (
					INSERT INTO tags (name) VALUES ($2)
					ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
					RETURNING id)
				INSERT INTO task_tags (task_id, tag_id) SELECT $1, id FROM tag
				ON CONFLICT DO NOTHING`, t.ID, name)
			if err != nil {
				return err
			}
			t.Tags = append(t.Tags, name)
		}
		return nil
	})
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, t)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func serverError(w http.ResponseWriter, err error) {
	slog.Error("request failed", "err", err)
	http.Error(w, "internal error", http.StatusInternalServerError)
}
