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
pub impl @mcp_lib.FirestoreReader for Reader with query_collection(
  self,
  collection_path : String,
  field : String,
  op : String,
  value : Json,
  limit : Int?,
) {
  let v = json_to_value(value)
  let docs = match limit {
    Some(lim) =>
      self.client.query_collection(collection_path, field, op, v, limit=lim)
    None => self.client.query_collection(collection_path, field, op, v)
  }
  query_results_to_json(docs)
}

///|
async fn run_with_client(client : @firestore.FirestoreClient) -> Unit {
  let reader = Reader::{ client, }
  @mcp_lib.run_server(reader)
}

///|
async fn main {
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
          run_with_client(fc)
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
              run_with_client(fc)
            }
          }
      }
  }
}
