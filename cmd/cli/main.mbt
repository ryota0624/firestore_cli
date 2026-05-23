///|
const USAGE =
  #|firestore <subcommand> [options]
  #|  get <collection_path>/<doc_id>
  #|  list <collection_path> [--page-size N] [--page-token TOKEN]
  #|  list-collections [--parent users/alice] [--page-size N] [--page-token TOKEN]
  #|  query <collection_path> [--where FIELD=VALUE] [--op OP] [--and FIELD=VALUE:OP ...]
  #|                         [--order FIELD[:asc|desc] ...] [--offset N] [--limit N]
  #|                         [--explain] [--analyze]
  #|  aggregate <collection_path> [--count [ALIAS]] [--sum FIELD[:ALIAS]] [--avg FIELD[:ALIAS]]
  #|                              [--where FIELD=VALUE] [--op OP] [--explain] [--analyze]
  #|  create <collection_path> [--doc-id ID] --fields JSON
  #|  delete <collection_path>/<doc_id> [<collection_path>/<doc_id> ...]
  #|
  #|query --ids-only: outputs one relative path per line (e.g. Col/docId), suitable for xargs delete
  #|query --op supports: EQUAL, NOT_EQUAL, LESS_THAN, GREATER_THAN, etc., IS_NULL, IS_NAN
  #|
  #|Global options:
  #|  --project ID             override GCP_PROJECT
  #|  --database ID            override FIRESTORE_DATABASE (default: "(default)")
  #|  --credentials PATH       use service account JSON at PATH (overrides ADC)
  #|
  #|Environment:
  #|  GCP_PROJECT (or GOOGLE_CLOUD_PROJECT)   required (or --project)
  #|  FIRESTORE_DATABASE                       default: (default)
  #|  FIRESTORE_EMULATOR_HOST                  emulator mode when set (e.g. http://127.0.0.1:8081)

///|
async fn main {
  let args = @sys.get_cli_args()
  let code = run(args) catch {
    err => {
      println("error: \{err}")
      1
    }
  }
  @sys.exit(code)
}

///|
suberror CliError {
  CliError(String)
}

///|
impl Show for CliError with output(self, logger) {
  let CliError(msg) = self
  logger.write_string(msg)
}

///|
/// グローバルフラグを args から抜き出し、(global_opts, remaining_args) を返す。
/// --project / --database / --credentials の値を受け取る。
struct GlobalOpts {
  project : String?
  database : String?
  credentials : String?
}

///|
fn parse_global_opts(args : Array[String]) -> (GlobalOpts, Array[String]) {
  let mut project : String? = None
  let mut database : String? = None
  let mut credentials : String? = None
  let remaining : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--project" && i + 1 < args.length() {
      project = Some(args[i + 1])
      i += 2
      continue
    }
    if a == "--database" && i + 1 < args.length() {
      database = Some(args[i + 1])
      i += 2
      continue
    }
    if a == "--credentials" && i + 1 < args.length() {
      credentials = Some(args[i + 1])
      i += 2
      continue
    }
    remaining.push(a)
    i += 1
  }
  (GlobalOpts::{ project, database, credentials }, remaining)
}

///|
async fn run(args : Array[String]) -> Int {
  // args[0] は実行ファイル名。subcommand 以前 / 以降どちらに現れても拾えるよう
  // 先に全体から global flag を抜き出す。
  let (gopts, rest) = parse_global_opts(args_slice(args, 1))
  if rest.length() < 1 {
    println(USAGE)
    return 2
  }
  let sub = rest[0]
  let sub_args = args_slice(rest, 1)
  if sub == "-h" || sub == "--help" || sub == "help" {
    println(USAGE)
    return 0
  }
  // Base config: env 由来。--project があれば missing も許容する。
  let (base_project, base_database, emulator_host) = match
    @firestore.Config::from_env() {
    Ok(c) => (c.project, c.database, c.emulator_host)
    Err(e) =>
      match gopts.project {
        Some(_) =>
          ("", "(default)", @sys.get_env_var("FIRESTORE_EMULATOR_HOST"))
        None => raise CliError("config: \{e}")
      }
  }
  let project = gopts.project.unwrap_or(base_project)
  let database = gopts.database.unwrap_or(base_database)
  if project == "" {
    raise CliError("config: missing GCP_PROJECT (set env or pass --project)")
  }
  let google_client = match emulator_host {
    Some(_) => {
      match gopts.credentials {
        Some(_) =>
          println(
            "warning: --credentials is ignored when FIRESTORE_EMULATOR_HOST is set",
          )
        None => ()
      }
      @firestore.build_emulator_client()
    }
    None =>
      match gopts.credentials {
        Some(path) =>
          match @firestore.build_production_client_from_service_account(path) {
            Ok(c) => c
            Err(e) => raise CliError("auth: \{e}")
          }
        None =>
          match @firestore.build_production_client() {
            Ok(c) => c
            Err(e) => raise CliError("auth: \{e}")
          }
      }
  }
  let fc = match emulator_host {
    Some(host) =>
      @firestore.FirestoreClient::new(
        google_client,
        project,
        database~,
        base_url=host,
      )
    None => @firestore.FirestoreClient::new(google_client, project, database~)
  }
  match sub {
    "get" => cmd_get(fc, sub_args)
    "list" => cmd_list(fc, sub_args)
    "list-collections" => cmd_list_collections(fc, sub_args)
    "query" => cmd_query(fc, sub_args)
    "aggregate" => cmd_aggregate(fc, sub_args)
    "create" => cmd_create(fc, sub_args)
    "delete" => cmd_delete(fc, sub_args)
    _ => {
      println(USAGE)
      raise CliError("unknown subcommand: \{sub}")
    }
  }
}

