// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A gauge is the number at the moment of the scrape: it can go down, and it can be
/// taken from a function instead of stored.
fn main raise {
  let registry = @metric.Registry::new()
  let running = registry.gauge("jobs_running", "Jobs running now.")
  running.set(3.0)
  running.dec()
  println(@expo.text(registry.collect()))
}
