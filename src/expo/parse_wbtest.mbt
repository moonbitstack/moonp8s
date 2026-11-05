// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the compatibility format parses a counter and its created series" {
  let doc = "# HELP c_total C.\n# TYPE c_total counter\nc_total{a=\"b\"} 1.0\nc_created{a=\"b\"} 1.7e+09\n"
  let families = parse(doc, format=Format::Text004) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(families.length(), 1)
  assert_eq(families[0].name, "c")
  match families[0].kind {
    @metric.Kind::Counter => ()
    _ => abort("expected a counter")
  }
  assert_eq(families[0].metrics[0].labels.length(), 1)
  match families[0].metrics[0].value {
    @metric.Value::Number(v) => assert_eq(v, 1.0)
    _ => abort("expected a number")
  }
  match families[0].metrics[0].created {
    Some(c) => assert_eq(c, 1700000000.0)
    None => abort("expected a created time")
  }
}

///|
test "OpenMetrics keeps info and stateset kinds" {
  let doc = "# HELP i I.\n# TYPE i info\ni_info{x=\"y\"} 1.0\n# HELP s S.\n# TYPE s stateset\ns{s=\"a\"} 1.0\ns{s=\"b\"} 0.0\n# EOF\n"
  let families = parse(doc, format=Format::OpenMetrics100) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(families.length(), 2)
  match families[0].kind {
    @metric.Kind::Info => ()
    _ => abort("expected info")
  }
  assert_eq(families[0].name, "i")
  match families[1].kind {
    @metric.Kind::StateSet => ()
    _ => abort("expected a state set")
  }
  match families[1].metrics[0].value {
    @metric.Value::State(states~) => {
      assert_eq(states.length(), 2)
      assert_eq(states[0].0, "a")
      assert_true(states[0].1)
      assert_true(!states[1].1)
    }
    _ => abort("expected states")
  }
}

///|
test "a histogram parses back into cumulative buckets" {
  let doc = "# HELP h H.\n# TYPE h histogram\nh_bucket{le=\"1.0\"} 1.0\nh_bucket{le=\"2.0\"} 3.0\nh_bucket{le=\"+Inf\"} 4.0\nh_count 4.0\nh_sum 5.5\n"
  let families = parse(doc, format=Format::Text004) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(families.length(), 1)
  match families[0].metrics[0].value {
    @metric.Value::Buckets(buckets~, sum~, count~) => {
      assert_eq(buckets.length(), 2)
      assert_eq(buckets[0].0, 1.0)
      assert_eq(buckets[0].1, 1L)
      assert_eq(buckets[1].1, 3L)
      assert_eq(sum, 5.5)
      assert_eq(count, 4L)
    }
    _ => abort("expected buckets")
  }
}

///|
test "malformed input is refused" {
  let refused = try {
    ignore(parse("# TYPE x counter\nx_total{bad 1.0\n", format=Format::Text004))
    false
  } catch {
    @metric.Refused(_) => true
  }
  assert_true(refused)
}

///|
test "the three named values parse in both formats" {
  let document = "# TYPE probe gauge\nprobe{a=\"one\"} NaN\nprobe{a=\"two\"} +Inf\nprobe{a=\"three\"} -Inf\n"
  for format in [Format::Text004, Format::OpenMetrics100] {
    let families = parse(document, format~) catch {
      @metric.Refused(message) => abort(message)
    }
    let values = families[0].metrics.map(fn(point) {
      match point.value {
        @metric.Value::Number(v) => v
        _ => abort("not a number")
      }
    })
    assert_true(values[0] != values[0])
    assert_true(values[1] > 0.0 && values[1] == 1.0 / 0.0)
    assert_true(values[2] < 0.0 && values[2] == 0.0 - 1.0 / 0.0)
  }
}

///|
test "an exemplar with no labels is written as an empty label set" {
  let families = try {
    let registry = @metric.Registry::new()
    let counter = registry.counter("hit", "Hit.")
    counter.inc(exemplar=@metric.Exemplar::new([], 1.0))
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
  assert_true(openmetrics(families).contains("hit_total 1.0 # {} 1.0"))
}
