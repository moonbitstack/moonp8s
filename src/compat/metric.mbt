// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The latency buckets the legacy metric package used, in milliseconds.
pub let default_latency_buckets : Array[Double] = [
  1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0,
]

///|
/// A counter partitioned by one label string, the shape the legacy metric
/// package exposed. New code should use `Family[@metric.Counter]`; this exists so an
/// existing call site can move over without being rewritten.
pub struct CounterVec {
  priv label : String
  priv counts : Map[String, @metric.Counter]
}

///|
/// An empty counter vector whose series are labelled `label`.
pub fn CounterVec::new(label~ : String = "label") -> CounterVec {
  { label, counts: Map([]), }
}

///|
fn CounterVec::get_or_create(
  self : CounterVec,
  key : String,
) -> @metric.Counter {
  match self.counts.get(key) {
    Some(counter) => counter
    None => {
      let counter = @metric.Counter::new()
      self.counts[key] = counter
      counter
    }
  }
}

///|
/// Add `delta` to the series named by `label`, creating it on first sight.
pub fn CounterVec::add(
  self : CounterVec,
  label : String,
  delta : Int64,
) -> Unit raise @metric.Refused {
  self.get_or_create(label).inc(by=delta.to_double())
}

///|
/// Increment the series named by `label` by one.
pub fn CounterVec::inc(
  self : CounterVec,
  label : String,
) -> Unit raise @metric.Refused {
  self.add(label, 1L)
}

///|
/// The current count of the series named by `label`.
pub fn CounterVec::value(self : CounterVec, label : String) -> Int64 {
  match self.counts.get(label) {
    Some(counter) => counter.get().to_int64()
    None => 0L
  }
}

///|
/// The sum of every series.
pub fn CounterVec::total(self : CounterVec) -> Int64 {
  let mut sum = 0L
  for _, counter in self.counts {
    sum = sum + counter.get().to_int64()
  }
  sum
}

///|
/// The series names seen so far.
pub fn CounterVec::labels(self : CounterVec) -> Array[String] {
  self.counts.keys().collect()
}

///|
pub impl @metric.Metric for CounterVec with fn kind(_self) {
  @metric.Kind::@metric.Counter
}

///|
pub impl @metric.Metric for CounterVec with fn points(self) {
  let out : Array[@metric.Point] = []
  for key, counter in self.counts {
    out.push({
      labels: [(self.label, key)],
      value: @metric.Value::Number(counter.get()),
      timestamp: None,
      created: None,
      exemplars: [],
    })
  }
  out
}

///|
pub extend CounterVec with @metric.Metric::{kind, points}

///|
/// The request counter and latency histogram the legacy server metric set
/// exposed: request counts labelled by request signature, and a millisecond
/// latency histogram.
pub struct ServerMetrics {
  priv requests : CounterVec
  priv latency : @metric.Histogram
}

///|
/// A fresh server metric set.
pub fn ServerMetrics::new() -> ServerMetrics raise @metric.Refused {
  {
    requests: CounterVec::new(label="request"),
    latency: @metric.Histogram::new(buckets=default_latency_buckets),
  }
}

///|
/// The request counter.
pub fn ServerMetrics::requests(self : ServerMetrics) -> CounterVec {
  self.requests
}

///|
/// The latency histogram, in milliseconds.
pub fn ServerMetrics::latency(self : ServerMetrics) -> @metric.Histogram {
  self.latency
}

///|
/// Register both series under the legacy names, optionally prefixed.
pub fn ServerMetrics::register(
  self : ServerMetrics,
  registry : @metric.Registry,
  prefix? : String,
) -> Unit raise @metric.Refused {
  let p = prefix.unwrap_or("")
  let lead = if p == "" { "" } else { p + "_" }
  registry.register(
    lead + "http_server_requests_code",
    "http server requests code count.",
    self.requests,
  )
  registry.register(
    lead + "http_server_requests_duration_ms",
    "http server requests duration(ms).",
    self.latency,
  )
}
