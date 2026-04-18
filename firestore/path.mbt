///|
/// 奇数セグメントの collection path を (parent_suffix, collection_id) に分解する。
/// 例: "notes" → Ok(("", "notes"))、"users/alice/posts" → Ok(("users/alice", "posts"))
/// 偶数セグメントや空文字セグメントを含む場合は Err を返す。
pub fn split_collection_path(path : String) -> Result[(String, String), String] {
  if path == "" {
    return Err("collection path must not be empty")
  }
  let segments = path.split("/").to_array().map(fn(s) { s.to_string() })
  if segments.is_empty() {
    return Err("collection path must not be empty")
  }
  for segment in segments {
    if segment == "" {
      return Err("collection path contains empty segment")
    }
  }
  if segments.length() % 2 == 0 {
    return Err("collection path must have odd number of segments")
  }
  let collection_id = segments[segments.length() - 1]
  let parent_suffix = if segments.length() == 1 {
    ""
  } else {
    segments[:segments.length() - 1].to_array().join("/")
  }
  Ok((parent_suffix, collection_id))
}

///|
/// "projects/{project}/databases/{database}/documents" に parent_suffix があれば "/" でつなぐ。
pub fn build_parent(
  project : String,
  database : String,
  parent_suffix : String,
) -> String {
  let base = "projects/" + project + "/databases/" + database + "/documents"
  if parent_suffix == "" {
    base
  } else {
    base + "/" + parent_suffix
  }
}

///|
/// get_document / delete_document 用の完全修飾名を組み立てる。
pub fn build_document_name(
  project : String,
  database : String,
  collection_path : String,
  doc_id : String,
) -> String {
  build_parent(project, database, collection_path) + "/" + doc_id
}
