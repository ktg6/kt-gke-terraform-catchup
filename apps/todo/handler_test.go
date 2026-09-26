package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// テーブル駆動テスト: Go の定番スタイル
func TestCreateTaskRequestValidate(t *testing.T) {
	tests := []struct {
		name    string
		req     createTaskRequest
		wantErr bool
	}{
		{"ok", createTaskRequest{Title: "buy milk", Tags: []string{"home"}}, false},
		{"empty title", createTaskRequest{Title: ""}, true},
		{"long title", createTaskRequest{Title: strings.Repeat("あ", 201)}, true},
		{"empty tag", createTaskRequest{Title: "x", Tags: []string{""}}, true},
		{"too many tags", createTaskRequest{Title: "x", Tags: make([]string, 11)}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := tt.req.validate(); (err != nil) != tt.wantErr {
				t.Errorf("validate() err = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

// DB 不要なエンドポイントは httptest で確認
func TestHealthz(t *testing.T) {
	rec := httptest.NewRecorder()
	newHandler(nil, "test").ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
}

func TestInvalidJSON(t *testing.T) {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/tasks", strings.NewReader("{"))
	newHandler(nil, "test").ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d", rec.Code)
	}
}
