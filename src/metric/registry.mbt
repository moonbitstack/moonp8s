// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A custom source of metric families. Implement this to contribute series whose
/// shape the built-in metric types do not cover; the registry applies its prefix
/// and constant labels to whatever `collect` returns.
pub(open) trait Collector {
  fn collect(Self) -> Array[MetricFamily]
}

///|
struct Entry {
  name : String
  help : String
  unit : String?
  metric : &Metric
}

///|
/// The set of metrics one exposition exposes, with an optional name prefix and
/// optional constant labels applied to everything registered. A registry refuses
/// a metric name that is not a valid OpenMetrics name, a label name that is not
/// a valid label name, a unit that is not a valid unit, and a name registered
/// twice.
pub struct Registry {
  priv prefix : String
  priv labels : Array[(String, String)]
  priv entries : Array[Entry]
  priv seen : Map[String, Unit]
  /// Every sample name already spent, mapped to the family that spends it. A
  /// gauge called `orders_total` next to a counter called `orders` would write
  /// two different series under one name, so the second registration is refused.
  priv taken : Map[String, String]
  priv collectors : Array[&Collector]
}

///|
/// An empty registry. `prefix` is prepended to every registered name, and
/// `labels` is added to every series.
pub fn Registry::new(
  prefix? : String,
  labels? : Array[(String, String)],
) -> Registry raise Refused {
  let prefix = prefix.unwrap_or("")
  let labels = labels.unwrap_or([])
  if prefix != "" && !is_valid_metric_name(prefix) {
    raise Refused("invalid name prefix: " + prefix)
  }
  for pair in labels {
    check_label_name(pair.0)
  }
  {
    prefix,
    labels,
    entries: [],
    seen: Map([]),
    taken: Map([]),
    collectors: [],
  }
}

///|
fn Registry::full_name(self : Registry, name : String) -> String {
  if self.prefix == "" {
    name
  } else {
    self.prefix + "_" + name
  }
}

///|
fn apply_unit(name : String, unit : String?) -> String {
  match unit {
    Some(u) => {
      let suffix = "_" + u
      if name.length() >= suffix.length() &&
        name[name.length() - suffix.length():].to_owned() == suffix {
        name
      } else {
        name + suffix
      }
    }
    None => name
  }
}

///|
/// The sample names a family of this kind writes in the text formats. Two
/// families whose sample names overlap would produce an exposition in which one
/// series name appears twice.
fn sample_names(name : String, kind : Kind) -> Array[String] {
  match kind {
    Kind::Counter => [name + "_total", name + "_created"]
    Kind::Info => [name + "_info"]
    Kind::Histogram =>
      [name + "_bucket", name + "_count", name + "_sum", name + "_created"]
    Kind::GaugeHistogram =>
      [name + "_bucket", name + "_gcount", name + "_gsum", name + "_created"]
    Kind::Summary => [name, name + "_count", name + "_sum", name + "_created"]
    _ => [name]
  }
}

///|
/// Register `metric` under `name`, with `help` and an optional `unit`. The unit
/// is appended to the name on the wire.
pub fn Registry::register(
  self : Registry,
  name : String,
  help : String,
  metric : &Metric,
  unit? : String,
) -> Unit raise Refused {
  check_metric_name(name)
  match unit {
    Some(u) => check_unit(u)
    None => ()
  }
  let kind = metric.kind()
  if unit is Some(_) && kind is (Info | StateSet) {
    raise Refused("a metric of this kind cannot have a unit: " + name)
  }
  // A counter's samples get `_total` when written, so a name that already says it is munged the
  // way client_python munges it, or it would come out twice.
  let named = self.full_name(name)
  let family = match (kind, named.strip_suffix("_total")) {
    (Counter, Some(stem)) => stem.to_owned()
    _ => named
  }
  let full = apply_unit(family, unit)
  if !is_valid_metric_name(full) {
    raise Refused("invalid metric name: " + full)
  }
  match self.seen.get(full) {
    Some(_) => raise Refused("metric already registered: " + full)
    None => ()
  }
  match self.taken.get(full) {
    Some(owner) =>
      raise Refused(
        full +
        " is already the sample of " +
        owner +
        ", so another family cannot take the name",
      )
    None => ()
  }
  for sample in sample_names(full, kind) {
    match self.seen.get(sample) {
      Some(_) =>
        raise Refused(
          "metric " + sample + " would share a sample name with " + full,
        )
      None => ()
    }
    match self.taken.get(sample) {
      Some(owner) =>
        raise Refused(
          full +
          " would write " +
          sample +
          ", which is already " +
          owner +
          "'s sample",
        )
      None => ()
    }
  }
  self.seen[full] = ()
  for sample in sample_names(full, kind) {
    self.taken[sample] = full
  }
  self.entries.push({ name: full, help, unit, metric, })
}

