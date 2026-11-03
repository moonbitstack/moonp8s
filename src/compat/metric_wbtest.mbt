// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the counter vector adds series and totals them" {
  let vec = CounterVec::new(label="request")
  try {
    vec.inc("GET / 200")
    vec.add("POST / 500", 2L)
  } catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(vec.value("GET / 200"), 1L)
  assert_eq(vec.value("POST / 500"), 2L)
  assert_eq(vec.total(), 3L)
  assert_eq(vec.labels().length(), 2)
}

///|
test "the counter vector collects one point per series" {
  let vec = CounterVec::new(label="request")
  vec.inc("GET / 200") catch {
    @metric.Refused(message) => abort(message)
  }
  let registry = try {
    let registry = @metric.Registry::new()
    registry.register("requests", "Requests.", vec)
    registry
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let families = registry.collect()
  assert_eq(families[0].metrics.length(), 1)
  assert_eq(families[0].metrics[0].labels[0].0, "request")
  assert_eq(families[0].metrics[0].labels[0].1, "GET / 200")
}

///|
test "the server metric set registers the legacy names" {
  let metrics = ServerMetrics::new() catch {
    @metric.Refused(message) => abort(message)
  }
  metrics.requests().inc("GET / 200") catch {
    @metric.Refused(message) => abort(message)
  }
  metrics.latency().observe(12.0)
  let registry = try {
    let registry = @metric.Registry::new()
    metrics.register(registry)
    registry
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let families = registry.collect()
  assert_eq(families.length(), 2)
  assert_eq(families[0].name, "http_server_requests_code")
  assert_eq(families[1].name, "http_server_requests_duration_ms")
}
