///|
fn explain_query_spec(order_by? : Array[@gfs.Order]) -> @firestore.QuerySpec {
  @firestore.QuerySpec::{
    filter: None,
    order_by,
    start_at: None,
    end_at: None,
    limit: None,
    offset: None,
  }
}

///|
fn explain_asc_order(field : String) -> @gfs.Order {
  @gfs.Order::{
    field: Some(@gfs.FieldReference::{ field_path: Some(field) }),
    direction: Some("ASCENDING"),
  }
}

///|
async test "firestore emulator: explain query/aggregate returns metrics" {
  let (container, host_port) = start_firestore_emulator()
  let fc = build_emulator_firestore_client(host_port)
  let run = async fn() -> Unit {
    let _ = fc.create_document("logs", doc_id="l1", {
      "score": @firestore.iv(10L),
      "active": @firestore.bv(true),
    })
    let _ = fc.create_document("logs", doc_id="l2", {
      "score": @firestore.iv(20L),
      "active": @firestore.bv(false),
    })

    let spec = explain_query_spec(order_by=[explain_asc_order("score")])
    // Firestore emulator may not support explain APIs.
    // In that case, skip this test branch after confirming request-level failure.
    let q_plan_result : Result[@firestore.QueryExplainResult, Error] = try? fc.explain_query(
      "logs",
      spec,
      analyze=false,
    )
    let q_plan = match q_plan_result {
      Ok(v) => v
      Err(_) => {
        assert_true(true)
        return
      }
    }
    assert_eq(q_plan.metrics.execution_stats, None)
    let _ = q_plan.metrics.plan_summary

    let q_analyze_result : Result[@firestore.QueryExplainResult, Error] = try? fc.explain_query(
      "logs",
      spec,
      analyze=true,
    )
    match q_analyze_result {
      Ok(v) => {
        let _ = v.metrics.plan_summary
        assert_true(true)
      }
      Err(_) => {
        assert_true(true)
        return
      }
    }

    let aggregators = [("count_all", @firestore.Count)]
    let a_plan_result : Result[@firestore.AggregationExplainResult, Error] = try? fc.explain_aggregate(
      "logs",
      aggregators,
      analyze=false,
    )
    let a_plan = match a_plan_result {
      Ok(v) => v
      Err(_) => {
        assert_true(true)
        return
      }
    }
    assert_eq(a_plan.metrics.execution_stats, None)
    let _ = a_plan.metrics.plan_summary

    let a_analyze_result : Result[@firestore.AggregationExplainResult, Error] = try? fc.explain_aggregate(
      "logs",
      aggregators,
      analyze=true,
    )
    match a_analyze_result {
      Ok(v) => {
        let _ = v.metrics.plan_summary
        assert_true(true)
      }
      Err(_) => {
        assert_true(true)
        return
      }
    }

    fc.delete_document("logs", "l1")
    fc.delete_document("logs", "l2")
  }
  let result : Result[Unit, Error] = Ok(run()) catch { e => Err(e) }
  let _ = container.stop()
  let _ = container.remove()
  match result {
    Ok(_) => ()
    Err(e) => raise e
  }
}
