# DB 設計・運用

## ER

```
users 1 ── * tasks * ── * tags
                   (task_tags で多対多)
```

## 設計ポイント (migrations/001_init.sql)

- **主キー**: `BIGINT GENERATED ALWAYS AS IDENTITY`。SQL 標準の自動採番 (旧 `SERIAL` の後継)。INT は 21 億で枯渇するため BIGINT
- **時刻**: `TIMESTAMPTZ` (タイムゾーン付き)。`TIMESTAMP` はタイムゾーン情報を失うため避ける
- **文字列**: PostgreSQL では `TEXT` と `VARCHAR(n)` の性能差なし。長さ制約は `CHECK` で明示
- **制約で整合性を守る**: `NOT NULL` / `UNIQUE` / `CHECK` / 外部キー。アプリのバリデーションと二重で守る
- **外部キー**: `ON DELETE CASCADE` でユーザー削除時にタスクも削除
- **多対多**: 中間テーブル `task_tags` + 複合主キー `(task_id, tag_id)` で重複防止
- **インデックス**
  - `tasks (user_id, created_at DESC)`: 「ユーザーの新しい順」をソートなしで取得
  - 複合インデックスは左端の列から使われる → `task_tags` の PK は `task_id` 起点のみ有効。`tag_id` 起点用に別途作成
  - 外部キー列には自動でインデックスが付かない (PostgreSQL)。JOIN・CASCADE 削除のため自分で付ける

## アプリ側の SQL (handler.go)

- **N+1 回避**: タスク一覧とタグを `LEFT JOIN` + `array_agg` で1クエリに集約
- **トランザクション**: タスク・タグ・中間テーブルの登録を1トランザクションで
- **UPSERT**: `INSERT ... ON CONFLICT (name) DO UPDATE` でタグの取得/作成を1文で
- **プレースホルダ** (`$1`): SQL インジェクション対策。文字列連結で SQL を組み立てない

## マイグレーション

- `migrations/NNN_xxx.sql` を追加 → ArgoCD の PreSync Job が新 Pod 起動前に適用
- 適用済みは `schema_migrations` テーブルで管理。advisory lock で同時実行を防止
- **後方互換を保つ**: 旧 Pod と新 Pod が同時に動くため、列の削除・改名は「追加 → コード切替 → 削除」の複数リリースに分ける

## CloudNativePG 運用演習

```sh
kubectl -n todo get cluster todo-db            # 状態・primary 確認
kubectl -n todo get pods -l cnpg.io/cluster=todo-db -L role
kubectl -n todo exec -it todo-db-1 -- psql todo  # psql 接続 (primary で)
```

CNPG が作る Service: `todo-db-rw` (primary: 読み書き) / `todo-db-ro` (replica: 読み取り専用) / `todo-db-r` (全台)。

### 課題

1. **実行計画**: `EXPLAIN ANALYZE SELECT ... FROM tasks WHERE user_id = 1 ORDER BY created_at DESC LIMIT 100;` でインデックス使用を確認。インデックスを DROP して比較 (大量データは `generate_series` で投入)
2. **フェイルオーバー**: primary Pod を `kubectl delete pod` → replica が昇格することを `get cluster` で確認。アプリへの影響も観察
   - **ノード障害**: primary のいるノードを `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` → 別ノードの replica が昇格。旧 primary は Pending (別ノード必須のため)。`kubectl uncordon` で復帰し replica として再参加
3. **スイッチオーバー** (計画的切替): `kubectl cnpg promote todo-db todo-db-2` (cnpg プラグイン要導入)
4. **レプリケーション**: primary で `SELECT * FROM pg_stat_replication;`
5. **マイグレーション追加**: `002_add_due_date.sql` で `tasks` に `due_date DATE` を追加 → push → PreSync Job のログ確認
6. **バックアップ (VolumeSnapshot)**: GKE の CSI スナップショットを利用

   ```yaml
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshotClass
   metadata: { name: pd-snapshot }
   driver: pd.csi.storage.gke.io
   deletionPolicy: Delete
   ---
   apiVersion: postgresql.cnpg.io/v1
   kind: Backup
   metadata: { name: manual-1, namespace: todo }
   spec:
     cluster: { name: todo-db }
     method: volumeSnapshot
   ```

   Cluster に `spec.backup.volumeSnapshot.className: pd-snapshot` の追記が必要。スナップショットは少額課金 → 確認後に削除
7. **リストア**: 上記バックアップから新 Cluster を `bootstrap.recovery` で作成
