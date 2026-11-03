// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An instantaneous value that may go up or down. `set` takes the timestamp to
/// record, because this library never reads a clock; pass `timestamp~` when the
/// sample is worth dating.
pub struct Gauge {
  priv mut value : Double
  priv mut timestamp : Double?
  priv mut function : (() -> Double)?
}

///|
/// A gauge at `initial` (zero unless given).
pub fn Gauge::new(initial~ : Double = 0.0) -> Gauge {
  { value: initial, timestamp: None, function: None, }
}

///|
/// Set the gauge to `v`, optionally dating the sample.
pub fn Gauge::set(self : Gauge, v : Double, timestamp? : Double) -> Unit {
  match self.function {
    Some(_) => ()
    None => {
      self.value = v
      self.timestamp = timestamp
    }
  }
}

///|
/// Take the value from `f` instead of a stored number. While a function is set,
/// `set`, `inc`, and `dec` do nothing, matching the Python client.
pub fn Gauge::set_function(self : Gauge, f : () -> Double) -> Unit {
  self.function = Some(f)
}

///|
/// Increase the gauge by `by`.
pub fn Gauge::inc(self : Gauge, by~ : Double = 1.0) -> Unit {
  match self.function {
    Some(_) => ()
    None => self.value = self.value + by
  }
}

///|
/// Decrease the gauge by `by`.
pub fn Gauge::dec(self : Gauge, by~ : Double = 1.0) -> Unit {
  match self.function {
    Some(_) => ()
    None => self.value = self.value - by
  }
}

///|
/// The current value.
pub fn Gauge::get(self : Gauge) -> Double {
  match self.function {
    Some(f) => f()
    None => self.value
  }
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
      value: Number(self.get()),
      timestamp: self.timestamp,
      created: None,
      exemplars: [],
    },
  ]
}

///|
pub extend Gauge with Metric::{kind, points}
