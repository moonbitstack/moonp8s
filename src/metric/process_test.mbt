// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn sample_process_stats() -> @metric.ProcessStats {
  {
    cpu_seconds: 1.5,
    open_fds: 3L,
    max_fds: 1024L,
    virtual_memory_bytes: 1000L,
    resident_memory_bytes: 500L,
    start_time_seconds: 1700000000.0,
    threads: 4L,
  }
}

///|
test "the process collector exports seven series" {
  let registry = try {
    let registry = @metric.Registry::new()
    registry.add(@metric.ProcessCollector::new(sample_process_stats()))
    registry
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let families = registry.collect()
  assert_eq(families.length(), 7)
  assert_eq(families[0].name, "process_cpu_seconds")
  match families[0].kind {
    @metric.Kind::Counter => ()
    _ => abort("expected a counter")
  }
  assert_eq(families[1].name, "process_open_fds")
  assert_eq(families[6].name, "process_threads")
}

///|
test "the process collector applies a prefix" {
  let registry = try {
    let registry = @metric.Registry::new()
    registry.add(
      @metric.ProcessCollector::new(sample_process_stats(), prefix="app"),
    )
    registry
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let families = registry.collect()
  assert_eq(families[0].name, "app_process_cpu_seconds")
  assert_eq(families[6].name, "app_process_threads")
}

///|
test "process values reach the exposition" {
  let registry = try {
    let registry = @metric.Registry::new()
    registry.add(@metric.ProcessCollector::new(sample_process_stats()))
    registry
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let families = registry.collect()
  match families[1].metrics[0].value {
    @metric.Value::Number(v) => assert_true(v == 3.0)
    _ => abort("expected a number")
  }
}
