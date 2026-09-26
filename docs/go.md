# Go 解説 (apps/todo)

Go 未経験者向け。コードと並べて読む前提。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `go.mod` / `go.sum` | 依存管理 (npm の package.json / lock に相当) |
| `main.go` | 起動・終了処理 |
| `handler.go` | HTTP ハンドラ・SQL |
| `migrate.go` | DB マイグレーション |
| `handler_test.go` | テスト (`go test ./...`) |

同じディレクトリの `.go` は全て `package main` = 1つのパッケージ。ファイル間で import なしに関数を呼べる。

## 押さえる文法

**エラー処理**: 例外なし。関数が `error` を最後の戻り値で返し、呼び出し側が毎回確認する。

```go
pool, err := pgxpool.New(ctx, url) // := は宣言+代入 (型推論)
if err != nil {
    return err                      // 呼び出し元へ伝播
}
```

`fmt.Errorf("%s: %w", f, err)` で文脈を付けてラップ。

**構造体とメソッド**: クラスの代わり。

```go
type server struct { db *pgxpool.Pool }            // フィールド
func (s *server) readyz(w http.ResponseWriter, r *http.Request) { ... } // メソッド
```

`*` はポインタ。`s *server` は「server を参照で受け取る」。

**大文字/小文字**: 先頭大文字 = パッケージ外に公開 (`Task`)、小文字 = 非公開 (`server`)。

**構造体タグ**: `` `json:"title"` `` で JSON のキー名を指定。

**defer**: 関数終了時に実行。後片付け用 (`defer pool.Close()`)。

**無名関数・クロージャ**: `pgx.BeginFunc(ctx, db, func(tx pgx.Tx) error { ... })` のように関数を引数で渡す。

**goroutine**: `go func() { ... }()` で軽量スレッド起動。`main.go` では終了シグナル待ちに使用。

**context**: キャンセル・タイムアウトを伝える値。`r.Context()` はクライアント切断でキャンセルされ、実行中の SQL も中断される。

**ジェネリクス**: `pgx.RowToStructByPos[Task]` の `[Task]` が型引数。

## 処理の流れ

1. `main`: フラグ解析、SIGTERM で ctx をキャンセルするよう設定
2. `run`: DB 接続プール作成 → `-migrate` なら `migrate` して終了、それ以外は HTTP サーバー起動
3. ctx キャンセル (Pod 停止) → `srv.Shutdown` で処理中リクエストを待って終了

## HTTP ルーティング

Go 1.22 以降の標準ライブラリだけで `"GET /tasks"` のようにメソッド付きで定義できる。`{$}` は完全一致 (`/` のみ)。

## 主なコマンド

```sh
go run . -migrate      # 実行 (DATABASE_URL 環境変数が必要)
go test ./...          # テスト
go vet ./...           # 静的解析
gofmt -w .             # 整形 (Go は公式フォーマッタで書式統一)
go mod tidy            # 依存の追加・削除を go.mod に反映
```

## Dockerfile

マルチステージビルド。1段目で静的バイナリ (`CGO_ENABLED=0`) を作り、2段目の distroless (シェルなし・非 root) にコピー。イメージは数 MB。