///|
async fn cmd_get(fc : @firestore.FirestoreClient, args : Array[String]) -> Int {
  if args.length() < 1 {
    raise CliError("usage: firestore get <collection_path>/<doc_id>")
  }
  let (cp, doc_id) = match @firestore.split_doc_path(args[0]) {
    Ok(v) => v
    Err(e) => raise CliError(e)
  }
  let doc = fc.get_document(cp, doc_id) catch {
    e => raise CliError("firestore: \{format_http_error(e)}")
  }
  println(@firestore.document_to_json(doc).stringify(indent=2))
  0
}

///|
async fn cmd_list(fc : @firestore.FirestoreClient, args : Array[String]) -> Int {
  if args.length() < 1 {
    raise CliError(
      "usage: firestore list <collection_path> [--page-size N] [--page-token T]",
    )
  }
  let cp = args[0]
  let page_size = match get_flag(args, "--page-size") {
    Some(s) => {
      let n = @string.parse_int(s) catch {
        e => raise CliError("--page-size: \{e}")
      }
      Some(n)
    }
    None => None
  }
  let page_token = get_flag(args, "--page-token")
  let resp = fc.list_documents(cp, page_size?, page_token?) catch {
    e => raise CliError("firestore: \{format_http_error(e)}")
  }
  let docs_json : Array[Json] = match resp.documents {
    Some(docs) => docs.iter().map(@firestore.document_to_json).collect()
    None => []
  }
  let out : Map[String, Json] = {}
  out["documents"] = Json::array(docs_json)
  match resp.next_page_token {
    Some(t) => out["next_page_token"] = Json::string(t)
    None => ()
  }
  println(Json::object(out).stringify(indent=2))
  0
}

