///|
const USAGE =
  #|firestore <subcommand> [options]
  #|  get <collection_path>/<doc_id>
  #|  list <collection_path> [--page-size N] [--page-token TOKEN]
  #|  query <collection_path> --where FIELD=VALUE [--op OP] [--limit N]
  #|  create <collection_path> [--doc-id ID] --fields JSON
  #|  delete <collection_path>/<doc_id>
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
    None =>
      @firestore.FirestoreClient::new(google_client, project, database~)
  }
  match sub {
    "get" => cmd_get(fc, sub_args)
    "list" => cmd_list(fc, sub_args)
    "query" => cmd_query(fc, sub_args)
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
      "usage: firestore query <collection_path> --where FIELD=VALUE [--op OP] [--limit N]",
    )
  }
  let cp = args[0]
  let where_arg = match get_flag(args, "--where") {
    Some(s) => s
    None => raise CliError("--where FIELD=VALUE is required")
  }
  let (field, value_str) = match split_once(where_arg, "=") {
    Some(v) => v
    None => raise CliError("--where must be FIELD=VALUE, got \"\{where_arg}\"")
  }
  let op = match get_flag(args, "--op") {
    Some(s) => s
    None => "EQUAL"
  }
  let limit = match get_flag(args, "--limit") {
    Some(s) => {
      let n = @string.parse_int(s) catch {
        e => raise CliError("--limit: \{e}")
      }
      Some(n)
    }
    None => None
  }
  let docs = fc.query_collection(
    cp,
    field,
    op,
    @firestore.sv(value_str),
    limit?,
  ) catch {
    e => raise CliError("firestore: \{format_http_error(e)}")
  }
  let arr : Array[Json] = docs.iter().map(@firestore.document_to_json).collect()
  println(Json::array(arr).stringify(indent=2))
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
    raise CliError("usage: firestore delete <collection_path>/<doc_id>")
  }
  let (cp, doc_id) = match @firestore.split_doc_path(args[0]) {
    Ok(v) => v
    Err(e) => raise CliError(e)
  }
  fc.delete_document(cp, doc_id) catch {
    e => raise CliError("firestore: \{format_http_error(e)}")
  }
  let out : Map[String, Json] = {}
  out["deleted"] = Json::string(args[0])
  println(Json::object(out).stringify(indent=2))
  0
}

///|
fn format_http_error(e : @ghttp.HttpError) -> String {
  match e {
    NetworkError(m) => "network: \{m}"
    TimeoutError(m) => "timeout: \{m}"
    InvalidUrl(m) => "invalid url: \{m}"
  }
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
fn args_slice(args : Array[String], from : Int) -> Array[String] {
  let out : Array[String] = []
  let mut i = from
  while i < args.length() {
    out.push(args[i])
    i += 1
  }
  out
}
