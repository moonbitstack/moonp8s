// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An exemplar ties a sample to the request that produced it: the request's
/// labels, the observed value, and optionally when it was observed (Unix
/// seconds).
pub(all) struct Exemplar {
  labels : Array[(String, String)]
  value : Double
  timestamp : Double?
}

///|
/// OpenMetrics caps an exemplar's combined label names and values at 128
/// characters; a longer set makes the exemplar unrepresentable.
pub let exemplar_label_limit : Int32 = 128

///|
/// Build an exemplar, refusing a label set over the OpenMetrics limit.
pub fn Exemplar::new(
  labels : Array[(String, String)],
  value : Double,
  timestamp? : Double,
) -> Exemplar raise Refused {
  let mut total = 0
  for pair in labels {
    total = total + pair.0.length() + pair.1.length()
  }
  if total > exemplar_label_limit {
    raise Refused(
      "exemplar labels total " +
      total.to_string() +
      " characters, limit " +
      exemplar_label_limit.to_string(),
    )
  }
  { labels, value, timestamp, }
}

///|
/// The value of one series. A histogram carries its cumulative buckets, sum,
/// and count together so that one series stays one `Point`; a summary carries
/// its quantiles, sum, and count the same way; a state set carries every state
/// with its flag.
pub(all) enum Value {
  Number(Double)
  Buckets(buckets~ : Array[(Double, Int64)], sum~ : Double, count~ : Int64)
  Quantiles(quantiles~ : Array[(Double, Double)], sum~ : Double, count~ : Int64)
  State(states~ : Array[(String, Bool)])
}

///|
/// One series of a family: its labels, its value, and the optional metadata
/// OpenMetrics carries alongside it. `created` is when the series was created
/// (Unix seconds); `exemplars` are the retained exemplars, matched to histogram
/// buckets by the value that produced them.
pub(all) struct Point {
  labels : Array[(String, String)]
  value : Value
  timestamp : Double?
  created : Double?
  exemplars : Array[Exemplar]
}

///|
/// A family of series sharing one name, help text, kind, and optional unit.
/// This is what an exposition is written from and what a parser produces.
pub(all) struct MetricFamily {
  name : String
  kind : Kind
  help : String
  unit : String?
  metrics : Array[Point]
}

///|
/// A point with no labels and no metadata, the shape a bare metric collects
/// into before its registry or family adds labels.
pub fn point_of(value : Value) -> Point {
  { labels: [], value, timestamp: None, created: None, exemplars: [], }
}
