// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn sample_families() -> Array[@metric.MetricFamily] {
  try {
    let registry = @metric.Registry::new()
    let counter = registry.counter("requests", "Requests.")
    counter.inc()
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
test "push builds a PUT to the job path" {
  let families = sample_families()
  let request = push("pushgateway.local", "batch", families)
  assert_eq(request.http_method, "PUT")
  assert_eq(request.path, "http://pushgateway.local/metrics/job/batch")
  assert_eq(request.headers[0].0, "Content-Type")
  assert_eq(request.headers[0].1, "text/plain; version=0.0.4; charset=utf-8")
  assert_eq(request.body, @expo.text(families))
}

///|
test "push_add builds a POST" {
  let request = push_add("https://gateway.example/", "batch", sample_families())
  assert_eq(request.http_method, "POST")
  assert_eq(request.path, "https://gateway.example/metrics/job/batch")
}

///|
test "delete builds a DELETE with no body" {
  let request = delete("gateway.example", "batch")
  assert_eq(request.http_method, "DELETE")
  assert_eq(request.body, "")
  assert_eq(request.path, "http://gateway.example/metrics/job/batch")
}

///|
test "grouping keys are escaped the way the gateway expects" {
  let request = push("gateway.example", "batch", sample_families(), grouping_key=[
    ("instance", "a/b"),
    ("empty", ""),
    ("zone", "eu west"),
  ])
  assert_eq(
    request.path,
    "http://gateway.example/metrics/job/batch/empty@base64/=/instance@base64/YS9i/zone@base64/ZXUgd2VzdA",
  )
}

///|
test "OpenMetrics can be selected for the pushed body" {
  let families = sample_families()
  let request = push(
    "gateway.example",
    "batch",
    families,
    format=@expo.Format::OpenMetrics100,
  )
  assert_eq(
    request.headers[0].1,
    "application/openmetrics-text; version=1.0.0; charset=utf-8",
  )
  assert_eq(request.body, @expo.openmetrics(families))
}
