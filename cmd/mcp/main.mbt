///|
struct Reader {
  client : @firestore.FirestoreClient
}

///|
fn json_to_value(j : Json) -> @gfs.Value raise @ghttp.HttpError {
  match j {
    Json::Null => @firestore.nullv()
    Json::True => @firestore.bv(true)
    Json::False => @firestore.bv(false)
    Json::Number(n, ..) => {
      let i = n.to_int64()
      if i.to_double() == n {
        @firestore.iv(i)
      } else {
        @firestore.dv(n)
      }
    }
    Json::String(s) => @firestore.sv(s)
    Json::Array(_) | Json::Object(_) =>
      raise @ghttp.HttpError::network_message(
        "MCP query value: only JSON primitives (null, boolean, number, string) are supported",
      )
  }
}

///|
fn list_response_to_json(resp : @gfs.ListDocumentsResponse) -> Json {
  let docs = resp.documents
    .unwrap_or([])
    .map(fn(d) { @firestore.document_to_json(d) })
  Json::object({
    "documents": Json::array(docs),
    "nextPageToken": match resp.next_page_token {
      Some(t) => Json::string(t)
      None => Json::null()
    },
  })
}

///|
fn query_results_to_json(docs : Array[@gfs.Document]) -> Json {
  Json::array(docs.map(fn(d) { @firestore.document_to_json(d) }))
}

///|
fn map_require_str(
  m : Map[String, Json],
  key : String,
) -> String raise @ghttp.HttpError {
  match m.get(key) {
    Some(Json::String(s)) => s
    _ => raise @ghttp.HttpError::network_message("missing or invalid \{key}")
  }
}

///|
fn map_opt_int_strict(
  m : Map[String, Json],
  key : String,
) -> Int? raise @ghttp.HttpError {
  match m.get(key) {
    None | Some(Json::Null) => None
    Some(Json::Number(n, ..)) => Some(n.to_int())
    Some(_) => raise @ghttp.HttpError::network_message("invalid \{key}")
  }
}

///|
fn parse_int64_decimal_string(s : String) -> Int64 raise @ghttp.HttpError {
  let mut acc : Int64 = 0L
  let mut neg = false
  let mut any_digit = false
  let mut first = true
  for ch in s.iter() {
    if first && ch == '-' {
      neg = true
      first = false
      continue
    }
    first = false
    if !ch.is_ascii_digit() {
      raise @ghttp.HttpError::network_message("invalid integerValue")
    }
    any_digit = true
    let d = ch.to_int() - '0'.to_int()
    acc = acc * 10L + Int64::from_int(d)
  }
  if !any_digit {
    raise @ghttp.HttpError::network_message("empty integerValue")
  }
  if neg {
    -acc
  } else {
    acc
  }
}

