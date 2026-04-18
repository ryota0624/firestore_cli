///|
pub struct FirestoreClient {
  service : @gfs.FirestoreService
  project : String
  database : String
}

///|
pub fn FirestoreClient::new(
  client : @gcore.GoogleClient,
  project : String,
  database? : String = "(default)",
  base_url? : String,
) -> FirestoreClient {
  let service = match base_url {
    Some(url) => @gfs.FirestoreService::new(client, base_url=url)
    None => @gfs.FirestoreService::new(client)
  }
  FirestoreClient::{ service, project, database }
}

///|
pub async fn FirestoreClient::get_document(
  self : FirestoreClient,
  collection_path : String,
  doc_id : String,
) -> @gfs.Document raise @ghttp.HttpError {
  let name = build_document_name(
    self.project,
    self.database,
    collection_path,
    doc_id,
  )
  self.service.get_document(name)
}

///|
pub async fn FirestoreClient::list_documents(
  self : FirestoreClient,
  collection_path : String,
  page_size? : Int,
  page_token? : String,
) -> @gfs.ListDocumentsResponse raise @ghttp.HttpError {
  let (parent_suffix, collection_id) = match
    split_collection_path(collection_path) {
    Ok(parts) => parts
    Err(msg) => raise @ghttp.HttpError::network_message(msg)
  }
  let parent = build_parent(self.project, self.database, parent_suffix)
  self.service.list_documents(parent, collection_id, page_size~, page_token~)
}

///|
pub async fn FirestoreClient::query_collection(
  self : FirestoreClient,
  collection_path : String,
  field : String,
  op : String,
  value : @gfs.Value,
  limit? : Int,
) -> Array[@gfs.Document] raise @ghttp.HttpError {
  let (parent_suffix, collection_id) = match
    split_collection_path(collection_path) {
    Ok(parts) => parts
    Err(msg) => raise @ghttp.HttpError::network_message(msg)
  }
  let parent = build_parent(self.project, self.database, parent_suffix)
  let query = @gfs.StructuredQuery::{
    select: None,
    from: Some([
      @gfs.CollectionSelector::{
        collection_id: Some(collection_id),
        all_descendants: None,
      },
    ]),
    where_: Some(@gfs.Filter::{
      composite_filter: None,
      field_filter: Some(@gfs.FieldFilter::{
        field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
        op: Some(op),
        value: Some(value),
      }),
      unary_filter: None,
    }),
    order_by: None,
    start_at: None,
    end_at: None,
    offset: None,
    limit,
    find_nearest: None,
  }
  let request = @gfs.RunQueryRequest::{
    parent: None,
    structured_query: Some(query),
    transaction: None,
    new_transaction: None,
    read_time: None,
    explain_options: None,
  }
  let responses = self.service.run_query(parent, request)
  let docs : Array[@gfs.Document] = []
  for response in responses {
    match response.document {
      Some(doc) => docs.push(doc)
      None => ()
    }
  }
  docs
}

///|
pub async fn FirestoreClient::create_document(
  self : FirestoreClient,
  collection_path : String,
  doc_id? : String,
  fields : Map[String, @gfs.Value],
) -> @gfs.Document raise @ghttp.HttpError {
  let (parent_suffix, collection_id) = match
    split_collection_path(collection_path) {
    Ok(parts) => parts
    Err(msg) => raise @ghttp.HttpError::network_message(msg)
  }
  let parent = build_parent(self.project, self.database, parent_suffix)
  let document = @gfs.Document::{
    name: None,
    fields: Some(fields),
    create_time: None,
    update_time: None,
  }
  self.service.create_document(
    parent,
    collection_id,
    document,
    document_id=doc_id,
  )
}

///|
pub async fn FirestoreClient::delete_document(
  self : FirestoreClient,
  collection_path : String,
  doc_id : String,
) -> Unit raise @ghttp.HttpError {
  let name = build_document_name(
    self.project,
    self.database,
    collection_path,
    doc_id,
  )
  let _ = self.service.delete_document(name)
}

///|
/// batch_get_documents の結果要素。
/// Found は見つかった Document、Missing は見つからなかった full resource name。
pub enum BatchGetResult {
  Found(@gfs.Document)
  Missing(String)
}

///|
/// 複数ドキュメントを一括取得する。
/// - 各 doc_path は "collection_path/doc_id" 形式（例: "notes/doc-a" や
///   "users/alice/posts/1"）
/// - 各要素に対し Found / Missing を返す。transaction-only メタデータ応答は skip。
pub async fn FirestoreClient::batch_get_documents(
  self : FirestoreClient,
  doc_paths : Array[String],
) -> Array[BatchGetResult] raise @ghttp.HttpError {
  let names : Array[String] = []
  for p in doc_paths {
    let (cp, doc_id) = match split_doc_path(p) {
      Ok(v) => v
      Err(msg) => raise @ghttp.HttpError::network_message(msg)
    }
    names.push(build_document_name(self.project, self.database, cp, doc_id))
  }
  let database = "projects/" + self.project + "/databases/" + self.database
  let request = @gfs.BatchGetDocumentsRequest::{
    database: None,
    documents: Some(names),
    mask: None,
    transaction: None,
    new_transaction: None,
    read_time: None,
  }
  let responses = self.service.batch_get_documents(database, request)
  let results : Array[BatchGetResult] = []
  for response in responses {
    match response.found {
      Some(doc) => {
        results.push(Found(doc))
        continue
      }
      None => ()
    }
    match response.missing {
      Some(name) => {
        results.push(Missing(name))
        continue
      }
      None => ()
    }
    // transaction-only metadata response — skip
  }
  results
}
