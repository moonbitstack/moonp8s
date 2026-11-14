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
/// `count` bounds from `low` to `high`, each a fixed multiple of the one before,
/// the multiple chosen so the last is `high`: `high / low` to the power
/// `1 / (count - 1)`. Two bounds are the least that names a range, and a range
/// that does not grow is refused rather than returned as a row of equal bounds.
///
/// This is for the case where the interesting span is known and the ratio
/// between steps is not: a request that answers in milliseconds or in seconds
/// wants `exponential_range(0.001, 60.0, 12)`, not a factor picked by hand.
pub fn exponential_range(
  low : Double,
  high : Double,
  count : Int32,
) -> Array[Double] raise Refused {
  if count < 2 {
    raise Refused(
      "exponential_range needs at least two bounds, got " + count.to_string(),
    )
  }
  if low <= 0.0 {
    raise Refused(
      "exponential_range needs a positive low bound, got " + low.to_string(),
    )
  }
  if high <= low {
    raise Refused(
      "exponential_range needs a high bound above the low one, got " +
      high.to_string(),
    )
  }
  let factor = @math.pow(high / low, 1.0 / (count - 1).to_double())
  let out : Array[Double] = []
  for i = 0; i < count; i = i + 1 {
    out.push(low * @math.pow(factor, i.to_double()))
  }
  out
}

///|
/// A histogram with cumulative buckets. Counts are kept per bucket and made
/// cumulative on snapshot, which is what the wire format carries. With `native`
/// it also keeps native buckets, or only those when no classic buckets were asked
/// for.
pub struct Histogram {
  priv bounds : Array[Double]
  priv counts : Array[Int64]
  priv mut sum : Double
  priv mut count : Int64
  priv exemplars : Array[Exemplar?]
  priv mut created : Double?
  priv sparse : SparseState?
  priv clock : () -> Double
}

///|
/// The time in Unix seconds, which is what a native histogram's resets are measured in.
fn wall() -> Double {
  @env.now().to_double() / 1000.0
}

///|
/// A histogram over `buckets`. Without `buckets` it uses the shared defaults, or none at
/// all when `native` is given, which is what client_golang does with a bucket factor and no
/// bucket list. `native` adds native buckets with those settings; `clock` is the time in Unix
/// seconds the native buckets' resets are measured by, the system clock unless given.
pub fn Histogram::new(
  buckets? : Array[Double],
  created? : Double,
  native? : Native,
  clock? : () -> Double,
) -> Histogram raise Refused {
  let bounds = match (buckets, native) {
    (Some(given), Some(_)) if given.length() == 0 => []
    (Some(given), _) => {
      check_buckets(given)
      copy_bounds(given)
    }
    (None, Some(_)) => []
    (None, None) => default_buckets()
  }
  let clock = clock.unwrap_or(wall)
  let sparse = match native {
    Some(config) => {
      if !(config.factor > 1.0) {
        raise Refused(
          "a native histogram's factor must be above 1, got " +
          config.factor.to_string(),
        )
      }
      Some(SparseState::new(config, clock()))
    }
    None => None
  }
  let n = bounds.length() + 1
  {
    bounds,
    counts: Array::make(n, 0L),
    sum: 0.0,
    count: 0L,
    exemplars: Array::make(n, None),
    created,
    sparse,
    clock,
  }
}

///|
/// The classic bucket a value falls in: the first whose bound it does not exceed, or the
/// `+Inf` bucket.
fn Histogram::bucket_of(self : Histogram, v : Double) -> Int32 {
  let mut index = self.bounds.length()
  for i = 0; i < self.bounds.length(); i = i + 1 {
    if v <= self.bounds[i] {
      index = i
      break
    }
  }
  index
}

///|
/// Count one observation in the classic buckets, the sum and the count, and in the native
/// buckets when there are some.
fn Histogram::count_in(self : Histogram, v : Double) -> Unit {
  let index = self.bucket_of(v)
  self.counts[index] = self.counts[index] + 1L
  self.sum = self.sum + v
  self.count = self.count + 1L
  match self.sparse {
    Some(sparse) if v == v => sparse.observe(v)
    _ => ()
  }
}

///|
/// Everything counted goes back to zero; exemplars stay, as they do in client_golang.
fn Histogram::clear(self : Histogram, at : Double) -> Unit {
  for i = 0; i < self.counts.length(); i = i + 1 {
    self.counts[i] = 0L
  }
  self.sum = 0.0
  self.count = 0L
  if self.sparse is Some(sparse) {
    sparse.clear()
    sparse.last_reset = at
  }
  if self.created is Some(_) {
    self.created = Some(at)
  }
}

///|
/// A reset that was put off until `min_reset` had passed happens once its time has come.
fn Histogram::settle(self : Histogram, now : Double) -> Unit {
  guard self.sparse is Some(sparse) else { return }
  guard sparse.reset_at is Some(at) && now >= at else { return }
  self.clear(at)
  sparse.reset_at = None
}

///|
/// Keep the native buckets within `max_buckets`: reset if `min_reset` has passed since the
/// last reset, else put a reset off until it has, then widen the zero bucket if allowed, else
/// halve the resolution.
fn Histogram::limit(self : Histogram, v : Double, now : Double) -> Unit {
  guard self.sparse is Some(sparse) else { return }
  let max = sparse.config.max_buckets
  if max == 0 || sparse.buckets() <= max {
    return
  }
  let wait = sparse.config.min_reset
  if wait > 0.0 && sparse.reset_at is None && now - sparse.last_reset >= wait {
    self.clear(now)
    // The observation that went over the limit is kept, so the reset loses nothing new.
    self.count_in(v)
    return
  }
  if wait > 0.0 && sparse.reset_at is None {
    sparse.reset_at = Some(sparse.last_reset + wait)
  }
  if sparse.widen_zero() {
    return
  }
  sparse.coarsen()
}

///|
/// Record one observation in the first bucket whose bound it does not exceed,
/// or in the `+Inf` bucket when it exceeds every bound, and in its native bucket.
/// NaN counts in the sum and the count but in no native bucket.
pub fn Histogram::observe(
  self : Histogram,
  v : Double,
  exemplar? : Exemplar,
) -> Unit {
  let now = if self.sparse is Some(_) { (self.clock)() } else { 0.0 }
  self.settle(now)
  self.count_in(v)
  if v == v {
    self.limit(v, now)
  }
  match exemplar {
    Some(e) => {
      self.exemplars[self.bucket_of(v)] = Some(e)
      match self.sparse {
        Some(sparse) if v == v =>
          sparse.keep_exemplar(e, e.timestamp.unwrap_or(now))
        _ => ()
      }
    }
    None => ()
  }
}

///|
/// The snapshot of this histogram: cumulative bucket counts, the sum, and the
/// total count, with the retained exemplars, and the native buckets when it keeps them.
pub fn Histogram::snapshot(self : Histogram) -> Point {
  if self.sparse is Some(_) {
    self.settle((self.clock)())
  }
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
  let value = match self.sparse {
    Some(sparse) =>
      Native(
        buckets=cumulative,
        sparse=sparse.value(),
        sum=self.sum,
        count=self.count,
      )
    None => Buckets(buckets=cumulative, sum=self.sum, count=self.count)
  }
  { labels: [], value, timestamp: None, created: self.created, exemplars, }
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