///|
fn gfs_value_from_json(j : Json) -> @gfs.Value raise @ghttp.HttpError {
  match @firestore.json_to_value(j) {
    Ok(v) => v
    Err(_) =>
      match j {
        Json::Object(m) => {
          match m.get("stringValue") {
            Some(Json::String(s)) => return @firestore.sv(s)
            _ => ()
          }
          match m.get("integerValue") {
            Some(Json::Number(n, ..)) => return @firestore.iv(n.to_int64())
            Some(Json::String(s)) =>
              return @firestore.iv(parse_int64_decimal_string(s))
            _ => ()
          }
          match m.get("doubleValue") {
            Some(Json::Number(n, ..)) => return @firestore.dv(n)
            _ => ()
          }
          match m.get("booleanValue") {
            Some(Json::True) => return @firestore.bv(true)
            Some(Json::False) => return @firestore.bv(false)
            _ => ()
          }
          match m.get("nullValue") {
            Some(_) => return @firestore.nullv()
            None => ()
          }
          match m.get("timestampValue") {
            Some(Json::String(s)) =>
              return @gfs.Value::{
                null_value: None,
                boolean_value: None,
                integer_value: None,
                double_value: None,
                timestamp_value: Some(s),
                string_value: None,
                bytes_value: None,
                reference_value: None,
                geo_point_value: None,
                array_value: None,
                map_value: None,
                field_reference_value: None,
                variable_reference_value: None,
                function_value: None,
                pipeline_value: None,
              }
            _ => ()
          }
          match m.get("bytesValue") {
            Some(Json::String(s)) =>
              return @gfs.Value::{
                null_value: None,
                boolean_value: None,
                integer_value: None,
                double_value: None,
                timestamp_value: None,
                string_value: None,
                bytes_value: Some(s),
                reference_value: None,
                geo_point_value: None,
                array_value: None,
                map_value: None,
                field_reference_value: None,
                variable_reference_value: None,
                function_value: None,
                pipeline_value: None,
              }
            _ => ()
          }
          match m.get("referenceValue") {
            Some(Json::String(s)) =>
              return @gfs.Value::{
                null_value: None,
                boolean_value: None,
                integer_value: None,
                double_value: None,
                timestamp_value: None,
                string_value: None,
                bytes_value: None,
                reference_value: Some(s),
                geo_point_value: None,
                array_value: None,
                map_value: None,
                field_reference_value: None,
                variable_reference_value: None,
                function_value: None,
                pipeline_value: None,
              }
            _ => ()
          }
          match m.get("geoPointValue") {
            Some(gj) =>
              return @gfs.Value::{
                null_value: None,
                boolean_value: None,
                integer_value: None,
                double_value: None,
                timestamp_value: None,
                string_value: None,
                bytes_value: None,
                reference_value: None,
                geo_point_value: Some(gj),
                array_value: None,
                map_value: None,
                field_reference_value: None,
                variable_reference_value: None,
                function_value: None,
                pipeline_value: None,
              }
            None => ()
          }
          match m.get("arrayValue") {
            Some(Json::Object(am)) => {
              let vals_j = match am.get("values") {
                Some(Json::Array(items)) => items
                _ =>
                  raise @ghttp.HttpError::network_message(
                    "arrayValue.values must be array",
                  )
              }
              let vals : Array[@gfs.Value] = []
              for vj in vals_j {
                vals.push(gfs_value_from_json(vj))
              }
              return @gfs.Value::{
                null_value: None,
                boolean_value: None,
                integer_value: None,
                double_value: None,
                timestamp_value: None,
                string_value: None,
                bytes_value: None,
                reference_value: None,
                geo_point_value: None,
                array_value: Some(@gfs.ArrayValue::{ values: Some(vals) }),
                map_value: None,
                field_reference_value: None,
                variable_reference_value: None,
                function_value: None,
                pipeline_value: None,
              }
            }
            _ => ()
          }
          match m.get("mapValue") {
            Some(Json::Object(mv)) => {
              let fm = match mv.get("fields") {
                Some(Json::Object(fields)) => fields
                _ =>
                  raise @ghttp.HttpError::network_message(
                    "mapValue.fields must be object",
                  )
              }
              let fields : Map[String, @gfs.Value] = {}
              for k, vj in fm {
                fields[k] = gfs_value_from_json(vj)
              }
              return @gfs.Value::{
                null_value: None,
                boolean_value: None,
                integer_value: None,
                double_value: None,
                timestamp_value: None,
                string_value: None,
                bytes_value: None,
                reference_value: None,
                geo_point_value: None,
                array_value: None,
                map_value: Some(@gfs.MapValue::{ fields: Some(fields) }),
                field_reference_value: None,
                variable_reference_value: None,
                function_value: None,
                pipeline_value: None,
              }
            }
            _ => ()
          }
          raise @ghttp.HttpError::network_message(
            "unsupported Firestore Value JSON",
          )
        }
        _ =>
          raise @ghttp.HttpError::network_message(
            "unsupported Firestore Value JSON",
          )
      }
  }
}

///|
fn field_path_from_field_json(j : Json) -> String raise @ghttp.HttpError {
  match j {
    Json::String(s) => s
    Json::Object(fm) =>
      match fm.get("fieldPath") {
        Some(Json::String(fp)) => fp
        _ =>
          raise @ghttp.HttpError::network_message(
            "field.fieldPath must be string",
          )
      }
    _ =>
      raise @ghttp.HttpError::network_message(
        "field must be string or { fieldPath }",
      )
  }
}

