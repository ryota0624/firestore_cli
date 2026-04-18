///|
fn q_field_filter(
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
fn q_spec(
  filter? : @gfs.Filter,
  order_by? : Array[@gfs.Order],
  start_at? : @gfs.Cursor,
  end_at? : @gfs.Cursor,
  limit? : Int,
) -> @firestore.QuerySpec {
  @firestore.QuerySpec::{
    filter,
    order_by,
    start_at,
    end_at,
    limit,
    offset: None,
  }
}

///|
fn q_asc_order(field : String) -> @gfs.Order {
  @gfs.Order::{
    field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
    direction: Some("ASCENDING"),
  }
}

///|
async test "firestore emulator: query CompositeFilter + order/limit + cursor paging" {
  let (container, host_port) = start_firestore_emulator()
  let fc = build_emulator_firestore_client(host_port)
  let run = async fn() -> Unit {
    let _ = fc.create_document("tickets", doc_id="a", {
      "priority": @firestore.iv(1L),
      "score": @firestore.iv(10L),
      "active": @firestore.bv(true),
    })
    let _ = fc.create_document("tickets", doc_id="b", {
      "priority": @firestore.iv(2L),
      "score": @firestore.iv(20L),
      "active": @firestore.bv(true),
    })
    let _ = fc.create_document("tickets", doc_id="c", {
      "priority": @firestore.iv(1L),
      "score": @firestore.iv(30L),
      "active": @firestore.bv(false),
    })
    let _ = fc.create_document("tickets", doc_id="d", {
      "priority": @firestore.iv(2L),
      "score": @firestore.iv(40L),
      "active": @firestore.bv(true),
    })
    let _ = fc.create_document("tickets", doc_id="e", {
      "priority": @firestore.iv(3L),
      "score": @firestore.iv(50L),
      "active": @firestore.bv(true),
    })

    let active_filter = q_field_filter("active", "EQUAL", @firestore.bv(true))
    let priority_filter = q_field_filter("priority", "EQUAL", @firestore.iv(2L))
    let and_filter = @gfs.Filter::{
      composite_filter: Some(@gfs.CompositeFilter::{
        op: Some("AND"),
        filters: Some([active_filter, priority_filter]),
      }),
      field_filter: None,
      unary_filter: None,
    }
    let and_docs = fc.query("tickets", q_spec(filter=and_filter))
    assert_eq(and_docs.length(), 2)
    let and_names : Array[String] = and_docs
      .iter()
      .map(fn(d) { d.name.unwrap_or("") })
      .collect()
    assert_true(and_names.iter().any(fn(n) { n.has_suffix("/b") }))
    assert_true(and_names.iter().any(fn(n) { n.has_suffix("/d") }))

    let order = [q_asc_order("score")]
    let first_three = fc.query("tickets", q_spec(order_by=order, limit=3))
    assert_eq(first_three.length(), 3)
    let ordered_names : Array[String] = first_three
      .iter()
      .map(fn(d) { d.name.unwrap_or("") })
      .collect()
    assert_true(ordered_names[0].has_suffix("/a"))
    assert_true(ordered_names[1].has_suffix("/b"))
    assert_true(ordered_names[2].has_suffix("/c"))

    let head = fc.query(
      "tickets",
      q_spec(order_by=order, end_at=@gfs.Cursor::{
        values: Some([@firestore.iv(20L)]),
        before: Some(false),
      }),
    )
    assert_eq(head.length(), 2)
    let head_names : Array[String] = head
      .iter()
      .map(fn(d) { d.name.unwrap_or("") })
      .collect()
    assert_true(head_names[0].has_suffix("/a"))
    assert_true(head_names[1].has_suffix("/b"))

    let tail = fc.query(
      "tickets",
      q_spec(order_by=order, start_at=@gfs.Cursor::{
        values: Some([@firestore.iv(30L)]),
        before: Some(false),
      }),
    )
    assert_eq(tail.length(), 2)
    let tail_names : Array[String] = tail
      .iter()
      .map(fn(d) { d.name.unwrap_or("") })
      .collect()
    assert_true(tail_names[0].has_suffix("/d"))
    assert_true(tail_names[1].has_suffix("/e"))

    fc.delete_document("tickets", "a")
    fc.delete_document("tickets", "b")
    fc.delete_document("tickets", "c")
    fc.delete_document("tickets", "d")
    fc.delete_document("tickets", "e")
  }
  let result : Result[Unit, Error] = Ok(run()) catch { e => Err(e) }
  let _ = container.stop()
  let _ = container.remove()
  match result {
    Ok(_) => ()
    Err(e) => raise e
  }
}
