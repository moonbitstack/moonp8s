// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The kind of a metric, as spelled in the `# TYPE` line of an exposition.
pub(all) enum Kind {
  Counter
  Gauge
  Histogram
  GaugeHistogram
  Summary
  Info
  StateSet
  Unknown
}

///|
/// The wire spelling of this kind: `counter`, `gauge`, `histogram`,
/// `gaugehistogram`, `summary`, `info`, `stateset`, or `unknown`.
pub fn Kind::code(self : Kind) -> String {
  match self {
    Kind::Counter => "counter"
    Kind::Gauge => "gauge"
    Kind::Histogram => "histogram"
    Kind::GaugeHistogram => "gaugehistogram"
    Kind::Summary => "summary"
    Kind::Info => "info"
    Kind::StateSet => "stateset"
    Kind::Unknown => "unknown"
  }
}

///|
/// The kind a wire spelling names. `untyped` is the legacy spelling of
/// `unknown`, and an unrecognised spelling is `unknown` rather than an error so
/// that a newer peer's exposition still parses.
pub fn Kind::of(name : String) -> Kind {
  match name {
    "counter" => Kind::Counter
    "gauge" => Kind::Gauge
    "histogram" => Kind::Histogram
    "gaugehistogram" => Kind::GaugeHistogram
    "summary" => Kind::Summary
    "info" => Kind::Info
    "stateset" => Kind::StateSet
    _ => Kind::Unknown
  }
}