///|
fn field_filter_from_json(j : Json) -> @gfs.FieldFilter raise @ghttp.HttpError {
  guard j is Object(m) else {
    raise @ghttp.HttpError::network_message("fieldFilter must be object")
  }
  let field_j = match m.get("field") {
    Some(f) => f
    None =>
      raise @ghttp.HttpError::network_message("fieldFilter.field required")
  }
  let fp = field_path_from_field_json(field_j)
  let op = match m.get("op") {
    Some(Json::String(s)) => Some(s)
    _ =>
      raise @ghttp.HttpError::network_message("fieldFilter.op must be string")
  }
  let vj = match m.get("value") {
    Some(v) => v
    None =>
      raise @ghttp.HttpError::network_message("fieldFilter.value required")
  }
  @gfs.FieldFilter::{
    field: Some(@gfs.FieldReference::{ field_path: Some(fp) }),
    op,
    value: Some(gfs_value_from_json(vj)),
  }
}

///|
fn composite_filter_from_json(
  j : Json,
) -> @gfs.CompositeFilter raise @ghttp.HttpError {
  guard j is Object(m) else {
    raise @ghttp.HttpError::network_message("compositeFilter must be object")
  }
  let op = match m.get("op") {
    Some(Json::String(s)) => Some(s)
    _ => raise @ghttp.HttpError::network_message("compositeFilter.op required")
  }
  let filters_j = match m.get("filters") {
    Some(Json::Array(arr)) => arr
    _ =>
      raise @ghttp.HttpError::network_message(
        "compositeFilter.filters must be array",
      )
  }
  let parts : Array[@gfs.Filter] = []
  for fj in filters_j {
    parts.push(filter_from_json(fj))
  }
  @gfs.CompositeFilter::{ op, filters: Some(parts) }
}

///|
fn unary_filter_from_json(j : Json) -> @gfs.UnaryFilter raise @ghttp.HttpError {
  guard j is Object(m) else {
    raise @ghttp.HttpError::network_message("unaryFilter must be object")
  }
  let op = match m.get("op") {
    Some(Json::String(s)) => Some(s)
    _ =>
      raise @ghttp.HttpError::network_message("unaryFilter.op must be string")
  }
  let field_j = match m.get("field") {
    Some(f) => f
    None =>
      raise @ghttp.HttpError::network_message("unaryFilter.field required")
  }
  let fp = field_path_from_field_json(field_j)
  @gfs.UnaryFilter::{
    op,
    field: Some(@gfs.FieldReference::{ field_path: Some(fp) }),
  }
}

///|
fn filter_from_json(j : Json) -> @gfs.Filter raise @ghttp.HttpError {
  guard j is Object(m) else {
    raise @ghttp.HttpError::network_message("filter must be object")
  }
  match (m.get("compositeFilter"), m.get("fieldFilter"), m.get("unaryFilter")) {
    (Some(cj), None, None) =>
      @gfs.Filter::{
        composite_filter: Some(composite_filter_from_json(cj)),
        field_filter: None,
        unary_filter: None,
      }
    (None, Some(fj), None) =>
      @gfs.Filter::{
        composite_filter: None,
        field_filter: Some(field_filter_from_json(fj)),
        unary_filter: None,
      }
    (None, None, Some(uj)) =>
      @gfs.Filter::{
        composite_filter: None,
        field_filter: None,
        unary_filter: Some(unary_filter_from_json(uj)),
      }
    (None, None, None) => {
      let has_field = match m.get("field") {
        Some(Json::String(_)) | Some(Json::Object(_)) => true
        _ => false
      }
      let has_op = match m.get("op") {
        Some(Json::String(_)) => true
        _ => false
      }
      let has_val = match m.get("value") {
        None | Some(Json::Null) => false
        Some(_) => true
      }
      if has_field && has_op && has_val {
        @gfs.Filter::{
          composite_filter: None,
          field_filter: Some(field_filter_from_json(j)),
          unary_filter: None,
        }
      } else {
        raise @ghttp.HttpError::network_message(
          "filter: expected compositeFilter, fieldFilter, unaryFilter, or shorthand field/op/value",
        )
      }
    }
    _ =>
      raise @ghttp.HttpError::network_message(
        "filter: exactly one of compositeFilter, fieldFilter, unaryFilter, or shorthand",
      )
  }
}

