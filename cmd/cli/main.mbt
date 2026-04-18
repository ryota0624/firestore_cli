///|
const USAGE =
  #|firestire <subcommand> [options]
  #|  get <collection_path>/<doc_id>
  #|  list <collection_path> [--page-size N] [--page-token TOKEN]
  #|  query <collection_path> --where FIELD=VALUE [--op OP] [--limit N]
  #|
  #|Environment:
  #|  GCP_PROJECT (or GOOGLE_CLOUD_PROJECT)   required
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
async fn run(args : Array[String]) -> Int {
  if args.length() < 2 {
    println(USAGE)
    return 2
  }
  let sub = args[1]
  let sub_args = args_slice(args, 2)
  if sub == "-h" || sub == "--help" || sub == "help" {
    println(USAGE)
    return 0
  }
  let cfg = match @firestore.Config::from_env() {
    Ok(c) => c
    Err(e) => raise CliError("config: \{e}")
  }
  let google_client = match cfg.emulator_host {
    Some(_) => @firestore.build_emulator_client()
    None =>
      match @firestore.build_production_client() {
        Ok(c) => c
        Err(e) => raise CliError("auth: \{e}")
      }
  }
  let fc = match cfg.emulator_host {
    Some(host) =>
      @firestore.FirestoreClient::new(
        google_client,
        cfg.project,
        database=cfg.database,
        base_url=host,
      )
    None =>
      @firestore.FirestoreClient::new(
        google_client,
        cfg.project,
        database=cfg.database,
      )
  }
  match sub {
    "get" => cmd_get(fc, sub_args)
    "list" => cmd_list(fc, sub_args)
    "query" => cmd_query(fc, sub_args)
    _ => {
      println(USAGE)
      raise CliError("unknown subcommand: \{sub}")
    }
  }
}

///|
async fn cmd_get(fc : @firestore.FirestoreClient, args : Array[String]) -> Int {
  if args.length() < 1 {
    raise CliError("usage: firestire get <collection_path>/<doc_id>")
  }
  let (cp, doc_id) = match split_doc_path(args[0]) {
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
      "usage: firestire list <collection_path> [--page-size N] [--page-token T]",
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
      "usage: firestire query <collection_path> --where FIELD=VALUE [--op OP] [--limit N]",
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
fn split_doc_path(path : String) -> Result[(String, String), String] {
  let segs : Array[String] = path
    .split("/")
    .map(fn(v) { v.to_string() })
    .collect()
  if segs.length() < 2 {
    return Err("document path must contain at least 2 segments: \"\{path}\"")
  }
  let last = segs[segs.length() - 1]
  let head : Array[String] = []
  let mut i = 0
  while i < segs.length() - 1 {
    head.push(segs[i])
    i += 1
  }
  if head.length() % 2 == 0 {
    return Err(
      "collection path must have an odd segment count (got \{head.length()}): \"\{path}\"",
    )
  }
  Ok((head.join("/"), last))
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
