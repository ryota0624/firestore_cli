///|
fn agg_field_filter(
  field : String,
  op : String,
  value : @gfs.Value,
) -> @gfs.Filter {
  @gfs.Filter::{
    composite_filter: None,
    field_filter: Some(@gfs.FieldFilter::{
      field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
      op: Some(op),
      value: Some(value),
    }),
    unary_filter: None,
  }
}

///|
fn to_value_map(
  rows : Array[@firestore.AggregationResult],
) -> Map[String, @gfs.Value] {
  let out : Map[String, @gfs.Value] = {}
  for row in rows {
    out[row.alias_] = row.value
  }
  out
}

///|
async test "firestore emulator: aggregate count/sum/avg + where + subcollection" {
  let (container, host_port) = start_firestore_emulator()
  let fc = build_emulator_firestore_client(host_port)
  let run = async fn() -> Unit {
    let _ = fc.create_document("metrics", doc_id="m1", {
      "amount": @firestore.dv(10.0),
      "active": @firestore.bv(true),
    })
    let _ = fc.create_document("metrics", doc_id="m2", {
      "amount": @firestore.dv(20.0),
      "active": @firestore.bv(false),
    })
    let _ = fc.create_document("metrics", doc_id="m3", {
      "amount": @firestore.dv(30.0),
      "active": @firestore.bv(true),
    })

    let all_rows = fc.aggregate("metrics", [
      ("count_all", @firestore.Count),
      ("sum_all", @firestore.Sum("amount")),
      ("avg_all", @firestore.Avg("amount")),
    ])
    let all = to_value_map(all_rows)
    assert_eq(all["count_all"].integer_value, Some("3"))
    assert_eq(all["sum_all"].double_value, Some(60.0))
    assert_eq(all["avg_all"].double_value, Some(20.0))

    let only_active = agg_field_filter("active", "EQUAL", @firestore.bv(true))
    let filtered_rows = fc.aggregate(
      "metrics",
      [
        ("count_active", @firestore.Count),
        ("sum_active", @firestore.Sum("amount")),
        ("avg_active", @firestore.Avg("amount")),
      ],
      where_=only_active,
    )
    let filtered = to_value_map(filtered_rows)
    assert_eq(filtered["count_active"].integer_value, Some("2"))
    assert_eq(filtered["sum_active"].double_value, Some(40.0))
    assert_eq(filtered["avg_active"].double_value, Some(20.0))

    let _ = fc.create_document("users", doc_id="alice", {
      "name": @firestore.sv("Alice"),
    })
    let _ = fc.create_document("users/alice/posts", doc_id="p1", {
      "likes": @firestore.dv(1.0),
    })
    let _ = fc.create_document("users/alice/posts", doc_id="p2", {
      "likes": @firestore.dv(2.0),
    })
    let sub_rows = fc.aggregate("users/alice/posts", [
      ("post_count", @firestore.Count),
      ("likes_sum", @firestore.Sum("likes")),
      ("likes_avg", @firestore.Avg("likes")),
    ])
    let sub = to_value_map(sub_rows)
    assert_eq(sub["post_count"].integer_value, Some("2"))
    assert_eq(sub["likes_sum"].double_value, Some(3.0))
    assert_eq(sub["likes_avg"].double_value, Some(1.5))

    fc.delete_document("users/alice/posts", "p1")
    fc.delete_document("users/alice/posts", "p2")
    fc.delete_document("users", "alice")
    fc.delete_document("metrics", "m1")
    fc.delete_document("metrics", "m2")
    fc.delete_document("metrics", "m3")
  }
  let result : Result[Unit, Error] = Ok(run()) catch { e => Err(e) }
  let _ = container.stop()
  let _ = container.remove()
  match result {
    Ok(_) => ()
    Err(e) => raise e
  }
}
