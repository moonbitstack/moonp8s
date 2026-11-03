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

///|
test "a gauge histogram uses gcount and gsum" {
  let families = try {
    let registry = @metric.Registry::new()
    let histogram = @metric.GaugeHistogram::new(buckets=[1.0])
    registry.register("gh", "Gauge histogram.", histogram)
    histogram.observe(0.5)
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let text_doc = text(families)
  assert_true(text_doc.contains("gh_bucket{le=\"1.0\"} 1.0"))
  assert_true(text_doc.contains("gh_gcount 1.0"))
  assert_true(text_doc.contains("gh_gsum 0.5"))
  assert_true(!text_doc.contains("gh_count"))
  let om_doc = openmetrics(families)
  assert_true(om_doc.contains("# TYPE gh gaugehistogram"))
  assert_true(om_doc.contains("gh_gcount 1.0"))
}

///|
test "a summary writes quantiles, count, and sum" {
  let families = try {
    let registry = @metric.Registry::new()
    let summary = @metric.Summary::new(quantiles=[(0.5, 0.01)])
    registry.register("latency", "Latency.", summary)
    for i = 1; i <= 100; i = i + 1 {
      summary.observe(i.to_double())
    }
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let doc = openmetrics(families)
  assert_true(doc.contains("latency{quantile=\"0.5\"} "))
  assert_true(doc.contains("latency_count 100.0\n"))
  assert_true(doc.contains("latency_sum 5050.0\n"))
  assert_true(doc.contains("# TYPE latency summary\n"))
}

///|
test "a timestamp is milliseconds in text and seconds in OpenMetrics" {
  let families = try {
    let registry = @metric.Registry::new()
    let gauge = @metric.Gauge::new()
    registry.register("g", "G.", gauge)
    gauge.set(1.0, timestamp=1700000000.5)
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
  assert_true(text(families).contains("g 1.0 1700000000500\n"))
  assert_true(openmetrics(families).contains("g 1.0 1.7000000005e+09\n"))
}

///|
test "an exemplar over 128 characters is refused" {
  let sb = StringBuilder()
  for i = 0; i < 129; i = i + 1 {
    sb.write_char('x')
  }
  let long = sb.to_string()
  let refused = try {
    ignore(@metric.Exemplar::new([("trace", long)], 1.0))
    false
  } catch {
    @metric.Refused(_) => true
  }
  assert_true(refused)
}

///|
test "help text escapes and survives a round trip" {
  let help = "a\\b\nc\"d"
  let families = try {
    let registry = @metric.Registry::new()
    let counter = registry.counter("c", help)
    counter.inc()
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let text_parsed = parse(text(families), format=Format::Text004) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(text_parsed[0].help, help)
  let om_parsed = parse(openmetrics(families), format=Format::OpenMetrics100) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(om_parsed[0].help, help)
}
