// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An instantaneous value that may go up or down. `set` takes the timestamp to
/// record, because this library never reads a clock; pass `timestamp~` when the
/// sample is worth dating.
pub struct Gauge {
  priv mut value : Double
  priv mut timestamp : Double?
}

///|
/// A gauge at `initial` (zero unless given).
pub fn Gauge::new(initial~ : Double = 0.0) -> Gauge {
  { value: initial, timestamp: None, }
}

///|
/// Set the gauge to `v`, optionally dating the sample.
pub fn Gauge::set(self : Gauge, v : Double, timestamp? : Double) -> Unit {
  self.value = v
  self.timestamp = timestamp
}

///|
/// Increase the gauge by `by`.
pub fn Gauge::inc(self : Gauge, by~ : Double = 1.0) -> Unit {
  self.value = self.value + by
}

///|
/// Decrease the gauge by `by`.
pub fn Gauge::dec(self : Gauge, by~ : Double = 1.0) -> Unit {
  self.value = self.value - by
}

///|
/// The current value.
pub fn Gauge::get(self : Gauge) -> Double {
  self.value
}

///|
pub impl Metric for Gauge with fn kind(_self) {
  Kind::Gauge
}

///|
pub impl Metric for Gauge with fn points(self) {
  [
    {
      labels: [],
      value: Number(self.value),
      timestamp: self.timestamp,
      created: None,
      exemplars: [],
    },
  ]
}

///|
pub extend Gauge with Metric::{kind, points}
