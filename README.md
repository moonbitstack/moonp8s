# moonp8s

Prometheus metrics for MoonBit: the metric types, a registry, both text
exposition formats, a parser for them, push gateway requests, and an ASGI
handler. It is a data model and a format implementation, not a server: it never
opens a socket and never reads a clock, so a scrape and a push stay something
the caller schedules.

The site is at **https://moonbitstack.github.io/moonp8s/** — a guide, the
generated reference, a parser to try, and four runnable examples.

## Install

```bash
moon add moonbitstack/moonp8s
```

## Annotations

Count and time a function by saying so on it. The function stays as it is, and a generator adds one
beside it:

```moonbit
#p8s.counter("orders_total", help="Orders asked for.")
#p8s.counter("orders_refused_total", help="Orders refused.", on=raised)
#p8s.timed("order_seconds", help="Seconds to place an order.", buckets="0.5, 1, 5")
fn place(item : String) -> Int raise Sold {
  ...
}
```

The generator writes one metric per annotation as a top-level `let`, `place_metered`, and
`register_metrics`, which puts them all in a registry:

<!-- nocheck -->
```moonbit
let registry = @moonp8s.Registry::new()
register_metrics(registry)
let receipt = place_metered("tea", now=clock)
```

`on` says when a counter moves: `call` (the default), `done` for a call that returned, or `raised`.
`buckets` defaults to the same list as `Histogram::new`. `now` is a clock in seconds, asked for only
when something is timed. The wrapper records a timing whichever way the call ends, a cancelled one
included.

The generator wires in as a dev_build rule, in `moon.mod`:

<!-- nocheck -->
```
rule(name: "metrics", command: "moonx moonbitstack/moonp8s/cmd/metrics -C \"$mod_dir\" \"$input\" -o \"$output\"")
```

and in the `moon.pkg` of the package, which imports `moonbitstack/moonp8s` and
`moonbitstack/moonp8s/metric`:

<!-- nocheck -->
```
dev_build(rule: "metrics", input: "orders.mbt", output: "orders.g.mbt")
formatter(ignore: [ "orders.g.mbt" ])
```

`moon run src/examples/08-annotated` shows it.

## Quick start

```moonbit
import {
  "moonbitstack/moonp8s",
  "moonbitstack/moonp8s/metric",
}

try {
  let registry = @moonp8s.Registry::new()
  let requests = registry.counter("http_requests", "HTTP requests.")
  requests.inc()
  let latency = registry.histogram("request_latency_seconds", "Latency.")
  latency.observe(0.25)
  println(@moonp8s.text(registry.collect()))
} catch {
  @metric.Refused(message) => println("refused: " + message)
}
```

`text` writes the compatibility format, version 0.0.4. `openmetrics` writes
OpenMetrics 1.0 and ends with `# EOF`:

```moonbit
let body = @moonp8s.openmetrics(registry.collect())
let content_type = @moonp8s.Format::OpenMetrics100.content_type()
```

## Metric types

| Type | Methods | Notes |
|:--|:--|:--|
| `Counter` | `inc(by~, exemplar?)`, `reset(created?)`, `get()` | Only increases; a negative step is refused. |
| `Gauge` | `set(v, timestamp?)`, `inc(by~)`, `dec(by~)`, `set_function(f)`, `get()` | Pass the timestamp to date a sample; a function replaces the stored value. |
| `Histogram` | `observe(v, exemplar?)`, `snapshot()` | Buckets from `buckets~`; `linear` and `exponential` build them. |
| `GaugeHistogram` | `observe`, `snapshot()` | A gauge's sum and count over histogram buckets. |
| `Summary` | `observe(v)`, `snapshot()` | Count and sum by default; `quantiles~` adds estimates. |
| `Info` | `Info::new(labels)` | A fixed label set whose value is 1. |
| `StateSet` | `set`, `unset`, `set_many`, `get` | `StateSet::exclusive` keeps exactly one state true. |