///|
fn order_from_json(j : Json) -> @gfs.Order raise @ghttp.HttpError {
  guard j is Object(m) else {
    raise @ghttp.HttpError::network_message("order_by entry must be object")
  }
  match m.get("fieldPath") {
    Some(Json::String(fp)) => {
      let direction = match m.get("direction") {
        Some(Json::String(d)) => Some(d)
        None | Some(Json::Null) => None
        _ =>
          raise @ghttp.HttpError::network_message(
            "order direction must be string",
          )
      }
      return @gfs.Order::{
        field: Some(@gfs.FieldReference::{ field_path: Some(fp) }),
        direction,
      }
    }
    _ => ()
  }
  let field_j = match m.get("field") {
    Some(f) => f
    None =>
      raise @ghttp.HttpError::network_message(
        "order_by: field or fieldPath required",
      )
  }
  let fp = field_path_from_field_json(field_j)
  let direction = match m.get("direction") {
    Some(Json::String(d)) => Some(d)
    None | Some(Json::Null) => None
    _ =>
      raise @ghttp.HttpError::network_message("order direction must be string")
  }
  @gfs.Order::{
    field: Some(@gfs.FieldReference::{ field_path: Some(fp) }),
    direction,
  }
}

///|
fn cursor_from_json(j : Json) -> @gfs.Cursor raise @ghttp.HttpError {
  guard j is Object(m) else {
    raise @ghttp.HttpError::network_message("cursor must be object")
  }
  let vals_j = match m.get("values") {
    Some(Json::Array(items)) => items
    _ => raise @ghttp.HttpError::network_message("cursor.values must be array")
  }
  let vals : Array[@gfs.Value] = []
  for vj in vals_j {
    vals.push(gfs_value_from_json(vj))
  }
  let before = match m.get("before") {
    None | Some(Json::Null) => None
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ =>
      raise @ghttp.HttpError::network_message("cursor.before must be boolean")
  }
  @gfs.Cursor::{ values: Some(vals), before }
}

///|
fn order_by_from_map(
  m : Map[String, Json],
) -> Array[@gfs.Order]? raise @ghttp.HttpError {
  let j = match m.get("order_by") {
    Some(x) => Some(x)
    None => m.get("orderBy")
  }
  match j {
    None | Some(Json::Null) => None
    Some(Json::Array(arr)) => {
      let out : Array[@gfs.Order] = []
      for x in arr {
        out.push(order_from_json(x))
      }
      Some(out)
    }
    _ =>
      raise @ghttp.HttpError::network_message("order_by must be array or null")
  }
}

///|
fn cursor_opt_from_map(
  m : Map[String, Json],
  snake : String,
  camel : String,
) -> @gfs.Cursor? raise @ghttp.HttpError {
  let j = match m.get(snake) {
    Some(x) => Some(x)
    None => m.get(camel)
  }
  match j {
    None | Some(Json::Null) => None
    Some(x) => Some(cursor_from_json(x))
  }
}

///|
fn query_spec_from_map_args(
  m : Map[String, Json],
  filter_override : @gfs.Filter?,
) -> @firestore.QuerySpec raise @ghttp.HttpError {
  let flt = match filter_override {
    Some(f) => Some(f)
    None =>
      match m.get("filter") {
        None | Some(Json::Null) => None
        Some(j) => Some(filter_from_json(j))
      }
  }
  let order_by = order_by_from_map(m)
  let start_at = cursor_opt_from_map(m, "start_at", "startAt")
  let end_at = cursor_opt_from_map(m, "end_at", "endAt")
  let offset = map_opt_int_strict(m, "offset")
  let limit = map_opt_int_strict(m, "limit")
  @firestore.QuerySpec::new(flt, order_by, start_at, end_at, limit, offset)
}

///|
fn has_query_extensions(m : Map[String, Json]) -> Bool {
  let keys : Array[String] = [
    "order_by", "orderBy", "start_at", "startAt", "end_at", "endAt", "offset",
  ]
  for k in keys {
    match m.get(k) {
      Some(Json::Null) | None => ()
      Some(_) => return true
    }
  }
  false
}

