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
  type Gauge,
  type Histogram,
  type GaugeHistogram,
  type Summary,
  type Info,
  type StateSet,
  type Family,
  type TypedFamily,
  type Registry,
  buckets,
  exemplar_label_limit,
  exponential,
  is_valid_label_name,
  is_valid_metric_name,
  is_valid_unit,
  linear,
}

///|
/// The exposition formats and their encoders and parser.
pub using @expo {type Format, format_float, negotiate, openmetrics, text}

///|
/// Push gateway request construction.
pub using @push {type PushRequest, delete, push, push_add}

///|
/// The `/metrics` handler and the request-counting middleware for an ASGI app.
pub using @asgi {app, middleware}
