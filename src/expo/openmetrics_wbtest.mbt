// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn unit_families() -> Array[@metric.MetricFamily] {
  try {
    let registry = @metric.Registry::new()
    let counter = registry.counter("requests", "Requests.", unit="seconds")
    counter.inc()
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
fn exemplar_families() -> Array[@metric.MetricFamily] {
  try {
    let registry = @metric.Registry::new()
    let counter = registry.counter("http_requests", "HTTP requests.")
    counter.inc(
      by=1.0,
      exemplar=@metric.Exemplar::new(
        [("trace_id", "abc")],
        1.0,
        timestamp=1700000000.0,
      ),
    )
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
test "a unit becomes a name suffix and a UNIT line" {
  let families = unit_families()
  assert_eq(families[0].name, "requests_seconds")
  assert_eq(families[0].unit, Some("seconds"))
  let doc = openmetrics(families)
  assert_true(doc.contains("# UNIT requests_seconds seconds\n"))
  assert_true(doc.contains("requests_seconds_total 1.0\n"))
  assert_true(text(families).contains("requests_seconds_total 1.0\n"))
}

///|
test "an exemplar is written on the counter line in OpenMetrics" {
  let doc = openmetrics(exemplar_families())
  assert_true(
    doc.contains("http_requests_total 1.0 # {trace_id=\"abc\"} 1.0 1.7e+09\n"),
  )
}

///|
test "the compatibility format carries no exemplar syntax" {
  let doc = text(exemplar_families())
  assert_true(!doc.contains("# {"))
}

///|
test "OpenMetrics ends with the EOF marker" {
  let doc = openmetrics(unit_families())
  assert_true(doc.contains("# EOF\n"))
}
