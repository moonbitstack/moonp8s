name = "moonbitstack/moonp8s"

version = "0.2.1"

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
  "moonbitstack/moonasgi@0.11.3",
  "moonbitstack/moonast@0.3.2",
  "moonbitstack/moonproto@0.2.1",
  "moonbitlang/parser@0.4.9",
  "moonbitlang/async@0.22.5",
  "moonbitstack/moonjson@0.5.1",
  "moonbitstack/moonbase@0.5.1",
}

preferred_target = "native"
