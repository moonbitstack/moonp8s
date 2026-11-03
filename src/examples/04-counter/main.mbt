// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A counter only goes up, so the only way to read it is to scrape it twice. This
/// program prints one scrape.
fn main raise {
  let registry = @metric.Registry::new()
  let jobs = registry.counter("jobs_processed", "Jobs finished.")
  jobs.inc()
  jobs.inc(by=11.0)
  println(@expo.text(registry.collect()))
}