///|
async fn cmd_query(
  fc : @firestore.FirestoreClient,
  args : Array[String],
) -> Int {
  if args.length() < 1 {
    raise CliError(
      "usage: firestore query <collection_path> [--where FIELD=VALUE] [--op OP] [--and FIELD=VALUE:OP ...] [--order FIELD[:asc|desc] ...] [--offset N] [--limit N] [--explain] [--analyze]",
    )
  }
  let cp = args[0]
  let filters : Array[@gfs.Filter] = []
  let op = get_flag(args, "--op").unwrap_or("EQUAL")
  match get_flag(args, "--where") {
    Some(where_arg) => {
      let (field, value_str) = parse_where_clause(where_arg)
      filters.push(make_field_filter(field, op, value_str))
    }
    None => ()
  }
  let and_flags = get_flags(args, "--and")
  for and_arg in and_flags {
    let (field, value_str, and_op) = parse_and_clause(and_arg)
    filters.push(make_field_filter(field, and_op, value_str))
  }
  let filter = combine_filters_and(filters)
  let order_specs = get_flags(args, "--order")
  let orders : Array[@gfs.Order] = []
  for order_spec in order_specs {
    orders.push(parse_order(order_spec))
  }
  let order_by = if orders.is_empty() { None } else { Some(orders) }
  let limit = match get_flag(args, "--limit") {
    Some(s) => {
      let n = @string.parse_int(s) catch {
        e => raise CliError("--limit: \{e}")
      }
      Some(n)
    }
    None => None
  }
  let offset = match get_flag(args, "--offset") {
    Some(s) => {
      let n = @string.parse_int(s) catch {
        e => raise CliError("--offset: \{e}")
      }
      Some(n)
    }
    None => None
  }
  let (parent_suffix, collection_id) = match
    @firestore.split_collection_path(cp) {
    Ok(parts) => parts
    Err(msg) => raise CliError(msg)
  }
  let parent = @firestore.build_parent(fc.project, fc.database, parent_suffix)
  let query = @gfs.StructuredQuery::{
    select: None,
    from: Some([
      @gfs.CollectionSelector::{
        collection_id: Some(collection_id),
        all_descendants: None,
      },
    ]),
    where_: filter,
    order_by,
    start_at: None,
    end_at: None,
    offset,
    limit,
    find_nearest: None,
  }
  let explain = has_flag(args, "--explain")
  let analyze = has_flag(args, "--analyze")
  if explain {
    let request = @gfs.RunQueryRequest::{
      parent: None,
      structured_query: Some(query),
      transaction: None,
      new_transaction: None,
      read_time: None,
      explain_options: Some(@gfs.ExplainOptions::{ analyze: Some(analyze) }),
    }
    let responses = fc.service.run_query(parent, request) catch {
      e => raise CliError("firestore: \{format_http_error(e)}")
    }
    let docs : Array[@gfs.Document] = []
    let mut metrics : @gfs.ExplainMetrics? = None
    for response in responses {
      match response.document {
        Some(doc) => docs.push(doc)
        None => ()
      }
      match response.explain_metrics {
        Some(m) => metrics = Some(m)
        None => ()
      }
    }
    let documents_json : Array[Json] = docs
      .iter()
      .map(@firestore.document_to_json)
      .collect()
    let out : Map[String, Json] = {}
    out["documents"] = Json::array(documents_json)
    out["metrics"] = explain_metrics_to_json(
      metrics.unwrap_or(@gfs.ExplainMetrics::{
        plan_summary: None,
        execution_stats: None,
      }),
    )
    println(Json::object(out).stringify(indent=2))
  } else {
    let ids_only = has_flag(args, "--ids-only")
    let request = @gfs.RunQueryRequest::{
      parent: None,
      structured_query: Some(query),
      transaction: None,
      new_transaction: None,
      read_time: None,
      explain_options: None,
    }
    let responses = fc.service.run_query(parent, request) catch {
      e => raise CliError("firestore: \{format_http_error(e)}")
    }
    let docs : Array[@gfs.Document] = []
    for response in responses {
      match response.document {
        Some(doc) => docs.push(doc)
        None => ()
      }
    }
    if ids_only {
      let doc_prefix = "projects/\{fc.project}/databases/\{fc.database}/documents/"
      for doc in docs {
        match doc.name {
          Some(name) =>
            if name.has_prefix(doc_prefix) {
              println(name[doc_prefix.length():].to_string())
            } else {
              println(name)
            }
          None => ()
        }
      }
    } else {
      let arr : Array[Json] = docs
        .iter()
        .map(@firestore.document_to_json)
        .collect()
      println(Json::array(arr).stringify(indent=2))
    }
  }
  0
}

///|
async fn cmd_list_collections(
  fc : @firestore.FirestoreClient,
  args : Array[String],
) -> Int {
  let parent = get_flag(args, "--parent")
  let page_size = match get_flag(args, "--page-size") {
    Some(s) => {
      let n = @string.parse_int(s) catch {
        e => raise CliError("--page-size: \{e}")
      }
      Some(n)
    }
    None => None
  }
  let page_token = get_flag(args, "--page-token")
  let (collection_ids, next_page_token) = match parent {
    Some(parent_doc_path) =>
      fc.list_collection_ids(parent_doc_path~, page_size?, page_token?) catch {
        e => raise CliError("firestore: \{format_http_error(e)}")
      }
    None =>
      fc.list_collection_ids(page_size?, page_token?) catch {
        e => raise CliError("firestore: \{format_http_error(e)}")
      }
  }
  let out : Map[String, Json] = {}
  out["collectionIds"] = Json::array(collection_ids.map(Json::string))
  match next_page_token {
    Some(token) => out["nextPageToken"] = Json::string(token)
    None => ()
  }
  println(Json::object(out).stringify(indent=2))
  0
}

