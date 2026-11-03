// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
#coverage.skip
fn main {
  try {
    let registry = @moonp8s.Registry::new()
    let jobs = registry.counter("jobs_done", "Jobs finished.")
    jobs.inc(by=3.0)
    let request = @moonp8s.push(
      "pushgateway.local",
      "batch",
      registry.collect(),
      grouping_key=[("instance", "worker-1")],
    )
    println(request.http_method + " " + request.path)
    for header in request.headers {
      println(header.0 + ": " + header.1)
    }
    println("")
    println(request.body)
  } catch {
    @metric.Refused(message) => println("refused: " + message)
  }
}
