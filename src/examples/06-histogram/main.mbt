// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Two observations, counted into the fourteen bounds the official clients share.
/// The buckets are cumulative on the wire: `le="0.5"` counts everything at or below
/// half a second.
fn main raise {
  let registry = @metric.Registry::new()
  let latency = registry.histogram(
    "request_duration_seconds", "Request latency.",
  )
  latency.observe(0.041)
  latency.observe(0.317)
  println(@expo.text(registry.collect()))
}
