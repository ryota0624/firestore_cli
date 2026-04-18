///|
test "split_collection_path: single segment" {
  assert_eq(split_collection_path("notes"), Ok(("", "notes")))
}

///|
test "split_collection_path: three segments" {
  assert_eq(
    split_collection_path("users/alice/posts"),
    Ok(("users/alice", "posts")),
  )
}

///|
test "split_collection_path: even segments rejected" {
  assert_true(split_collection_path("users/alice") is Err(_))
}

///|
test "split_collection_path: empty segment rejected" {
  assert_true(split_collection_path("users//posts") is Err(_))
}

///|
test "build_parent and build_document_name" {
  assert_eq(
    build_parent("p1", "(default)", ""),
    "projects/p1/databases/(default)/documents",
  )
  assert_eq(
    build_parent("p1", "(default)", "users/alice"),
    "projects/p1/databases/(default)/documents/users/alice",
  )
  assert_eq(
    build_document_name("p1", "(default)", "users/alice/posts", "doc1"),
    "projects/p1/databases/(default)/documents/users/alice/posts/doc1",
  )
}
