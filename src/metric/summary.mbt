// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A Greenwald-Khanna sketch: it keeps a sorted summary of the observations so
/// that a quantile can be answered to within `epsilon` of the rank using memory
/// logarithmic in the number of observations. The targeted-quantile (CKMS)
/// family generalises this sketch; a single epsilon is what a summary's
/// quantile-and-error pairs reduce to.
struct Gk {
  epsilon : Double
  mut n : Int64
  buf : Array[(Double, Int64, Int64)]
}

///|
fn Gk::new(epsilon : Double) -> Gk {
  { epsilon, n: 0L, buf: [], }
}

///|
fn Gk::compress(self : Gk) -> Unit {
  let threshold = (2.0 * self.epsilon * self.n.to_double()).to_int64()
  let mut i = self.buf.length() - 2
  while i >= 1 {
    let v = self.buf[i].0
    let g = self.buf[i].1
    let next_g = self.buf[i + 1].1
    let next_delta = self.buf[i + 1].2
    if g + next_g + next_delta <= threshold {
      self.buf[i] = (v, g + next_g, next_delta)
      ignore(self.buf.remove(i + 1))
    }
    i = i - 1
  }
}

///|
fn Gk::insert(self : Gk, v : Double) -> Unit {
  let mut i = 0
  while i < self.buf.length() && self.buf[i].0 <= v {
    i = i + 1
  }
  let delta = if i == 0 || i == self.buf.length() {
    0L
  } else {
    let d = (2.0 * self.epsilon * self.n.to_double()).to_int64() - 1L
    if d < 0L {
      0L
    } else {
      d
    }
  }
  self.buf.insert(i, (v, 1L, delta))
  self.n = self.n + 1L
  let period = (1.0 / (2.0 * self.epsilon)).to_int64()
  if period > 0L && self.n % period == 0L {
    self.compress()
  }
}

///|
fn Gk::query(self : Gk, q : Double) -> Double {
  if self.buf.length() == 0 {
    return 0.0
  }
  let rank = q * self.n.to_double()
  let mut r = 0L
  for i = 0; i < self.buf.length(); i = i + 1 {
    r = r + self.buf[i].1
    if r.to_double() + self.buf[i].2.to_double() > rank {
      return self.buf[i].0
    }
  }
  self.buf[self.buf.length() - 1].0
}

///|
/// A summary: the count and sum of the observations, plus approximate quantiles
/// when the constructor is given target quantiles and their permitted rank
/// error.
pub struct Summary {
  priv mut count : Int64
  priv mut sum : Double
  priv created : Double?
  priv targets : Array[(Double, Double)]
  priv sketch : Gk?
}

///|
/// A summary. With `quantiles` (pairs of target quantile and permitted error),
/// observations also feed a sketch so that `snapshot` can report those
/// quantiles; without them the summary carries only count and sum, as the
/// official clients do by default.
pub fn Summary::new(
  quantiles? : Array[(Double, Double)],
  created? : Double,
) -> Summary raise Refused {
  let targets : Array[(Double, Double)] = match quantiles {
    Some(qs) => qs
    None => []
  }
  let mut epsilon = 0.0
  for pair in targets {
    let q = pair.0
    let err = pair.1
    if q != q || q < 0.0 || q > 1.0 {
      raise Refused("quantile target out of [0, 1]: " + q.to_string())
    }
    if err != err || err <= 0.0 {
      raise Refused("quantile error must be positive, got " + err.to_string())
    }
    if err > epsilon {
      epsilon = err
    }
  }
  {
    count: 0L,
    sum: 0.0,
    created,
    targets,
    sketch: if targets.length() > 0 {
      Some(Gk::new(epsilon))
    } else {
      None
    },
  }
}

///|
/// Record one observation.
pub fn Summary::observe(self : Summary, v : Double) -> Unit {
  self.count = self.count + 1L
  self.sum = self.sum + v
  match self.sketch {
    Some(g) => g.insert(v)
    None => ()
  }
}

///|
/// The snapshot of this summary: the configured quantiles (empty when none were
/// configured), the sum, and the count.
pub fn Summary::snapshot(self : Summary) -> Point {
  let quantiles : Array[(Double, Double)] = match self.sketch {
    Some(g) => self.targets.map(fn(pair) { (pair.0, g.query(pair.0)) })
    None => []
  }
  {
    labels: [],
    value: Quantiles(quantiles~, sum=self.sum, count=self.count),
    timestamp: None,
    created: self.created,
    exemplars: [],
  }
}

///|
/// The number of observations.
pub fn Summary::total(self : Summary) -> Int64 {
  self.count
}

///|
pub impl Metric for Summary with fn kind(_self) {
  Kind::Summary
}

///|
pub impl Metric for Summary with fn points(self) {
  [self.snapshot()]
}

///|
pub extend Summary with Metric::{kind, points}
