name = "moonbitstack/moonp8s"

version = "0.1.2"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonp8s"

license = "Apache-2.0"

keywords = [
  "prometheus",
  "p8s",
  "metrics",
  "openmetrics",
  "exposition",
  "monitoring",
  "observability",
  "telemetry",
  "counter",
  "gauge",
  "histogram",
  "summary",
  "exemplar",
  "pushgateway",
  "client",
  "asgi",
  "protobuf",
  "protobuf-export",
  "delimited",
  "scrape",
  "collector",
  "moonbit",
]

description = "Prometheus metrics for MoonBit."

source = "src"

import {
  "moonbitstack/moonasgi@0.11.2",
  "moonbitstack/moonast@0.3.0",
  "moonbitstack/moonproto@0.1.2",
  "moonbitlang/parser@0.4.8",
  "moonbitlang/async@0.22.5",
  "moonbitstack/moonjson@0.5.0",
}

preferred_target = "native"
