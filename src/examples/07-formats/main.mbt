// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One snapshot, two formats. The counts are the same object; only the spelling of
/// the timestamp and the ending differ.
fn main raise {
  let registry = @metric.Registry::new()
  let latency = registry.histogram(
    "request_duration_seconds", "Request latency.",
  )
  latency.observe(0.041)
  latency.observe(0.317)
  let families = registry.collect(at=1_700_000_015.0)
  println("=== 0.0.4 ===")
  println(@expo.text(families))
  println("=== 1.0 ===")
  println(@expo.openmetrics(families))
}
