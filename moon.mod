name = "moonbitstack/moonp8s"

version = "0.1.1"

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
  "moonbit",
]

description = "Prometheus metrics for MoonBit."

source = "src"

import {
  "moonbitstack/moonasgi@0.10.6",
  "moonbitstack/moonast@0.2.6",
  "moonbitlang/parser@0.4.6",
  "moonbitlang/async@0.22.5",
}

preferred_target = "native"
