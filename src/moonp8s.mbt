// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The metric model re-exported for callers that want one import.
pub using @metric {
  type Kind,
  type Value,
  type Point,
  type MetricFamily,
  type Exemplar,
  type Counter,
  type LocalCounter,
  type Gauge,
  type Histogram,
  type GaugeHistogram,
  type Summary,
  type Info,
  type StateSet,
  type Family,
  trait LabelSet,
  type TypedFamily,
  type Registry,
  type ProcessCollector,
  type ProcessStats,
  buckets,
  exemplar_label_limit,
  exponential,
  is_valid_label_name,
  is_valid_metric_name,
  is_valid_unit,
  linear,
}

///|
/// The exposition formats and their encoders and parser, and the protobuf
/// format a scraper reads.
pub using @expo {
  type Format,
  format_float,
  negotiate,
  openmetrics,
  protobuf,
  protobuf_content_type,
  text,
  wants_protobuf,
}

///|
/// How several processes' values become one series, and the model of the files
/// they leave behind. The directory these files live in is a native package of
/// its own: `moonbitstack/moonp8s/multiproc/directory`.
pub using @multiproc {type Mode, type Entry, type Part, merge}

///|
/// Push gateway request construction.
pub using @push {type PushRequest, delete, push, push_add}

///|
/// The `/metrics` handler and the request-counting middleware for an ASGI app.
pub using @asgi {app, middleware}
