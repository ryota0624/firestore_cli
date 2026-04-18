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
