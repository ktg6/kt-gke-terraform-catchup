-- 設計解説は docs/db.md

CREATE TABLE users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email      TEXT        NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tasks (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title      TEXT        NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
    done       BOOLEAN     NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- 「ユーザーのタスクを新しい順」の検索用複合インデックス
CREATE INDEX tasks_user_id_created_at_idx ON tasks (user_id, created_at DESC);

CREATE TABLE tags (
    id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE CHECK (char_length(name) BETWEEN 1 AND 50)
);

-- 多対多の中間テーブル。複合主キーで重複防止
CREATE TABLE task_tags (
    task_id BIGINT NOT NULL REFERENCES tasks (id) ON DELETE CASCADE,
    tag_id  BIGINT NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, tag_id)
);
-- PK は (task_id, tag_id) 順 → tag_id 起点の検索用に別途インデックス
CREATE INDEX task_tags_tag_id_idx ON task_tags (tag_id);

INSERT INTO users (email) VALUES ('demo@example.com');
