// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn escaped_families() -> Array[@metric.MetricFamily] {
  try {
    let registry = @metric.Registry::new()
    let paths = @metric.Family::new(["path"], fn() { @metric.Counter::new() })
    registry.register("paths", "Paths.", paths)
    paths.labels(["a\"b\\c\nd"]).inc()
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
test "label values escape quote, backslash, and newline" {
  let doc = text(escaped_families())
  assert_true(doc.contains("paths_total{path=\"a\\\"b\\\\c\\nd\"} 1.0"))
}

///|
test "escaped label values survive a parse round trip" {
  let families = escaped_families()
  let parsed = parse(openmetrics(families), format=Format::OpenMetrics100) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].metrics[0].labels[0].1, "a\"b\\c\nd")
}