///|
/// Create a counter, register it, and return it.
pub fn Registry::counter(
  self : Registry,
  name : String,
  help : String,
  unit? : String,
) -> Counter raise Refused {
  let metric = Counter::new()
  self.register(name, help, metric, unit?)
  metric
}

///|
/// Create a gauge, register it, and return it.
pub fn Registry::gauge(
  self : Registry,
  name : String,
  help : String,
  unit? : String,
) -> Gauge raise Refused {
  let metric = Gauge::new()
  self.register(name, help, metric, unit?)
  metric
}

///|
/// Create a histogram, register it, and return it.
pub fn Registry::histogram(
  self : Registry,
  name : String,
  help : String,
  buckets? : Array[Double],
  unit? : String,
) -> Histogram raise Refused {
  let metric = match buckets {
    Some(b) => Histogram::new(buckets=b)
    None => Histogram::new()
  }
  self.register(name, help, metric, unit?)
  metric
}

///|
/// A sub-registry whose names carry `prefix` after this registry's own prefix,
/// and whose series carry this registry's labels plus `labels`.
pub fn Registry::sub(
  self : Registry,
  prefix~ : String,
  labels? : Array[(String, String)],
) -> Registry raise Refused {
  if !is_valid_metric_name(prefix) {
    raise Refused("invalid name prefix: " + prefix)
  }
  let extra = labels.unwrap_or([])
  for pair in extra {
    check_label_name(pair.0)
  }
  let combined = if self.prefix == "" {
    prefix
  } else {
    self.prefix + "_" + prefix
  }
  {
    prefix: combined,
    labels: self.labels + extra,
    entries: [],
    seen: Map([]),
    taken: Map([]),
    collectors: [],
  }
}

///|
/// Add a custom collector. Its families are exposed after the registered
/// metrics, with this registry's prefix and labels applied.
pub fn Registry::add(self : Registry, collector : &Collector) -> Unit {
  self.collectors.push(collector)
}

///|
fn stamp(point : Point, at : Double?) -> Point {
  match point.timestamp {
    Some(_) => point
    None =>
      match at {
        Some(when) => { ..point, timestamp: Some(when), }
        None => point
      }
  }
}

///|
fn Registry::gather(self : Registry, at : Double?) -> Array[MetricFamily] {
  let out : Array[MetricFamily] = []
  for entry in self.entries {
    let labelled = entry.metric
      .points()
      .map(fn(p) { stamp({ ..p, labels: self.labels + p.labels, }, at) })
    out.push({
      name: entry.name,
      kind: entry.metric.kind(),
      help: entry.help,
      unit: entry.unit,
      metrics: labelled,
    })
  }
  for collector in self.collectors {
    for family in collector.collect() {
      let labelled = family.metrics.map(fn(p) {
        stamp({ ..p, labels: self.labels + p.labels, }, at)
      })
      out.push({
        ..family,
        name: self.full_name(family.name),
        metrics: labelled,
      })
    }
  }
  out
}

///|
/// The snapshot of everything registered: one family per registered metric or
/// collector family, in registration order.
///
/// `at` is the moment of the scrape. Every sample that does not already carry a
/// timestamp is stamped with it, which is what a real scrape does: the exporter does
/// not know when it will be read. A sample that was given a timestamp keeps it — a
/// backfilled point is not the scrape's.
pub fn Registry::collect(self : Registry, at? : Double) -> Array[MetricFamily] {
  self.gather(at)
}
