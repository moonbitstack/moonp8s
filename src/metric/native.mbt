// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Native histograms: buckets whose boundaries grow by a fixed factor, kept only where
// observations fell, so a histogram is fine-grained everywhere without a list of bounds
// chosen in advance. The bucketing, the limit on populated buckets and the exemplar
// selection follow client_golang, so that the same observations give the same exposition.

///|
/// How a histogram keeps native buckets. Passed to `Histogram::new` as `native`, it adds them
/// beside the classic buckets, or replaces those when no classic buckets are given.
///
/// - `factor`: the largest ratio between the bounds of neighbouring buckets; the schema is the
///   coarsest one that keeps within it. Must be above 1.
/// - `zero_threshold`: observations whose absolute value is at most this go to the zero bucket.
/// - `max_buckets`: once more buckets than this are populated, the histogram is reset if
///   `min_reset` seconds have passed since the last reset, else the zero bucket is widened up
///   to `max_zero_threshold`, else every bucket is made twice as wide. 0 is no limit.
/// - `min_reset`: seconds between resets; 0 never resets. A widened or coarsened histogram goes
///   back to its first resolution once this has passed.
/// - `max_exemplars`, `exemplar_ttl`: how many exemplars the native buckets keep, and after how
///   many seconds an old one is the first to go; `max_exemplars` 0 keeps none.
#derive(Eq, Debug)
pub(all) struct Native {
  factor : Double
  zero_threshold : Double
  max_buckets : Int32
  min_reset : Double
  max_zero_threshold : Double
  max_exemplars : Int32
  exemplar_ttl : Double
}

///|
pub extend Native with Eq::{equal, not_equal}

///|
pub extend Native with Debug::{to_repr}

///|
/// The settings a native histogram starts from. `factor` 1.1 is the trade-off client_golang's
/// documentation recommends (eight buckets per power of two); `zero_threshold` is its default,
/// 2^-128; `max_buckets` 100 and `min_reset` fifteen minutes are what its native histogram
/// example sets, since an unlimited bucket count lets wide-spread input grow the histogram
/// without end; `max_zero_threshold` 0 never widens the zero bucket, its default; ten
/// exemplars kept for five minutes are its defaults.
pub let native : Native = {
  factor: 1.1,
  zero_threshold: 2.938735877055719e-39,
  max_buckets: 100,
  min_reset: 900.0,
  max_zero_threshold: 0.0,
  max_exemplars: 10,
  exemplar_ttl: 300.0,
}

///|
/// `native` with the settings named here changed.
pub fn Native::new(
  factor~ : Double = native.factor,
  zero_threshold~ : Double = native.zero_threshold,
  max_buckets~ : Int32 = native.max_buckets,
  min_reset~ : Double = native.min_reset,
  max_zero_threshold~ : Double = native.max_zero_threshold,
  max_exemplars~ : Int32 = native.max_exemplars,
  exemplar_ttl~ : Double = native.exemplar_ttl,
) -> Native {
  {
    factor,
    zero_threshold,
    max_buckets,
    min_reset,
    max_zero_threshold,
    max_exemplars,
    exemplar_ttl,
  }
}

///|
/// The finest and the coarsest schema a native histogram can have.
let schema_max : Int32 = 8

///|
let schema_min : Int32 = -4

///|
let max_double : Double = 1.7976931348623157e308

///|
/// The schema for a growth factor: the coarsest whose buckets grow by at most `factor`.
fn schema_of(factor : Double) -> Int32 {
  let floor = log2(log2(factor)).floor()
  if floor <= -8.0 {
    schema_max
  } else if floor >= 4.0 {
    schema_min
  } else {
    -floor.to_int()
  }
}

///|
/// `x` as a fraction in [0.5, 1) and a power of two. Zero, infinities and NaN come back as
/// themselves with exponent 0.
fn frexp(x : Double) -> (Double, Int32) {
  if x == 0.0 || x != x || x.is_inf() {
    return (x, 0)
  }
  let mut bits = x.reinterpret_as_uint64()
  let mut shift = 0
  if ((bits >> 52) & 0x7ffUL) == 0UL {
    // A subnormal number: make it normal first.
    bits = (x * 18446744073709551616.0).reinterpret_as_uint64()
    shift = -64
  }
  let exp = ((bits >> 52) & 0x7ffUL).to_int() - 1022 + shift
  let frac = (bits & 0x800fffffffffffffUL) | (1022UL << 52)
  (frac.reinterpret_as_double(), exp)
}

