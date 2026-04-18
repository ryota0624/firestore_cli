///|
pub(all) suberror TransportError {
  Eof
  InvalidJson
} derive(Debug)

///|
/// stdout へ JSON を改行区切りで送信
pub async fn send_message(payload : Json) -> Unit {
  let s = payload.stringify()
  @stdio.stdout.write(s + "\n")
}

///|
/// stdin から 1 行読んで JSON にパース
pub async fn recv_message() -> Json raise Error {
  match @stdio.stdin.read_until("\n") {
    None => raise TransportError::Eof
    Some(line) =>
      @json.parse(line.trim()) catch {
        _ => raise TransportError::InvalidJson
      }
  }
}

///|
/// stderr に診断ログを書く（改行付き）
pub async fn log(msg : String) -> Unit {
  @stdio.stderr.write(msg + "\n")
}
