// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
priv struct FamilyAcc {
  name : String
  kind : @metric.Kind
  help : String
  mode : Mode?
  order : Array[String]
  index : Map[String, Int32]
  labels : Array[Array[(String, String)]]
  seen : Array[Int32]
  value : Array[Double]
  timestamp : Array[Double]
  count : Array[Double]
  sum : Array[Double]
  buckets : Array[Array[(Double, Double)]]
}

///|
fn FamilyAcc::new(
  name : String,
  kind : @metric.Kind,
  help : String,
  mode : Mode?,
) -> FamilyAcc {
  {
    name,
    kind,
    help,
    mode,
    order: [],
    index: Map([]),
    labels: [],
    seen: [],
    value: [],
    timestamp: [],
    count: [],
    sum: [],
    buckets: [],
  }
}

///|
fn sort_pairs(labels : Array[(String, String)]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in labels {
    out.push(pair)
  }
  out.sort_by(fn(a, b) { String::lexical_compare(a.0, b.0) })
  out
}

///|
fn label_key(labels : Array[(String, String)]) -> String {
  let sb = StringBuilder()
  for pair in labels {
    sb.write_string(pair.0.length().to_string())
    sb.write_char(':')
    sb.write_string(pair.0)
    sb.write_string(pair.1.length().to_string())
    sb.write_char(':')
    sb.write_string(pair.1)
  }
  sb.to_string()
}

///|
fn without(
  labels : Array[(String, String)],
  name : String,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in labels {
    if pair.0 != name {
      out.push(pair)
    }
  }
  out
}

