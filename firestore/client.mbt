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
pub async fn FirestoreClient::list_collection_ids(
  self : FirestoreClient,
  parent_doc_path? : String,
  page_size? : Int,
  page_token? : String,
) -> (Array[String], String?) raise @ghttp.HttpError {
  let parent = match parent_doc_path {
    None => build_parent(self.project, self.database, "")
    Some(path) => {
      if path == "" {
        raise @ghttp.HttpError::network_message(
          "parent document path must not be empty",
        )
      }
      let segments = path.split("/").to_array().map(fn(s) { s.to_string() })
      for segment in segments {
        if segment == "" {
          raise @ghttp.HttpError::network_message(
            "parent document path contains empty segment: \"\{path}\"",
          )
        }
      }
      if segments.length() % 2 != 0 {
        raise @ghttp.HttpError::network_message(
          "parent document path must have even number of segments: \"\{path}\"",
        )
      }
      build_parent(self.project, self.database, path)
    }
  }
  let request = @gfs.ListCollectionIdsRequest::{
    parent: None,
    page_size,
    page_token,
    read_time: None,
  }
  let response = self.service.list_collection_ids(parent, request)
  let collection_ids = match response.collection_ids {
    Some(v) => v
    None => []
  }
  let next_page_token = match response.next_page_token {
    Some(v) => if v == "" { None } else { Some(v) }
    None => None
  }
  (collection_ids, next_page_token)
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
pub(all) enum Aggregator {
  Count
  Sum(String)
  Avg(String)
}

///|
pub(all) struct AggregationResult {
  alias_ : String
  value : @gfs.Value
}

///|
pub(all) struct AggregationExplainResult {
  results : Array[AggregationResult]
  metrics : @gfs.ExplainMetrics
}

///|
pub async fn FirestoreClient::aggregate(
  self : FirestoreClient,
  collection_path : String,
  aggregators : Array[(String, Aggregator)],
  where_? : @gfs.Filter,
) -> Array[AggregationResult] raise @ghttp.HttpError {
  let (parent_suffix, collection_id) = match
    split_collection_path(collection_path) {
    Ok(parts) => parts
    Err(msg) => raise @ghttp.HttpError::network_message(msg)
  }
  let parent = build_parent(self.project, self.database, parent_suffix)
  let gfs_aggregations : Array[@gfs.Aggregation] = []
  for entry in aggregators {
    let (alias_name, aggregator) = entry
    match aggregator {
      Count =>
        gfs_aggregations.push(@gfs.Aggregation::{
          count: Some(@gfs.Count::{ up_to: None }),
          sum: None,
          avg: None,
          alias_: Some(alias_name),
        })
      Sum(field_path) =>
        gfs_aggregations.push(@gfs.Aggregation::{
          count: None,
          sum: Some(@gfs.Sum::{
            field: Some(@gfs.FieldReference::{ field_path: Some(field_path) }),
          }),
          avg: None,
          alias_: Some(alias_name),
        })
      Avg(field_path) =>
        gfs_aggregations.push(@gfs.Aggregation::{
          count: None,
          sum: None,
          avg: Some(@gfs.Avg::{
            field: Some(@gfs.FieldReference::{ field_path: Some(field_path) }),
          }),
          alias_: Some(alias_name),
        })
    }
  }
  let request = @gfs.RunAggregationQueryRequest::{
    parent: None,
    structured_aggregation_query: Some(@gfs.StructuredAggregationQuery::{
      structured_query: Some(@gfs.StructuredQuery::{
        select: None,
        from: Some([
          @gfs.CollectionSelector::{
            collection_id: Some(collection_id),
            all_descendants: None,
          },
        ]),
        where_,
        order_by: None,
        start_at: None,
        end_at: None,
        offset: None,
        limit: None,
        find_nearest: None,
      }),
      aggregations: Some(gfs_aggregations),
    }),
    transaction: None,
    new_transaction: None,
    read_time: None,
    explain_options: None,
  }
  let responses = self.service.run_aggregation_query(parent, request)
  let results : Array[AggregationResult] = []
  for response in responses {
    match response.result {
      Some(result) =>
        match result.aggregate_fields {
          Some(fields) =>
            for key, value in fields {
              results.push(AggregationResult::{ alias_: key, value })
            }
          None => ()
        }
      None => ()
    }
  }
  results
}

///|
pub async fn FirestoreClient::explain_aggregate(
  self : FirestoreClient,
  collection_path : String,
  aggregators : Array[(String, Aggregator)],
  where_? : @gfs.Filter,
  analyze? : Bool = false,
) -> AggregationExplainResult raise @ghttp.HttpError {
  let (parent_suffix, collection_id) = match
    split_collection_path(collection_path) {
    Ok(parts) => parts
    Err(msg) => raise @ghttp.HttpError::network_message(msg)
  }
  let parent = build_parent(self.project, self.database, parent_suffix)
  let gfs_aggregations : Array[@gfs.Aggregation] = []
  for entry in aggregators {
    let (alias_name, aggregator) = entry
    match aggregator {
      Count =>
        gfs_aggregations.push(@gfs.Aggregation::{
          count: Some(@gfs.Count::{ up_to: None }),
          sum: None,
          avg: None,
          alias_: Some(alias_name),
        })
      Sum(field_path) =>
        gfs_aggregations.push(@gfs.Aggregation::{
          count: None,
          sum: Some(@gfs.Sum::{
            field: Some(@gfs.FieldReference::{ field_path: Some(field_path) }),
          }),
          avg: None,
          alias_: Some(alias_name),
        })
      Avg(field_path) =>
        gfs_aggregations.push(@gfs.Aggregation::{
          count: None,
          sum: None,
          avg: Some(@gfs.Avg::{
            field: Some(@gfs.FieldReference::{ field_path: Some(field_path) }),
          }),
          alias_: Some(alias_name),
        })
    }
  }
  let request = @gfs.RunAggregationQueryRequest::{
    parent: None,
    structured_aggregation_query: Some(@gfs.StructuredAggregationQuery::{
      structured_query: Some(@gfs.StructuredQuery::{
        select: None,
        from: Some([
          @gfs.CollectionSelector::{
            collection_id: Some(collection_id),
            all_descendants: None,
          },
        ]),
        where_,
        order_by: None,
        start_at: None,
        end_at: None,
        offset: None,
        limit: None,
        find_nearest: None,
      }),
      aggregations: Some(gfs_aggregations),
    }),
    transaction: None,
    new_transaction: None,
    read_time: None,
    explain_options: Some(@gfs.ExplainOptions::{ analyze: Some(analyze) }),
  }
  let responses = self.service.run_aggregation_query(parent, request)
  let results : Array[AggregationResult] = []
  let mut metrics : @gfs.ExplainMetrics? = None
  for response in responses {
    match response.result {
      Some(result) =>
        match result.aggregate_fields {
          Some(fields) =>
            for key, value in fields {
              results.push(AggregationResult::{ alias_: key, value })
            }
          None => ()
        }
      None => ()
    }
    match response.explain_metrics {
      Some(m) => metrics = Some(m)
      None => ()
    }
  }
  let explain_metrics = match metrics {
    Some(m) => m
    None =>
      raise @ghttp.HttpError::network_message(
        "explain metrics not found in aggregation response",
      )
  }
  AggregationExplainResult::{ results, metrics: explain_metrics }
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
pub(all) enum BatchGetResult {
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

///|
pub(all) struct QuerySpec {
  filter : @gfs.Filter?
  order_by : Array[@gfs.Order]?
  start_at : @gfs.Cursor?
  end_at : @gfs.Cursor?
  limit : Int?
  offset : Int?
}

///|
pub(all) struct QueryExplainResult {
  documents : Array[@gfs.Document]
  metrics : @gfs.ExplainMetrics
}

///|
fn extract_explain_metrics(
  responses : Array[@gfs.RunQueryResponse],
) -> @gfs.ExplainMetrics {
  if responses.is_empty() {
    @gfs.ExplainMetrics::{ plan_summary: None, execution_stats: None }
  } else {
    let last = responses[responses.length() - 1]
    match last.explain_metrics {
      Some(m) => m
      None => @gfs.ExplainMetrics::{ plan_summary: None, execution_stats: None }
    }
  }
}

///|
pub async fn FirestoreClient::query(
  self : FirestoreClient,
  collection_path : String,
  spec : QuerySpec,
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
    where_: spec.filter,
    order_by: spec.order_by,
    start_at: spec.start_at,
    end_at: spec.end_at,
    offset: spec.offset,
    limit: spec.limit,
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
pub async fn FirestoreClient::explain_query(
  self : FirestoreClient,
  collection_path : String,
  spec : QuerySpec,
  analyze? : Bool = false,
) -> QueryExplainResult raise @ghttp.HttpError {
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
    where_: spec.filter,
    order_by: spec.order_by,
    start_at: spec.start_at,
    end_at: spec.end_at,
    offset: spec.offset,
    limit: spec.limit,
    find_nearest: None,
  }
  let request = @gfs.RunQueryRequest::{
    parent: None,
    structured_query: Some(query),
    transaction: None,
    new_transaction: None,
    read_time: None,
    explain_options: Some(@gfs.ExplainOptions::{ analyze: Some(analyze) }),
  }
  let responses = self.service.run_query(parent, request)
  let docs : Array[@gfs.Document] = []
  for i in 0..<responses.length() {
    match responses[i].document {
      Some(doc) => docs.push(doc)
      None => ()
    }
  }
  QueryExplainResult::{
    documents: docs,
    metrics: extract_explain_metrics(responses),
  }
}