///|
async fn cmd_aggregate(
  fc : @firestore.FirestoreClient,
  args : Array[String],
) -> Int {
  if args.length() < 1 {
    raise CliError(
      "usage: firestore aggregate <collection_path> [--count [ALIAS]] [--sum FIELD[:ALIAS]] [--avg FIELD[:ALIAS]] [--where FIELD=VALUE] [--op OP] [--explain] [--analyze]",
    )
  }
  let cp = args[0]
  let aggregations : Array[@gfs.Aggregation] = []
  let mut i = 1
  let mut count_index = 0
  while i < args.length() {
    let token = args[i]
    if token == "--count" {
      count_index += 1
      let mut alias_name = "count_\{count_index}"
      if i + 1 < args.length() && !is_flag_token(args[i + 1]) {
        alias_name = args[i + 1]
        i += 1
      }
      aggregations.push(@gfs.Aggregation::{
        count: Some(@gfs.Count::{ up_to: None }),
        sum: None,
        avg: None,
        alias_: Some(alias_name),
      })
      i += 1
      continue
    }
    if token == "--sum" {
      if i + 1 >= args.length() {
        raise CliError("--sum requires FIELD[:ALIAS]")
      }
      let (field, alias_name) = parse_agg_field_alias(args[i + 1], "sum")
      aggregations.push(@gfs.Aggregation::{
        count: None,
        sum: Some(@gfs.Sum::{
          field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
        }),
        avg: None,
        alias_: Some(alias_name),
      })
      i += 2
      continue
    }
    if token == "--avg" {
      if i + 1 >= args.length() {
        raise CliError("--avg requires FIELD[:ALIAS]")
      }
      let (field, alias_name) = parse_agg_field_alias(args[i + 1], "avg")
      aggregations.push(@gfs.Aggregation::{
        count: None,
        sum: None,
        avg: Some(@gfs.Avg::{
          field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
        }),
        alias_: Some(alias_name),
      })
      i += 2
      continue
    }
    i += 1
  }
  if aggregations.is_empty() {
    raise CliError(
      "at least one aggregator is required (--count, --sum, --avg)",
    )
  }

  let where_filter = match get_flag(args, "--where") {
    Some(where_arg) => {
      let op = get_flag(args, "--op").unwrap_or("EQUAL")
      let (field, value_str) = parse_where_clause(where_arg)
      Some(make_field_filter(field, op, value_str))
    }
    None => None
  }
  let explain = has_flag(args, "--explain")
  let analyze = has_flag(args, "--analyze")
  let (parent_suffix, collection_id) = match
    @firestore.split_collection_path(cp) {
    Ok(parts) => parts
    Err(msg) => raise CliError(msg)
  }
  let parent = @firestore.build_parent(fc.project, fc.database, parent_suffix)
  let query = @gfs.StructuredQuery::{
    select: None,
    from: Some([
      @gfs.CollectionSelector::{
        collection_id: Some(collection_id),
        all_descendants: None,
      },
    ]),
    where_: where_filter,
    order_by: None,
    start_at: None,
    end_at: None,
    offset: None,
    limit: None,
    find_nearest: None,
  }
  let request = @gfs.RunAggregationQueryRequest::{
    parent: None,
    structured_aggregation_query: Some(@gfs.StructuredAggregationQuery::{
      structured_query: Some(query),
      aggregations: Some(aggregations),
    }),
    transaction: None,
    new_transaction: None,
    read_time: None,
    explain_options: if explain {
      Some(@gfs.ExplainOptions::{ analyze: Some(analyze) })
    } else {
      None
    },
  }
  let responses = fc.service.run_aggregation_query(parent, request) catch {
    e => raise CliError("firestore: \{format_http_error(e)}")
  }
  let results : Array[Json] = []
  let mut metrics : @gfs.ExplainMetrics? = None
  for response in responses {
    match response.result {
      Some(result) =>
        match result.aggregate_fields {
          Some(fields) =>
            for key, value in fields {
              let item : Map[String, Json] = {}
              item["alias_"] = Json::string(key)
              item["value"] = @firestore.value_to_json(value)
              results.push(Json::object(item))
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
  if explain {
    let out : Map[String, Json] = {}
    out["results"] = Json::array(results)
    out["metrics"] = explain_metrics_to_json(
      metrics.unwrap_or(@gfs.ExplainMetrics::{
        plan_summary: None,
        execution_stats: None,
      }),
    )
    println(Json::object(out).stringify(indent=2))
  } else {
    println(Json::array(results).stringify(indent=2))
  }
  0
}

///|
async fn cmd_create(
  fc : @firestore.FirestoreClient,
  args : Array[String],
) -> Int {
  if args.length() < 1 {
    raise CliError(
      "usage: firestore create <collection_path> [--doc-id ID] --fields JSON",
    )
  }
  let cp = args[0]
  let fields_arg = match get_flag(args, "--fields") {
    Some(s) => s
    None => raise CliError("--fields JSON is required")
  }
  let doc_id = get_flag(args, "--doc-id")
  let parsed = @json.parse(fields_arg) catch {
    e => raise CliError("--fields: invalid JSON: \{e}")
  }
  let obj = match parsed {
    Json::Object(m) => m
    _ => raise CliError("--fields: JSON must be an object")
  }
  let fields : Map[String, @gfs.Value] = {}
  for key, value in obj {
    let v = match @firestore.json_to_value(value) {
      Ok(v) => v
      Err(msg) => raise CliError("--fields[\{key}]: \{msg}")
    }
    fields[key] = v
  }
  let doc = fc.create_document(cp, doc_id?, fields) catch {
    e => raise CliError("firestore: \{format_http_error(e)}")
  }
  println(@firestore.document_to_json(doc).stringify(indent=2))
  0
}

///|
async fn cmd_delete(
  fc : @firestore.FirestoreClient,
  args : Array[String],
) -> Int {
  if args.length() < 1 {
    raise CliError(
      "usage: firestore delete <collection_path>/<doc_id> [<collection_path>/<doc_id> ...]",
    )
  }
  let doc_prefix = "projects/\{fc.project}/databases/\{fc.database}/documents/"
  let full_names : Array[String] = []
  for arg in args {
    match @firestore.split_doc_path(arg) {
      Ok(_) => full_names.push(doc_prefix + arg)
      Err(e) => raise CliError(e)
    }
  }
  fc.batch_delete_documents(full_names) catch {
    e => raise CliError("firestore: \{format_http_error(e)}")
  }
  let out : Map[String, Json] = {}
  out["deleted"] = Json::array(args.map(Json::string))
  println(Json::object(out).stringify(indent=2))
  0
}

///|
fn format_http_error(e : @ghttp.HttpError) -> String {
  match e {
    NetworkError(m) =>
      if looks_like_upstream_api_error(m) {
        "upstream api error: \{m}"
      } else {
        "transport error: \{m}"
      }
    TimeoutError(m) => "timeout: \{m}"
    InvalidUrl(m) => "invalid configuration: \{m}"
  }
}

///|
/// @ghttp.HttpError currently does not expose structured upstream status/code.
/// Use narrowly-scoped message inspection to separate likely Firestore/API errors
/// from transport failures.
fn looks_like_upstream_api_error(message : String) -> Bool {
  message.contains("INVALID_ARGUMENT") ||
  message.contains("FAILED_PRECONDITION") ||
  message.contains("NOT_FOUND") ||
  message.contains("ALREADY_EXISTS") ||
  message.contains("PERMISSION_DENIED") ||
  message.contains("UNAUTHENTICATED") ||
  message.contains("RESOURCE_EXHAUSTED") ||
  message.contains("ABORTED") ||
  message.contains("OUT_OF_RANGE") ||
  message.contains("UNIMPLEMENTED") ||
  message.contains("INTERNAL") ||
  message.contains("UNAVAILABLE") ||
  message.contains("DATA_LOSS") ||
  message.contains("http status") ||
  message.contains("\"error\"")
}

///|
fn split_once(s : String, sep : String) -> (String, String)? {
  let idx = s.find(sep)
  match idx {
    Some(i) => Some((s[:i].to_string(), s[i + sep.length():].to_string()))
    None => None
  }
}

///|
fn get_flag(args : Array[String], flag : String) -> String? {
  let mut i = 0
  while i < args.length() {
    if args[i] == flag && i + 1 < args.length() {
      return Some(args[i + 1])
    }
    i += 1
  }
  None
}

///|
fn get_flags(args : Array[String], flag : String) -> Array[String] {
  let values : Array[String] = []
  let mut i = 0
  while i < args.length() {
    if args[i] == flag && i + 1 < args.length() {
      values.push(args[i + 1])
    }
    i += 1
  }
  values
}

///|
fn has_flag(args : Array[String], flag : String) -> Bool {
  let mut i = 0
  while i < args.length() {
    if args[i] == flag {
      return true
    }
    i += 1
  }
  false
}

///|
fn parse_where_clause(where_arg : String) -> (String, String) raise CliError {
  match split_once(where_arg, "=") {
    Some(v) => v
    None => raise CliError("--where must be FIELD=VALUE, got \"\{where_arg}\"")
  }
}

///|
fn parse_and_clause(
  and_arg : String,
) -> (String, String, String) raise CliError {
  let (field_eq_value, op) = match split_once(and_arg, ":") {
    Some(v) => v
    None => raise CliError("--and must be FIELD=VALUE:OP, got \"\{and_arg}\"")
  }
  let (field, value) = match split_once(field_eq_value, "=") {
    Some(v) => v
    None =>
      raise CliError(
        "--and must contain FIELD=VALUE before :OP, got \"\{and_arg}\"",
      )
  }
  (field, value, op)
}

///|
fn make_field_filter(
  field : String,
  op : String,
  value : String,
) -> @gfs.Filter {
  make_filter(field, op, value)
}

///|
/// IS_NULL / IS_NAN は unary_filter で処理し、それ以外は field_filter を使う。
fn make_filter(field : String, op : String, value : String) -> @gfs.Filter {
  if op == "IS_NULL" || op == "IS_NAN" {
    @gfs.Filter::{
      composite_filter: None,
      field_filter: None,
      unary_filter: Some(@gfs.UnaryFilter::{
        op: Some(op),
        field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
      }),
    }
  } else {
    @gfs.Filter::{
      composite_filter: None,
      field_filter: Some(@gfs.FieldFilter::{
        field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
        op: Some(op),
        value: Some(@firestore.sv(value)),
      }),
      unary_filter: None,
    }
  }
}

///|
fn combine_filters_and(filters : Array[@gfs.Filter]) -> @gfs.Filter? {
  if filters.is_empty() {
    None
  } else if filters.length() == 1 {
    Some(filters[0])
  } else {
    Some(@gfs.Filter::{
      composite_filter: Some(@gfs.CompositeFilter::{
        filters: Some(filters),
        op: Some("AND"),
      }),
      field_filter: None,
      unary_filter: None,
    })
  }
}

///|
fn parse_order(order_arg : String) -> @gfs.Order raise CliError {
  let (field, direction) = match split_once(order_arg, ":") {
    Some((f, dir)) =>
      (
        f,
        match dir {
          "asc" => "ASCENDING"
          "desc" => "DESCENDING"
          _ =>
            raise CliError(
              "--order direction must be asc or desc, got \"\{dir}\"",
            )
        },
      )
    None => (order_arg, "ASCENDING")
  }
  @gfs.Order::{
    field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
    direction: Some(direction),
  }
}

///|
fn parse_agg_field_alias(
  spec : String,
  kind : String,
) -> (String, String) raise CliError {
  match split_once(spec, ":") {
    Some((field, alias_name)) => {
      if field == "" {
        raise CliError("--\{kind} requires FIELD[:ALIAS], got \"\{spec}\"")
      }
      if alias_name == "" {
        raise CliError("--\{kind} alias must not be empty in \"\{spec}\"")
      }
      (field, alias_name)
    }
    None => {
      if spec == "" {
        raise CliError("--\{kind} requires FIELD[:ALIAS]")
      }
      (spec, default_agg_alias(kind, spec))
    }
  }
}

///|
fn default_agg_alias(kind : String, field : String) -> String {
  kind + "_" + sanitize_alias_part(field)
}

///|
fn sanitize_alias_part(s : String) -> String {
  let out = StringBuilder::new()
  let mut last_was_sep = false
  for c in s {
    if c is ('0'..='9' | 'a'..='z' | 'A'..='Z' | '_') {
      out.write_char(c)
      last_was_sep = false
    } else if !last_was_sep {
      out.write_char('_')
      last_was_sep = true
    }
  }
  let sanitized = out.to_string()
  if sanitized == "" {
    "value"
  } else {
    sanitized
  }
}

///|
fn is_flag_token(s : String) -> Bool {
  s.has_prefix("--")
}

///|
fn explain_metrics_to_json(metrics : @gfs.ExplainMetrics) -> Json {
  let obj : Map[String, Json] = {}
  obj["planSummary"] = match metrics.plan_summary {
    Some(v) => v.to_json()
    None => Json::null()
  }
  obj["executionStats"] = match metrics.execution_stats {
    Some(v) => v.to_json()
    None => Json::null()
  }
  Json::object(obj)
}

///|
fn args_slice(args : Array[String], from : Int) -> Array[String] {
  let out : Array[String] = []
  let mut i = from
  while i < args.length() {
    out.push(args[i])
    i += 1
  }
  out
}
