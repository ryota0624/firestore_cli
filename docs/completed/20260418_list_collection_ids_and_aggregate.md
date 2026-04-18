# 完了報告: list_collection_ids と aggregate/explain_aggregate の追加

## 実装内容
- `firestore/client.mbt` に `FirestoreClient::list_collection_ids` を追加。
  - `parent_doc_path` が `None` の場合は `build_parent(project, database, "")` を使用。
  - `Some(path)` の場合はセグメント空要素と偶数セグメント（ドキュメントパス）を検証し、`build_parent(project, database, path)` を使用。
  - `ListCollectionIdsRequest` を組み立てて `self.service.list_collection_ids` を呼び出し、`(collection_ids, next_page_token?)` を返却。
- 集約系 API と型を追加。
  - 追加型: `Aggregator`, `AggregationResult`, `AggregationExplainResult`
  - 追加メソッド: `FirestoreClient::aggregate`, `FirestoreClient::explain_aggregate`
  - `split_collection_path` で `(parent_suffix, collection_id)` を取得し、`StructuredAggregationQuery` を構築。
  - `aggregators` から `@gfs.Aggregation` 配列を生成（`Count`/`Sum`/`Avg` と `alias_`）。
  - `aggregate` は `explain_options=None`、`explain_aggregate` は `ExplainOptions { analyze: Some(analyze) }` を設定。
  - `run_aggregation_query` の配列レスポンスを走査し、`result.aggregate_fields` を `AggregationResult` に変換。
  - `explain_aggregate` は最後に得られた `explain_metrics` を `AggregationExplainResult.metrics` に格納し、未取得時は `HttpError` を返却。

## 技術的な決定事項
- 既存メソッドは変更せず、追加のみで実装して互換性を維持。
- `list_collection_ids` の `parent_doc_path` 検証は「サブコレ親=ドキュメントパス（偶数セグメント）」を満たす専用チェックで実装。
- `explain_aggregate` の戻り値型は `metrics` が必須なため、応答に `explain_metrics` が無い場合は黙殺せず明示的にエラー化。

## 変更ファイル一覧
- `firestore/client.mbt`
  - `list_collection_ids` / `aggregate` / `explain_aggregate` の追加
  - `Aggregator` / `AggregationResult` / `AggregationExplainResult` の追加
- `firestore/pkg.generated.mbti`
  - 公開 API 追加に伴う自動更新
- `docs/completed/20260418_list_collection_ids_and_aggregate.md`
  - 本完了報告

## テスト・確認
- `moon fmt`
- `moon info -p ryota0624/firestore_cli/firestore`
- `moon check --target native`

## 今後の課題
- `AggregationResult` のフィールド名 `alias` は MoonBit の予約語警告対象のため、将来的に互換性方針を決めた上で命名再検討の余地あり。
- 実 API 応答に対する `aggregate` / `explain_aggregate` の統合テストは未追加。

## 参考資料
- Firestore generated client/types:
  - `.mooncakes/ryota0624/googleapis/generated/firestore/client.mbt`
  - `.mooncakes/ryota0624/googleapis/generated/firestore/types.mbt`
- パスヘルパ:
  - `firestore/path.mbt`