///|
fn lookup(labels : Array[(String, String)], name : String) -> String? {
  for pair in labels {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn FamilyAcc::slot(self : FamilyAcc, labels : Array[(String, String)]) -> Int32 {
  let sorted = sort_pairs(labels)
  let key = label_key(sorted)
  match self.index.get(key) {
    Some(i) => i
    None => {
      let i = self.order.length()
      self.order.push(key)
      self.index[key] = i
      self.labels.push(sorted)
      self.seen.push(0)
      self.value.push(0.0)
      self.timestamp.push(0.0)
      self.count.push(0.0)
      self.sum.push(0.0)
      self.buckets.push([])
      i
    }
  }
}

///|
fn add_bucket(
  buckets : Array[(Double, Double)],
  le : Double,
  value : Double,
) -> Unit {
  for i = 0; i < buckets.length(); i = i + 1 {
    if buckets[i].0 == le {
      buckets[i] = (le, buckets[i].1 + value)
      return
    }
  }
  buckets.push((le, value))
}

///|
fn parse_le(text : String) -> Double raise @metric.Refused {
  let t = text.trim().to_owned()
  match t {
    "+Inf" | "Inf" | "+inf" | "inf" | "INF" => 1.0 / 0.0
    "-Inf" | "-inf" | "-INF" => 0.0 - 1.0 / 0.0
    _ =>
      @string.parse_double(t) catch {
        _ => raise @metric.Refused("a bucket bound is not a number: " + text)
      }
  }
}

///|
/// One family's slots turned into a family: numbers for counters and gauges,
/// cumulative buckets for histograms, count and sum for summaries.
fn FamilyAcc::finish(self : FamilyAcc) -> @metric.MetricFamily {
  let points : Array[@metric.Point] = []
  for i = 0; i < self.order.length(); i = i + 1 {
    let labels = self.labels[i]
    let value = match self.kind {
      @metric.Kind::Counter => @metric.Value::Number(self.value[i])
      @metric.Kind::Gauge => @metric.Value::Number(self.value[i])
      @metric.Kind::Summary =>
        @metric.Value::Quantiles(
          quantiles=[],
          sum=self.sum[i],
          count=self.count[i].to_int64(),
        )
      @metric.Kind::Histogram | @metric.Kind::GaugeHistogram => {
        let sorted : Array[(Double, Double)] = []
        for pair in self.buckets[i] {
          sorted.push(pair)
        }
        sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
        let cumulative : Array[(Double, Int64)] = []
        let mut acc = 0.0
        for pair in sorted {
          acc = acc + pair.1
          if pair.0 == 1.0 / 0.0 {
            continue
          }
          cumulative.push((pair.0, acc.to_int64()))
        }
        @metric.Value::Buckets(
          buckets=cumulative,
          sum=self.sum[i],
          count=acc.to_int64(),
        )
      }
      _ => @metric.Value::Number(self.value[i])
    }
    points.push({
      labels,
      value,
      timestamp: None,
      created: None,
      exemplars: [],
    })
  }
  {
    name: self.name,
    kind: self.kind,
    help: self.help,
    unit: None,
    metrics: points,
  }
}

///|
/// Fold the parts into one set of families.
///
/// Counters and summaries add up across processes; histograms add up per bucket
/// and are made cumulative again; a gauge follows its mode. Families come out in
/// the order their first part mentions them, and series in the order they were
/// first seen, so two runs over the same directory write the same bytes.
///
/// A family that two files disagree about — a name that is a counter in one
/// process and a histogram in another, or a gauge written under two modes — is
/// refused. The numbers would be meaningless, and a scrape that says so is
/// better than one that quietly picks a side.
pub fn merge(
  parts : Array[Part],
) -> Array[@metric.MetricFamily] raise @metric.Refused {
  let families : Array[FamilyAcc] = []
  let index : Map[String, Int32] = Map([])
  for part in parts {
    for entry in part.entries {
      if part.kind is @metric.Kind::Gauge && part.mode is None {
        raise @metric.Refused("a gauge file without a mode: " + part.pid)
      }
      let fi = match index.get(entry.metric) {
        Some(i) => {
          let known = families[i]
          if known.kind.code() != part.kind.code() {
            raise @metric.Refused(
              entry.metric +
              " is a " +
              known.kind.code() +
              " in one file and a " +
              part.kind.code() +
              " in another",
            )
          }
          match (known.mode, part.mode) {
            (Some(a), Some(b)) =>
              if a.code() != b.code() {
                raise @metric.Refused(
                  entry.metric +
                  " is written under two gauge modes: " +
                  a.code() +
                  " and " +
                  b.code(),
                )
              }
            _ => ()
          }
          i
        }
        None => {
          let i = families.length()
          families.push(
            FamilyAcc::new(entry.metric, part.kind, entry.help, part.mode),
          )
          index[entry.metric] = i
          i
        }
      }
      let family = families[fi]
      match part.kind {
        @metric.Kind::Counter => {
          let slot = family.slot(entry.labels)
          family.value[slot] = family.value[slot] + entry.value
          family.seen[slot] = family.seen[slot] + 1
        }
        @metric.Kind::Summary => {
          let slot = family.slot(entry.labels)
          if entry.sample.has_suffix("_count") {
            family.count[slot] = family.count[slot] + entry.value
            family.seen[slot] = family.seen[slot] + 1
          } else if entry.sample.has_suffix("_sum") {
            family.sum[slot] = family.sum[slot] + entry.value
            family.seen[slot] = family.seen[slot] + 1
          }
        }
        @metric.Kind::Histogram | @metric.Kind::GaugeHistogram =>
          match lookup(entry.labels, "le") {
            Some(le_text) => {
              let le = parse_le(le_text)
              let slot = family.slot(without(entry.labels, "le"))
              add_bucket(family.buckets[slot], le, entry.value)
              family.seen[slot] = family.seen[slot] + 1
            }
            None =>
              if entry.sample.has_suffix("_sum") ||
                entry.sample.has_suffix("_gsum") {
                let slot = family.slot(entry.labels)
                family.sum[slot] = family.sum[slot] + entry.value
                family.seen[slot] = family.seen[slot] + 1
              }
          }
        @metric.Kind::Gauge => {
          let mode = match part.mode {
            Some(m) => m
            None =>
              raise @metric.Refused("a gauge file without a mode: " + part.pid)
          }
          if mode.is_separate() {
            let labels : Array[(String, String)] = []
            for pair in entry.labels {
              labels.push(pair)
            }
            labels.push(("pid", part.pid))
            let slot = family.slot(labels)
            family.value[slot] = entry.value
            family.timestamp[slot] = entry.timestamp
            family.seen[slot] = family.seen[slot] + 1
          } else {
            let slot = family.slot(entry.labels)
            if family.seen[slot] == 0 {
              family.value[slot] = entry.value
              family.timestamp[slot] = entry.timestamp
            } else if mode.code() == "sum" || mode.code() == "livesum" {
              family.value[slot] = family.value[slot] + entry.value
            } else if mode.code() == "min" || mode.code() == "livemin" {
              if entry.value < family.value[slot] {
                family.value[slot] = entry.value
              }
            } else if mode.code() == "max" || mode.code() == "livemax" {
              if entry.value > family.value[slot] {
                family.value[slot] = entry.value
              }
            } else if entry.timestamp > family.timestamp[slot] {
              // A later value wins; at the same timestamp the value already
              // kept stays, so the answer does not depend on file order.
              family.value[slot] = entry.value
              family.timestamp[slot] = entry.timestamp
            }
            family.seen[slot] = family.seen[slot] + 1
          }
        }
        _ =>
          raise @metric.Refused("no multiprocess form for " + part.kind.code())
      }
    }
  }
  let out : Array[@metric.MetricFamily] = []
  for family in families {
    out.push(family.finish())
  }
  out
}
