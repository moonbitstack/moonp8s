// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The default bucket bounds the official Prometheus clients share: 0.005
/// through 10, fourteen finite bounds plus the implicit `+Inf` bucket every
/// histogram has.
pub let buckets : Array[Double] = [
  0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0,
]

///|
fn default_buckets() -> Array[Double] {
  [
    0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0,
  ]
}

///|
/// Bounds must be finite and strictly increasing; the implicit `+Inf` bucket is
/// added at encoding time, so passing infinity here is refused.
fn copy_bounds(bounds : Array[Double]) -> Array[Double] {
  let out : Array[Double] = []
  for b in bounds {
    out.push(b)
  }
  out
}

///|
fn check_buckets(bounds : Array[Double]) -> Unit raise Refused {
  if bounds.length() == 0 {
    raise Refused("a histogram needs at least one bucket")
  }
  let inf = 1.0 / 0.0
  let mut prev = 0.0 - inf
  let mut first = true
  for b in bounds {
    if b != b {
      raise Refused("bucket bound is NaN")
    }
    if b == inf || b == 0.0 - inf {
      raise Refused("bucket bounds must be finite")
    }
    // A histogram with a negative bound must not carry a sum, and this model
    // always carries one.
    if b < 0.0 {
      raise Refused("bucket bounds must not be negative, got " + b.to_string())
    }
    if !first && b <= prev {
      raise Refused("bucket bounds must be strictly increasing")
    }
    prev = b
    first = false
  }
}

///|
/// `count` bounds starting at `start` and growing by `width`.
pub fn linear(
  start : Double,
  width : Double,
  count : Int32,
) -> Array[Double] raise Refused {
  if count <= 0 {
    raise Refused("linear needs a positive count, got " + count.to_string())
  }
  if width <= 0.0 {
    raise Refused("linear needs a positive width, got " + width.to_string())
  }
  let out : Array[Double] = []
  for i = 0; i < count; i = i + 1 {
    out.push(start + width * i.to_double())
  }
  out
}

///|
/// `count` bounds starting at `start` and multiplying by `factor`.
pub fn exponential(
  start : Double,
  factor : Double,
  count : Int32,
) -> Array[Double] raise Refused {
  if count <= 0 {
    raise Refused(
      "exponential needs a positive count, got " + count.to_string(),
    )
  }
  if start <= 0.0 {
    raise Refused(
      "exponential needs a positive start, got " + start.to_string(),
    )
  }
  if factor <= 0.0 {
    raise Refused(
      "exponential needs a positive factor, got " + factor.to_string(),
    )
  }
  let out : Array[Double] = []
  let mut v = start
  for i = 0; i < count; i = i + 1 {
    out.push(v)
    v = v * factor
  }
  out
}

///|
/// A histogram with cumulative buckets. Counts are kept per bucket and made
/// cumulative on snapshot, which is what the wire format carries.
pub struct Histogram {
  priv bounds : Array[Double]
  priv counts : Array[Int64]
  priv mut sum : Double
  priv mut count : Int64
  priv exemplars : Array[Exemplar?]
  priv created : Double?
}

///|
/// A histogram over `buckets` (the shared defaults unless given).
pub fn Histogram::new(
  buckets~ : Array[Double] = default_buckets(),
  created? : Double,
) -> Histogram raise Refused {
  check_buckets(buckets)
  let bounds = copy_bounds(buckets)
  let n = bounds.length() + 1
  {
    bounds,
    counts: Array::make(n, 0L),
    sum: 0.0,
    count: 0L,
    exemplars: Array::make(n, None),
    created,
  }
}

///|
/// Record one observation in the first bucket whose bound it does not exceed,
/// or in the `+Inf` bucket when it exceeds every bound.
pub fn Histogram::observe(
  self : Histogram,
  v : Double,
  exemplar? : Exemplar,
) -> Unit {
  self.sum = self.sum + v
  self.count = self.count + 1L
  let mut index = self.bounds.length()
  for i = 0; i < self.bounds.length(); i = i + 1 {
    if v <= self.bounds[i] {
      index = i
      break
    }
  }
  self.counts[index] = self.counts[index] + 1L
  match exemplar {
    Some(e) => self.exemplars[index] = Some(e)
    None => ()
  }
}

///|
/// The snapshot of this histogram: cumulative bucket counts, the sum, and the
/// total count, with the retained exemplars.
pub fn Histogram::snapshot(self : Histogram) -> Point {
  let cumulative : Array[(Double, Int64)] = []
  let mut acc = 0L
  for i = 0; i < self.bounds.length(); i = i + 1 {
    acc = acc + self.counts[i]
    cumulative.push((self.bounds[i], acc))
  }
  let exemplars : Array[Exemplar] = []
  for e in self.exemplars {
    match e {
      Some(x) => exemplars.push(x)
      None => ()
    }
  }
  {
    labels: [],
    value: Buckets(buckets=cumulative, sum=self.sum, count=self.count),
    timestamp: None,
    created: self.created,
    exemplars,
  }
}

///|
/// The number of observations.
pub fn Histogram::total(self : Histogram) -> Int64 {
  self.count
}

///|
/// The sum of the observations.
pub fn Histogram::sum_value(self : Histogram) -> Double {
  self.sum
}

///|
pub impl Metric for Histogram with fn kind(_self) {
  Kind::Histogram
}

///|
pub impl Metric for Histogram with fn points(self) {
  [self.snapshot()]
}

///|
pub extend Histogram with Metric::{kind, points}

///|
/// A gauge histogram: the same buckets as a histogram, but the sum and count are
/// a gauge's, and the wire format spells them `_gsum` and `_gcount`.
pub struct GaugeHistogram {
  priv inner : Histogram
}

///|
/// A gauge histogram over `buckets` (the shared defaults unless given).
pub fn GaugeHistogram::new(
  buckets~ : Array[Double] = default_buckets(),
  created? : Double,
) -> GaugeHistogram raise Refused {
  { inner: Histogram::new(buckets~, created?), }
}

///|
/// Record one observation.
pub fn GaugeHistogram::observe(
  self : GaugeHistogram,
  v : Double,
  exemplar? : Exemplar,
) -> Unit {
  self.inner.observe(v, exemplar?)
}

///|
/// The snapshot of this gauge histogram.
pub fn GaugeHistogram::snapshot(self : GaugeHistogram) -> Point {
  self.inner.snapshot()
}

///|
pub impl Metric for GaugeHistogram with fn kind(_self) {
  Kind::GaugeHistogram
}

///|
pub impl Metric for GaugeHistogram with fn points(self) {
  [self.snapshot()]
}

///|
pub extend GaugeHistogram with Metric::{kind, points}