///|
/// 2^e for an exponent a double can hold as a normal number.
fn pow2(e : Int32) -> Double {
  ((e + 1023).to_uint64() << 52).reinterpret_as_double()
}

///|
/// `frac × 2^exp`, without overflowing on the way when `exp` is beyond a normal exponent.
fn ldexp(frac : Double, exp : Int32) -> Double {
  let mut x = frac
  let mut e = exp
  while e > 1000 {
    x = x * pow2(1000)
    e = e - 1000
  }
  while e < -1000 {
    x = x * pow2(-1000)
    e = e + 1000
  }
  x * pow2(e)
}

///|
/// log2 that is exact at powers of two, which `schema_of` relies on at the edges of a schema.
fn log2(x : Double) -> Double {
  let (frac, exp) = frexp(x)
  if frac == 0.5 {
    return (exp - 1).to_double()
  }
  @math.ln(frac) * (1.0 / 0.6931471805599453) + exp.to_double()
}

///|
/// The first index whose bound is at least `frac`.
fn search(bounds : FixedArray[Double], frac : Double) -> Int32 {
  let mut low = 0
  let mut high = bounds.length()
  while low < high {
    let mid = (low + high) / 2
    if bounds[mid] < frac {
      low = mid + 1
    } else {
      high = mid
    }
  }
  low
}

///|
/// The bucket a value falls in at `schema`. Bucket `k` covers (2^((k-1)/2^schema),
/// 2^(k/2^schema)], so bucket 0 ends at 1. An infinity goes to the bucket after the one that
/// holds the largest double.
fn bucket_key(value : Double, schema : Int32) -> Int32 {
  let inf = value.is_inf()
  let (frac, exp) = frexp(if inf { max_double } else { value.abs() })
  let key = if schema > 0 {
    let bounds = native_bounds[schema]
    search(bounds, frac) + (exp - 1) * bounds.length()
  } else {
    let k = if frac == 0.5 { exp - 1 } else { exp }
    let offset = (1 << -schema) - 1
    (k + offset) >> -schema
  }
  if inf {
    key + 1
  } else {
    key
  }
}

///|
/// The upper bound of bucket `key` at `schema`. The bucket before the one for infinities ends
/// at the largest double rather than at an infinite bound.
fn upper_of(key : Int32, schema : Int32) -> Double {
  if schema < 0 {
    let exp = key << -schema
    if exp == 1024 {
      return max_double
    }
    return ldexp(1.0, exp)
  }
  let frac = native_bounds[schema][key & ((1 << schema) - 1)]
  let exp = (key >> schema) + 1
  if frac == 0.5 && exp == 1025 {
    return max_double
  }
  ldexp(frac, exp)
}

///|
/// The native side of a histogram while it is being observed into.
priv struct SparseState {
  config : Native
  first_schema : Int32
  mut schema : Int32
  mut zero_threshold : Double
  mut zero_count : Int64
  positive : Map[Int32, Int64]
  negative : Map[Int32, Int64]
  mut last_reset : Double
  mut reset_at : Double?
  exemplars : Array[(Exemplar, Double)]
}

///|
fn SparseState::new(config : Native, now : Double) -> SparseState {
  let schema = schema_of(config.factor)
  {
    config,
    first_schema: schema,
    schema,
    zero_threshold: config.zero_threshold,
    zero_count: 0L,
    positive: Map([]),
    negative: Map([]),
    last_reset: now,
    reset_at: None,
    exemplars: [],
  }
}

///|
fn SparseState::buckets(self : SparseState) -> Int32 {
  self.positive.length() + self.negative.length()
}

///|
fn add_to(buckets : Map[Int32, Int64], key : Int32, n : Int64) -> Unit {
  buckets[key] = buckets.get(key).unwrap_or(0L) + n
}

///|
/// Count one observation in its native bucket.
fn SparseState::observe(self : SparseState, value : Double) -> Unit {
  let v = if value == 1.0 / 0.0 {
    max_double
  } else if value == -1.0 / 0.0 {
    -max_double
  } else {
    value
  }
  let key = bucket_key(value, self.schema)
  if v > self.zero_threshold {
    add_to(self.positive, key, 1L)
  } else if v < -self.zero_threshold {
    add_to(self.negative, key, 1L)
  } else {
    self.zero_count = self.zero_count + 1L
  }
}

///|
/// Back to the first resolution, with nothing counted.
fn SparseState::clear(self : SparseState) -> Unit {
  self.schema = self.first_schema
  self.zero_threshold = self.config.zero_threshold
  self.zero_count = 0L
  self.positive.clear()
  self.negative.clear()
}