///|
fn field_filter_from_shorthand(
  field : String,
  op : String,
  value_j : Json,
) -> @gfs.FieldFilter raise @ghttp.HttpError {
  @gfs.FieldFilter::{
    field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
    op: Some(op),
    value: Some(gfs_value_from_json(value_j)),
  }
}

///|
fn aggregation_results_to_json(
  results : Array[@firestore.AggregationResult],
) -> Json {
  let items : Array[Json] = []
  for r in results {
    items.push(
      Json::object({
        "alias": Json::string(r.alias_),
        "value": @firestore.value_to_json(r.value),
      }),
    )
  }
  Json::array(items)
}

///|
fn explain_metrics_to_json(metrics : @gfs.ExplainMetrics) -> Json {
  Json::object({
    "planSummary": match metrics.plan_summary {
      Some(ps) =>
        Json::object({
          "indexesUsed": match ps.indexes_used {
            Some(arr) => Json::array(arr)
            None => Json::null()
          },
        })
      None => Json::null()
    },
    "executionStats": match metrics.execution_stats {
      Some(es) =>
        Json::object({
          "resultsReturned": match es.results_returned {
            Some(s) => Json::string(s)
            None => Json::null()
          },
          "executionDuration": match es.execution_duration {
            Some(s) => Json::string(s)
            None => Json::null()
          },
          "readOperations": match es.read_operations {
            Some(s) => Json::string(s)
            None => Json::null()
          },
          "debugStats": match es.debug_stats {
            Some(d) => d
            None => Json::null()
          },
        })
      None => Json::null()
    },
  })
}

///|
fn aggregators_from_json(
  j : Json,
) -> Array[(String, @firestore.Aggregator)] raise @ghttp.HttpError {
  guard j is Array(arr) else {
    raise @ghttp.HttpError::network_message("aggregators must be array")
  }
  let out : Array[(String, @firestore.Aggregator)] = []
  for item in arr {
    guard item is Object(m) else {
      raise @ghttp.HttpError::network_message("each aggregator must be object")
    }
    let agg_name = match m.get("alias") {
      Some(Json::String(a)) => a
      _ => raise @ghttp.HttpError::network_message("aggregator.alias required")
    }
    let typ = match m.get("type") {
      Some(Json::String(t)) => t
      _ => raise @ghttp.HttpError::network_message("aggregator.type required")
    }
    match typ {
      "count" => out.push((agg_name, @firestore.aggregators_count()))
      "sum" => {
        let field = match m.get("field") {
          Some(Json::String(f)) => f
          _ =>
            raise @ghttp.HttpError::network_message(
              "aggregator.field required for sum",
            )
        }
        out.push((agg_name, @firestore.aggregators_sum(field)))
      }
      "avg" => {
        let field = match m.get("field") {
          Some(Json::String(f)) => f
          _ =>
            raise @ghttp.HttpError::network_message(
              "aggregator.field required for avg",
            )
        }
        out.push((agg_name, @firestore.aggregators_avg(field)))
      }
      _ =>
        raise @ghttp.HttpError::network_message(
          "aggregator.type must be count, sum, or avg",
        )
    }
  }
  out
}

