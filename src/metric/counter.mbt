// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Anything a registry can collect: a metric, a family of metrics, or a custom
/// collector's contribution. Implement this to plug a new metric shape into a
/// registry without changing the registry.
pub(open) trait Metric {
  fn kind(Self) -> Kind
  fn points(Self) -> Array[Point]
}

///|
/// A monotonically increasing count. `inc` refuses a negative step because a
/// counter that goes down is a gauge.
pub struct Counter {
  priv mut value : Double
  priv created : Double?
  priv mut exemplar : Exemplar?
}

///|
/// A counter at zero. `created` records when the series came into existence, for
/// the `_created` series OpenMetrics exposes.
pub fn Counter::new(created? : Double) -> Counter {
  { value: 0.0, created, exemplar: None, }
}

///|
/// Increase the counter by `by`, keeping `exemplar` as the latest exemplar.
pub fn Counter::inc(
  self : Counter,
  by~ : Double = 1.0,
  exemplar? : Exemplar,
) -> Unit raise Refused {
  if by < 0.0 {
    raise Refused("counter can only increase, got " + by.to_string())
  }
  self.value = self.value + by
  match exemplar {
    Some(e) => self.exemplar = Some(e)
    None => ()
  }
}

///|
/// The current count.
pub fn Counter::get(self : Counter) -> Double {
  self.value
}

///|
pub impl Metric for Counter with fn kind(_self) {
  Kind::Counter
}

///|
pub impl Metric for Counter with fn points(self) {
  let exemplars : Array[Exemplar] = match self.exemplar {
    Some(e) => [e]
    None => []
  }
  [
    {
      labels: [],
      value: Number(self.value),
      timestamp: None,
      created: self.created,
      exemplars,
    },
  ]
}

///|
pub extend Counter with Metric::{kind, points}
