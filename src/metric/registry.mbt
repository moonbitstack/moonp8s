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
  { prefix, labels, entries: [], seen: Map([]), collectors: [], }
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
  let full = apply_unit(self.full_name(name), unit)
  if !is_valid_metric_name(full) {
    raise Refused("invalid metric name: " + full)
  }
  match self.seen.get(full) {
    Some(_) => raise Refused("metric already registered: " + full)
    None => ()
  }
  self.seen[full] = ()
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
fn Registry::gather(self : Registry) -> Array[MetricFamily] {
  let out : Array[MetricFamily] = []
  for entry in self.entries {
    let labelled = entry.metric
      .points()
      .map(fn(p) { { ..p, labels: self.labels + p.labels, } })
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
        { ..p, labels: self.labels + p.labels, }
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
pub fn Registry::collect(self : Registry) -> Array[MetricFamily] {
  self.gather()
}
