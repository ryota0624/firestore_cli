# Task: Query enhancement + explain (2026-04-18)

## Summary

Added `QuerySpec` and `QueryExplainResult`, plus `FirestoreClient::query` and `FirestoreClient::explain_query` in `firestore/client.mbt`. Existing `query_collection` is unchanged.

## Implementation notes

- Collection path handling uses `split_collection_path` and `build_parent` like other client methods.
- `StructuredQuery` uses a single `CollectionSelector` with `collection_id` and `all_descendants: None`.
- `QuerySpec.filter` maps to `where_`; `order_by`, `start_at`, `end_at`, `limit`, and `offset` are passed through; `find_nearest` is `None`.
- `RunQueryRequest.explain_options` is `None` for `query`, and `Some(ExplainOptions { analyze: Some(analyze) })` for `explain_query`.
- Responses from `run_query` are scanned for `document`; `extract_explain_metrics` reads `explain_metrics` from the last `RunQueryResponse`, defaulting to empty metrics when missing.

## Verification

Run locally (authoritative):

```bash
cd /path/to/firestire_cli
git checkout -b feat/query-enhancement-and-explain   # if not already on branch
moon fmt
moon info -p ryota0624/firestore_cli/firestore
moon check --target native
moon test
```

If `fast_linter` MCP is available, run `mcp__fast_linter__analyze_files` on `firestore/client.mbt`. Otherwise rely on `moon check --target native`.

`pkg.generated.mbti` was updated by hand to match the new API; re-run `moon info` and resolve any diff so the file matches the compiler output.

## Git

```bash
git add firestore/client.mbt firestore/pkg.generated.mbti docs/completed/20260418_query_enhancement.md
git commit -m "feat(firestore): add QuerySpec, query, and explain_query"
```

## Branch

Target branch: `feat/query-enhancement-and-explain` (commit on this branch; no PR required by task).
