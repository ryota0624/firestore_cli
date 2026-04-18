# 2026-04-18 Phase 3 Integration Tests

## Added integration tests

- `test/integration/list_collection_ids_test.mbt`
  - Root-level collection ID listing after creating multiple collections.
  - Subcollection ID listing for `parent_doc_path="users/alice"` after creating `users/alice/posts`.
  - Note: on emulator `listCollectionIds` may return `NetworkError`; test treats this as emulator limitation and exits early.

- `test/integration/aggregate_test.mbt`
  - `aggregate` with `Count`, `Sum("amount")`, `Avg("amount")`.
  - Combined with `where_` condition (`active == true`).
  - Aggregation on subcollection (`users/alice/posts`).

- `test/integration/query_advanced_test.mbt`
  - `QuerySpec` with `CompositeFilter` (`AND`) across two field filters.
  - `order_by + limit` behavior.
  - Cursor paging via `start_at / end_at`.

- `test/integration/explain_test.mbt`
  - `explain_query` with `analyze=false` and `analyze=true`.
  - `explain_aggregate` with `analyze=false` and `analyze=true`.
  - For emulator limitations, the test accepts API-level errors by early return while still asserting metrics object shape when responses are returned.

## Commands executed

- `moon fmt test/integration`
- `moon info -p ryota0624/firestore_cli/test/integration`
- `moon check --target native`
- `moon test -p ryota0624/firestore_cli/test/integration --target native`
