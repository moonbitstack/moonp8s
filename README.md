# moonp8s

Prometheus metrics for MoonBit: the metric types, a registry, both text
exposition formats, a parser for them, push gateway requests, and an ASGI
handler. It is a data model and a format implementation, not a server: it never
opens a socket and never reads a clock, so a scrape and a push stay something
the caller schedules.

The site is at **https://moonbitstack.github.io/moonp8s/** — a guide, the
generated reference, a parser to try, and five runnable examples.

## Install

```bash
moon add moonbitstack/moonp8s
```

## Annotations

Count and time a function by saying so on it. The function stays as it is, and a generator adds one
beside it:

<!-- nocheck -->
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
let registry = @moonp8s.Registry::new()
let requests = registry.counter("http_requests", "HTTP requests.")
requests.inc()
let latency = registry.histogram("request_latency_seconds", "Latency.")
latency.observe(0.25)
println(@moonp8s.text(registry.collect()))
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
| `Counter` | `inc(by~, exemplar?)`, `reset(created?)`, `get()` | Only increases; a negative step or NaN is refused. A reset dates the series anew, or forgets when it started. |
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
let served = @moonp8s.Family::new(["method", "code"], fn() {
  @moonp8s.Counter::new()
})
served.labels(["GET", "200"]).inc()
served.labels(["POST", "500"]).inc(by=2.0)
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
let reg = @moonp8s.Registry::new(prefix="app", labels=[("region", "eu")])
let req = reg.counter("http_requests", "HTTP requests.")
let sub = reg.sub(prefix="http", labels=[("server", "a")])
```

A custom source implements `Collector` and is added with `add`; the registry
applies its prefix and constant labels to the families the collector returns.

A name is refused when it would collide with a sample another family already writes: a
gauge called `orders_total` next to a counter called `orders` would put two different
series under one name, so the second registration is refused with the name it would
have taken.

## Several processes

A worker pool counts the same metric once per worker. Each process writes what it has
counted to its own file in one directory; the process that answers `/metrics` reads the
directory and adds the files up. Nothing is shared, so a scrape never waits for a
worker that is busy.

<!-- nocheck -->
```moonbit
// moon.pkg: import { "moonbitstack/moonp8s/multiproc/directory" }
let written = @directory.write(
  dir,
  7,
  registry.collect(),
  modes=[("queue_depth", @moonp8s.Mode::Sum)],
)
```

`write` replaces this process's files. They hold the totals since the process started,
not a delta, so flushing twice is flushing once; each file is written beside its final
name and renamed into place, so a scrape reads a whole file or the previous one.

The scrape side is one call:

<!-- nocheck -->
```moonbit
let families = @directory.collect(dir, at=1_700_000_015.0)
let body = @moonp8s.openmetrics(families)
```

Counters, histograms, and summaries add up across processes. A gauge does not, so its
mode says what to do with the values from the other processes:

| Mode | The series becomes |
|:--|:--|
| `Mode::All` (default) | one series per process, each labelled `pid` |
| `Mode::Min`, `Mode::Max` | the smallest or the largest value |
| `Mode::Sum` | the sum of the values |
| `Mode::MostRecent` | the value written last; at equal timestamps the earlier file wins |

Every mode also has a `Live` spelling — `LiveAll`, `LiveMin`, and so on — which
aggregates the same way and changes what happens when the process exits:

<!-- nocheck -->
```moonbit
@directory.mark_dead(dir, 7)
```

A live gauge describes a process that is running now, so its file goes when the
supervisor says the process is gone. A counter's file stays: what the process counted
is still true after it exits.

A summary's quantiles are estimated from one process's samples and cannot be added up,
so only its count and sum travel. An info metric and a state set are process-local and
have no cross-process meaning; `write` names them in the result it returns rather than
dropping them quietly.

The files use the layout the official clients' multiprocess mode uses, which is what
makes a directory portable: a worker written here can be read by them, and a directory
they wrote can be read here.

## Exposition

| Function | Result |
|:--|:--|
| `text(families)` | Prometheus text format, version 0.0.4 |
| `openmetrics(families)` | OpenMetrics text format, version 1.0.0, ending in `# EOF` |
| `protobuf(families)` | the protobuf format a scraper reads, a delimited stream of families |
| `negotiate(accept)` | `Format` chosen from an `Accept` header |
| `parse(text, format~)` | the families an exposition describes |

`parse` reads both text formats. The compatibility format is lossy for info and
state sets, which it spells as gauges; OpenMetrics keeps them.

`protobuf` writes the `io.prometheus.client` schema Prometheus scrapes: one family per
message, length-delimited, in the stream a real scraper reads. It reads the same snapshot
the text formats do, so one registry is every format. A counter keeps its base name and
puts its value in the counter field, so Prometheus stores it as `<name>_total`, the series
the text format spells; a histogram keeps its cumulative buckets, sum, and count; a summary
keeps its count, sum, and quantiles; a state set is a gauge per state.

```moonbit
let proto = @moonp8s.protobuf(registry.collect())
let content_type = @moonp8s.protobuf_content_type
```

The `/metrics` handler answers a request that accepts the protobuf format with that
content type, built on moonproto's wire primitives.

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
| `moonbitstack/moonp8s/expo` | The two text formats, the protobuf format, their negotiation, and the parser. |
| `moonbitstack/moonp8s/push` | Push gateway request construction. |
| `moonbitstack/moonp8s/asgi` | The `/metrics` handler and the counting middleware. |
| `moonbitstack/moonp8s/multiproc` | Gauge modes, a worker's file, and the merge. No I/O. |
| `moonbitstack/moonp8s/multiproc/directory` | Writing and reading those files. Native only. |

## Conformance

The OpenMetrics 1.0 specification was read MUST by MUST; the verdict for each of the
hundred is in the delivery notes for this version. Three are not met, and here is what
each would cost:

- **Negative observations.** A histogram or summary that records a negative value
  carries a negative sum, which the specification forbids because a sum is a counter.
  Both official clients accept negative observations and document the consequence, and
  a temperature delta is a real thing to record; refusing them would move the problem
  from the exposition to the caller's arithmetic.
- **Reserved names.** Label names beginning with an underscore belong to the ingestor.
  A registry here accepts them: `__name__` is the ingestor's to set, but a metric named
  `_internal_total` is a naming mistake, not an unreadable exposition.
- **Counts rendered as floats.** Counts and bucket values are integers in the model,
  and written `17.0` rather than `17`, as every official client writes them. The
  format's own grammar accepts both, and a reader must not reject either.

The exposition formats themselves are checked by tooling rather than by reading:
`promtool check metrics` lints the 0.0.4 output clean, a real Prometheus server scrapes
both formats and the query results are compared with the values the workers recorded,
and the multiprocess directory is exchanged with the official Python client in both
directions, with the two renderings compared line for line — the two writers order the
series of one family differently, and neither format gives series an order.

## Migration

`moonbitstack/moonp8s/compat` rebuilds the legacy counter vector, server metric
set, and remote report writer on the registry model, so an existing caller can
move over one import at a time.

## License

Apache-2.0.