///|
/// Widen the zero bucket over the populated bucket nearest to zero, when that stays within
/// `max_zero_threshold`.
fn SparseState::widen_zero(self : SparseState) -> Bool {
  if self.zero_threshold >= self.config.max_zero_threshold {
    return false
  }
  let mut smallest : Int32? = None
  for key, _ in self.positive {
    if smallest is None || key < smallest.unwrap() {
      smallest = Some(key)
    }
  }
  for key, _ in self.negative {
    if smallest is None || key < smallest.unwrap() {
      smallest = Some(key)
    }
  }
  guard smallest is Some(key) else { return false }
  let threshold = upper_of(key, self.schema)
  if threshold > self.config.max_zero_threshold {
    return false
  }
  self.zero_threshold = threshold
  for side in [self.positive, self.negative] {
    if side.get(key) is Some(n) {
      self.zero_count = self.zero_count + n
      side.remove(key)
    }
  }
  true
}

///|
/// Make every bucket twice as wide by going one schema coarser, unless already at the
/// coarsest.
fn SparseState::coarsen(self : SparseState) -> Unit {
  if self.schema == schema_min {
    return
  }
  self.schema = self.schema - 1
  for side in [self.positive, self.negative] {
    let old = side.to_array()
    side.clear()
    for entry in old {
      // Integer division rounds toward zero, which is what pairs bucket 2k-1 and 2k for a
      // positive key and 2k and 2k+1 for a negative one.
      let key = (if entry.0 > 0 { entry.0 + 1 } else { entry.0 }) / 2
      add_to(side, key, entry.1)
    }
  }
}

///|
/// Keep an exemplar among the native ones: in order of value while there is room, then in
/// place of the oldest one if it has outlived `exemplar_ttl`, else in place of one of the two
/// closest in log value, so that the kept ones stay spread over the range.
fn SparseState::keep_exemplar(
  self : SparseState,
  e : Exemplar,
  at : Double,
) -> Unit {
  let limit = self.config.max_exemplars
  if limit <= 0 {
    return
  }
  let kept = self.exemplars
  if kept.length() < limit {
    let mut i = 0
    while i < kept.length() && !(e.value < kept[i].0.value) {
      i = i + 1
    }
    kept.insert(i, (e, at))
    return
  }
  if kept.length() == 1 {
    kept[0] = (e, at)
    return
  }
  let mut oldest_at = 0.0
  let mut oldest = -1
  let mut closest = -1.0
  let mut place = -1
  let mut replace = -1
  let mut current = 0.0
  for i, entry in kept {
    if oldest == -1 || entry.1 < oldest_at {
      oldest_at = entry.1
      oldest = i
    }
    if place == -1 && e.value <= entry.0.value {
      place = i
    }
    let previous = current
    current = @math.ln(entry.0.value)
    if i == 0 {
      continue
    }
    let diff = (current - previous).abs()
    if closest == -1.0 || diff < closest {
      closest = diff
      replace = if kept[i].1 < kept[i - 1].1 { i } else { i - 1 }
    }
  }
  if place == -1 {
    place = kept.length()
  }
  if oldest != -1 && at - oldest_at > self.config.exemplar_ttl {
    replace = oldest
  } else {
    let log = @math.ln(e.value)
    if place > 0 {
      let diff = (log - @math.ln(kept[place - 1].0.value)).abs()
      if diff < closest {
        closest = diff
        replace = place - 1
      }
    }
    if place < kept.length() {
      let diff = (@math.ln(kept[place].0.value) - log).abs()
      if diff < closest {
        replace = place
      }
    }
  }
  if replace == place {
    kept[place] = (e, at)
  } else if replace < place {
    kept.remove(replace) |> ignore
    kept.insert(place - 1, (e, at))
  } else {
    kept.remove(replace) |> ignore
    kept.insert(place, (e, at))
  }
}

///|
/// The native side as a value: populated buckets in key order.
fn SparseState::value(self : SparseState) -> Sparse {
  let ordered = (side : Map[Int32, Int64]) => {
    let pairs = side.to_array()
    pairs.sort_by_key(pair => pair.0)
    pairs
  }
  {
    schema: self.schema,
    zero_threshold: self.zero_threshold,
    zero_count: self.zero_count,
    positive: ordered(self.positive),
    negative: ordered(self.negative),
    exemplars: self.exemplars.map(entry => entry.0),
  }
}
