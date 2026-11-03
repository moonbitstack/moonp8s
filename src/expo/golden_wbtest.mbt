// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn golden_families() -> Array[@metric.MetricFamily] {
  try {
    let registry = @metric.Registry::new()
    let requests = @metric.Family::new(["method", "code"], fn() {
      @metric.Counter::new(created=1700000000.0)
    })
    registry.register("http_requests", "HTTP requests.", requests)
    requests.labels(["GET", "200"]).inc()
    requests.labels(["POST", "500"]).inc(by=2.5)
    let temperature = @metric.Gauge::new()
    registry.register("temperature_celsius", "Temperature.", temperature)
    temperature.set(21.5)
    let latency = @metric.Family::new(["route"], fn() raise @metric.Refused {
      @metric.Histogram::new(created=1700000000.0)
    })
    registry.register("request_latency_seconds", "Latency.", latency)
    latency.labels(["/"]).observe(0.05)
    latency.labels(["/"]).observe(0.3)
    latency.labels(["/"]).observe(2.0)
    let size = @metric.Summary::new(created=1700000000.0)
    registry.register("request_size_bytes", "Size.", size)
    size.observe(512.0)
    size.observe(1024.0)
    let build = @metric.Info::new([("version", "1.2.3"), ("commit", "abc")])
    registry.register("build_info", "Build info.", build)
    let state = @metric.StateSet::exclusive(["starting", "running", "stopped"])
    registry.register("task_state", "Task state.", state)
    state.set("running")
    registry.collect()
  } catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
test "compatibility format matches the reference client byte for byte" {
  assert_eq(text(golden_families()), golden_text)
}

///|
test "OpenMetrics format matches the reference client byte for byte" {
  assert_eq(openmetrics(golden_families()), golden_openmetrics)
}

///|
test "OpenMetrics round-trips through the parser" {
  let families = parse(golden_openmetrics, format=Format::OpenMetrics100)
  assert_eq(openmetrics(families), golden_openmetrics)
}
