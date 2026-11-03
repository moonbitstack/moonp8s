// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The process numbers a `ProcessCollector` exports. The caller reads them —
/// this library performs no I/O — which keeps the collector portable across
/// every target.
pub(all) struct ProcessStats {
  cpu_seconds : Double
  open_fds : Int64
  max_fds : Int64
  virtual_memory_bytes : Int64
  resident_memory_bytes : Int64
  start_time_seconds : Double
  threads : Int64
}

///|
/// The seven `process_*` series the Rust client's process collector exposes:
/// CPU time, open and maximum file descriptors, virtual and resident memory,
/// start time, and thread count.
pub struct ProcessCollector {
  priv prefix : String
  priv stats : ProcessStats
}

///|
/// A process collector over `stats`. `namespace` prefixes every name, as the
/// Rust client's namespace does.
pub fn ProcessCollector::new(
  stats : ProcessStats,
  prefix? : String,
) -> ProcessCollector {
  { prefix: prefix.unwrap_or(""), stats, }
}

///|
fn process_name(prefix : String, name : String) -> String {
  if prefix == "" {
    name
  } else {
    prefix + "_" + name
  }
}

///|
fn process_family(
  prefix : String,
  name : String,
  kind : Kind,
  help : String,
  value : Value,
) -> MetricFamily {
  {
    name: process_name(prefix, name),
    kind,
    help,
    unit: None,
    metrics: [
      { labels: [], value, timestamp: None, created: None, exemplars: [], },
    ],
  }
}

///|
pub impl Collector for ProcessCollector with fn collect(self) {
  let stats = self.stats
  let prefix = self.prefix
  [
    process_family(
      prefix,
      "process_cpu_seconds",
      Kind::Counter,
      "Total user and system CPU time spent in seconds.",
      Number(stats.cpu_seconds),
    ),
    process_family(
      prefix,
      "process_open_fds",
      Kind::Gauge,
      "Number of open file descriptors.",
      Number(stats.open_fds.to_double()),
    ),
    process_family(
      prefix,
      "process_max_fds",
      Kind::Gauge,
      "Maximum number of open file descriptors.",
      Number(stats.max_fds.to_double()),
    ),
    process_family(
      prefix,
      "process_virtual_memory_bytes",
      Kind::Gauge,
      "Virtual memory size in bytes.",
      Number(stats.virtual_memory_bytes.to_double()),
    ),
    process_family(
      prefix,
      "process_resident_memory_bytes",
      Kind::Gauge,
      "Resident memory size in bytes.",
      Number(stats.resident_memory_bytes.to_double()),
    ),
    process_family(
      prefix,
      "process_start_time_seconds",
      Kind::Gauge,
      "Start time of the process since unix epoch in seconds.",
      Number(stats.start_time_seconds),
    ),
    process_family(
      prefix,
      "process_threads",
      Kind::Gauge,
      "Number of OS threads in the process.",
      Number(stats.threads.to_double()),
    ),
  ]
}

///|
pub extend ProcessCollector with Collector::{collect}
