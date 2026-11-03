// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The fixed creation time used here keeps the example deterministic.
let created : Double = 1700000000.0

///|
fn build() -> Unit raise @metric.Refused {
  let registry = @moonp8s.Registry::new()
  let requests = @moonp8s.Family::new(["method", "code"], fn() {
    @moonp8s.Counter::new(created~)
  })
  registry.register("http_requests", "HTTP requests.", requests)
  requests.labels(["GET", "200"]).inc()
  requests.labels(["POST", "500"]).inc(by=2.5)
  let temperature = @moonp8s.Gauge::new()
  registry.register("temperature_celsius", "Temperature.", temperature)
  temperature.set(21.5)
  let latency = @moonp8s.Family::new(["route"], fn() raise @metric.Refused {
    @moonp8s.Histogram::new(created~)
  })
  registry.register("request_latency_seconds", "Latency.", latency)
  latency.labels(["/"]).observe(0.05)
  latency.labels(["/"]).observe(0.3)
  latency.labels(["/"]).observe(2.0)
  let size = @moonp8s.Summary::new(created~)
  registry.register("request_size_bytes", "Size.", size)
  size.observe(512.0)
  size.observe(1024.0)
  let build = @moonp8s.Info::new([("version", "1.2.3"), ("commit", "abc")])
  registry.register("build_info", "Build info.", build)
  let state = @moonp8s.StateSet::exclusive(["starting", "running", "stopped"])
  registry.register("task_state", "Task state.", state)
  state.set("running")
  let families = registry.collect()
  println(@moonp8s.text(families))
  println(@moonp8s.openmetrics(families))
}

///|
#coverage.skip
fn main {
  build() catch {
    @metric.Refused(message) => println("refused: " + message)
  }
}
