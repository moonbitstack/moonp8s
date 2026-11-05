// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn escaped_families() -> Array[@metric.MetricFamily] {
  labeled_families("a\"b\\c\nd")
}

///|
fn labeled_families(value : String) -> Array[@metric.MetricFamily] {
  try {
    let registry = @metric.Registry::new()
    let paths = @metric.Family::new(["path"], fn() { @metric.Counter::new() })
    registry.register("paths", "Paths.", paths)
    paths.labels([value]).inc()
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
fn round_trip(value : String, format : Format) -> String {
  let families = labeled_families(value)
  let document = match format {
    Format::Text004 => text(families)
    Format::OpenMetrics100 => openmetrics(families)
  }
  let parsed = parse(document, format~) catch {
    @metric.Refused(message) => abort(message)
  }
  parsed[0].metrics[0].labels[0].1
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

///|
test "a backslash in a label value is doubled in both formats" {
  let one = labeled_families("a\\b")
  assert_true(text(one).contains("paths_total{path=\"a\\\\b\"} 1.0"))
  assert_true(openmetrics(one).contains("paths_total{path=\"a\\\\b\"} 1.0"))
  assert_eq(round_trip("a\\b", Format::Text004), "a\\b")
  assert_eq(round_trip("a\\b", Format::OpenMetrics100), "a\\b")
}

///|
test "a double quote in a label value is escaped in both formats" {
  let one = labeled_families("a\"b")
  assert_true(text(one).contains("paths_total{path=\"a\\\"b\"} 1.0"))
  assert_true(openmetrics(one).contains("paths_total{path=\"a\\\"b\"} 1.0"))
  assert_eq(round_trip("a\"b", Format::Text004), "a\"b")
  assert_eq(round_trip("a\"b", Format::OpenMetrics100), "a\"b")
}

///|
test "a newline in a label value is escaped in both formats" {
  let one = labeled_families("a\nb")
  assert_true(text(one).contains("paths_total{path=\"a\\nb\"} 1.0"))
  assert_true(openmetrics(one).contains("paths_total{path=\"a\\nb\"} 1.0"))
  assert_eq(round_trip("a\nb", Format::Text004), "a\nb")
  assert_eq(round_trip("a\nb", Format::OpenMetrics100), "a\nb")
}

///|
test "an escaped label value stays on one line" {
  let doc = text(labeled_families("a\nb"))
  // One break after the help line, one after the type line, one after the
  // sample: a newline that leaked through would add a fourth.
  let mut breaks = 0
  for c in doc {
    if c == '\n' {
      breaks = breaks + 1
    }
  }
  assert_eq(breaks, 3)
}