///|
fn aggregate_where_clause(j : Json) -> @gfs.Filter raise @ghttp.HttpError {
  guard j is Object(m) else {
    raise @ghttp.HttpError::network_message("where must be object")
  }
  if m.contains("compositeFilter") ||
    m.contains("fieldFilter") ||
    m.contains("unaryFilter") {
    filter_from_json(j)
  } else {
    let field = map_require_str(m, "field")
    let op = map_require_str(m, "op")
    let vj = match m.get("value") {
      Some(v) => v
      None => raise @ghttp.HttpError::network_message("where.value required")
    }
    @gfs.Filter::{
      composite_filter: None,
      field_filter: Some(field_filter_from_shorthand(field, op, vj)),
      unary_filter: None,
    }
  }
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with get_document(
  self,
  collection_path : String,
  doc_id : String,
) {
  let doc = self.client.get_document(collection_path, doc_id)
  @firestore.document_to_json(doc)
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with list_documents(
  self,
  collection_path : String,
  page_size : Int?,
  page_token : String?,
) {
  let resp = match (page_size, page_token) {
    (Some(ps), Some(pt)) =>
      self.client.list_documents(collection_path, page_size=ps, page_token=pt)
    (Some(ps), None) =>
      self.client.list_documents(collection_path, page_size=ps)
    (None, Some(pt)) =>
      self.client.list_documents(collection_path, page_token=pt)
    (None, None) => self.client.list_documents(collection_path)
  }
  list_response_to_json(resp)
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with list_collection_ids(
  self,
  parent_doc_path : String?,
  page_size : Int?,
  page_token : String?,
) {
  let (ids, next_tok) = match (parent_doc_path, page_size, page_token) {
    (Some(p), Some(ps), Some(pt)) =>
      self.client.list_collection_ids(
        parent_doc_path=p,
        page_size=ps,
        page_token=pt,
      )
    (Some(p), Some(ps), None) =>
      self.client.list_collection_ids(parent_doc_path=p, page_size=ps)
    (Some(p), None, Some(pt)) =>
      self.client.list_collection_ids(parent_doc_path=p, page_token=pt)
    (Some(p), None, None) => self.client.list_collection_ids(parent_doc_path=p)
    (None, Some(ps), Some(pt)) =>
      self.client.list_collection_ids(page_size=ps, page_token=pt)
    (None, Some(ps), None) => self.client.list_collection_ids(page_size=ps)
    (None, None, Some(pt)) => self.client.list_collection_ids(page_token=pt)
    (None, None, None) => self.client.list_collection_ids()
  }
  Json::object({
    "collectionIds": Json::array(ids.map(fn(s) { Json::string(s) })),
    "nextPageToken": match next_tok {
      Some(t) => Json::string(t)
      None => Json::null()
    },
  })
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with aggregate(
  self,
  collection_path : String,
  aggregators : Json,
  where_ : Json?,
) {
  let aggs = aggregators_from_json(aggregators)
  let wf = match where_ {
    None => None
    Some(j) => Some(aggregate_where_clause(j))
  }
  let results = match wf {
    None => self.client.aggregate(collection_path, aggs)
    Some(f) => self.client.aggregate(collection_path, aggs, where_=f)
  }
  aggregation_results_to_json(results)
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with explain_aggregate(
  self,
  collection_path : String,
  aggregators : Json,
  where_ : Json?,
  analyze : Bool?,
) {
  let aggs = aggregators_from_json(aggregators)
  let wf = match where_ {
    None => None
    Some(j) => Some(aggregate_where_clause(j))
  }
  let analyze_flag = analyze.unwrap_or(false)
  let res = match wf {
    None =>
      self.client.explain_aggregate(collection_path, aggs, analyze=analyze_flag)
    Some(f) =>
      self.client.explain_aggregate(
        collection_path,
        aggs,
        where_=f,
        analyze=analyze_flag,
      )
  }
  Json::object({
    "results": aggregation_results_to_json(res.results),
    "metrics": explain_metrics_to_json(res.metrics),
  })
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with explain_query(
  self,
  collection_path : String,
  spec : Json,
  analyze : Bool?,
) {
  guard spec is Object(spec_map) else {
    raise @ghttp.HttpError::network_message("spec must be object")
  }
  let qs = query_spec_from_map_args(spec_map, None)
  let analyze_flag = analyze.unwrap_or(false)
  let r = self.client.explain_query(collection_path, qs, analyze=analyze_flag)
  Json::object({
    "documents": Json::array(r.documents.map(@firestore.document_to_json)),
    "metrics": explain_metrics_to_json(r.metrics),
  })
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with query_collection(
  self,
  args : Map[String, Json],
) {
  let cp = map_require_str(args, "collection_path")
  let has_filter_key = match args.get("filter") {
    None | Some(Json::Null) => false
    Some(_) => true
  }
  if has_filter_key {
    let spec = query_spec_from_map_args(args, None)
    let docs = self.client.query(cp, spec)
    return query_results_to_json(docs)
  }
  let field_opt = match args.get("field") {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
  let op_opt = match args.get("op") {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
  let has_value = match args.get("value") {
    None | Some(Json::Null) => false
    Some(_) => true
  }
  let legacy_triple = match (field_opt, op_opt, has_value) {
    (Some(_), Some(_), true) => true
    _ => false
  }
  if !legacy_triple {
    if field_opt is Some(_) || op_opt is Some(_) || has_value {
      raise @ghttp.HttpError::network_message(
        "field, op, and value must all be set together (unless using filter)",
      )
    }
  }
  let has_ext = has_query_extensions(args)
  if legacy_triple && !has_ext {
    let v = json_to_value(
      match args.get("value") {
        Some(val) => val
        None =>
          raise @ghttp.HttpError::network_message("missing value for query")
      },
    )
    let lim = map_opt_int_strict(args, "limit")
    let docs = match lim {
      Some(lim) =>
        self.client.query_collection(
          cp,
          field_opt.unwrap(),
          op_opt.unwrap(),
          v,
          limit=lim,
        )
      None =>
        self.client.query_collection(cp, field_opt.unwrap(), op_opt.unwrap(), v)
    }
    return query_results_to_json(docs)
  }
  let flt = if legacy_triple && has_ext {
    Some(@gfs.Filter::{
      composite_filter: None,
      field_filter: Some(
        field_filter_from_shorthand(
          field_opt.unwrap(),
          op_opt.unwrap(),
          match args.get("value") {
            Some(val) => val
            None => raise @ghttp.HttpError::network_message("missing value")
          },
        ),
      ),
      unary_filter: None,
    })
  } else {
    None
  }
  let spec = query_spec_from_map_args(args, flt)
  let docs = self.client.query(cp, spec)
  query_results_to_json(docs)
}

///|
pub impl @mcp_lib.FirestoreReader for Reader with batch_get(
  self,
  doc_paths : Array[String],
) {
  let results = self.client.batch_get_documents(doc_paths)
  let arr : Array[Json] = []
  for r in results {
    match r {
      @firestore.BatchGetResult::Found(doc) =>
        arr.push(Json::object({ "found": @firestore.document_to_json(doc) }))
      @firestore.BatchGetResult::Missing(name) =>
        arr.push(Json::object({ "missing": Json::string(name) }))
    }
  }
  Json::array(arr)
}

///|
pub impl @mcp_lib.FirestoreWriter for Reader with create_document(
  self,
  collection_path,
  doc_id,
  fields,
) {
  let converted : Map[String, @gfs.Value] = {}
  for k, v in fields {
    converted[k] = json_to_value(v)
  }
  let doc = match doc_id {
    Some(id) =>
      self.client.create_document(collection_path, doc_id=id, converted)
    None => self.client.create_document(collection_path, converted)
  }
  @firestore.document_to_json(doc)
}

///|
pub impl @mcp_lib.FirestoreWriter for Reader with delete_document(
  self,
  collection_path,
  doc_id,
) {
  self.client.delete_document(collection_path, doc_id)
}

///|
async fn run_with_client(
  client : @firestore.FirestoreClient,
  read_only : Bool,
) -> Unit {
  let reader = Reader::{ client, }
  @mcp_lib.run_server(reader, reader, read_only~)
}

///|
async fn main {
  let args = @sys.get_cli_args()
  let read_only = args.iter().any(fn(a) { a == "--readonly" })
  match @firestore.Config::from_env() {
    Err(e) => {
      @mcp_lib.log("config error: \{e}")
      @sys.exit(1)
    }
    Ok(cfg) =>
      match cfg.emulator_host {
        Some(_) => {
          let google = @firestore.build_emulator_client()
          let fc = @firestore.FirestoreClient::new(
            google,
            cfg.project,
            database=cfg.database,
            base_url?=cfg.emulator_host,
          )
          run_with_client(fc, read_only)
        }
        None =>
          match @firestore.build_production_client() {
            Err(e) => {
              @mcp_lib.log("auth error: \{e}")
              @sys.exit(1)
            }
            Ok(google) => {
              let fc = @firestore.FirestoreClient::new(
                google,
                cfg.project,
                database=cfg.database,
              )
              run_with_client(fc, read_only)
            }
          }
      }
  }
}