A hot counter can accumulate through a shard and flush when it is scraped:

```moonbit
let shard = requests.shard()
shard.inc()
shard.flush()
```

`ProcessCollector` exports the seven `process_*` series from a `ProcessStats`
value; the caller reads the numbers, so the collector stays portable and does
no I/O of its own.

The default histogram buckets are the shared client defaults, 0.005 through 10:

```moonbit
let h = @moonp8s.Histogram::new(buckets=@moonp8s.linear(1.0, 1.0, 5))
```

A summary with quantiles uses a Greenwald-Khanna sketch, so memory grows with
the log of the observation count rather than with the count:

```moonbit
let s = @moonp8s.Summary::new(quantiles=[(0.5, 0.01), (0.9, 0.01), (0.99, 0.001)])
```

## Labels and families

`Family` fixes the label names at construction and creates one child per
combination of values:

```moonbit
let requests = @moonp8s.Family::new(["method", "code"], fn() {
  @moonp8s.Counter::new()
})
requests.labels(["GET", "200"]).inc()
requests.labels(["POST", "500"]).inc(by=2.0)
```

When the label combination is better expressed as a record, implement
`LabelSet` and use `TypedFamily`:

```moonbit
struct Route {
  method : String
  path : String
} derive(Eq, Hash)

impl @moonp8s.LabelSet for Route with pairs(self) {
  [("method", self.method), ("path", self.path)]
}
```

## Registry

A registry applies an optional name prefix and constant labels, refuses an
invalid name, a duplicate name, and an invalid unit, and collects everything in
registration order. A counter's name may end in `_total` or not: the family is named without it,
and its samples are written with it, so it comes out once:

```moonbit
let registry = @moonp8s.Registry::new(prefix="app", labels=[("region", "eu")])
let requests = registry.counter("http_requests", "HTTP requests.")
let sub = registry.sub(prefix="http", labels=[("server", "a")])
```

A custom source implements `Collector` and is added with `add`; the registry
applies its prefix and constant labels to the families the collector returns.

## Exposition

| Function | Result |
|:--|:--|
| `text(families)` | Prometheus text format, version 0.0.4 |
| `openmetrics(families)` | OpenMetrics text format, version 1.0.0, ending in `# EOF` |
| `negotiate(accept)` | `Format` chosen from an `Accept` header |
| `parse(text, format~)` | the families an exposition describes |

`parse` reads both formats. The compatibility format is lossy for info and
state sets, which it spells as gauges; OpenMetrics keeps them.

## Push gateway

`push`, `push_add`, and `delete` build the request; the caller sends it:

```moonbit
let request = @moonp8s.push(
  "pushgateway.local",
  "batch",
  registry.collect(),
  grouping_key=[("instance", "worker-1")],
)
println(request.http_method + " " + request.path)
println(request.body)
```

Grouping key values that contain a slash or a space, and empty values, use the
gateway's `@base64` form.

## ASGI

`app` serves `/metrics`; `middleware` counts requests and observes their
duration. The clock is a parameter so a test can drive time:

```moonbit
let handler = @moonp8s.app(registry)
let wrapped = @moonp8s.middleware(registry)
```

## Packages

| Package | Contents |
|:--|:--|
| `moonbitstack/moonp8s` | Re-exports the common types and functions. |
| `moonbitstack/moonp8s/metric` | Metric types, families, the registry, and the snapshot model. |
| `moonbitstack/moonp8s/expo` | Both text formats, their negotiation, and the parser. |
| `moonbitstack/moonp8s/push` | Push gateway request construction. |
| `moonbitstack/moonp8s/asgi` | The `/metrics` handler and the counting middleware. |

## Migration

`moonbitstack/moonp8s/compat` rebuilds the legacy counter vector, server metric
set, and remote report writer on the registry model, so an existing caller can
move over one import at a time.

## License

Apache-2.0.
