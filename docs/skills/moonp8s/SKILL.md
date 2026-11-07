---
name: moonp8s
description: Prometheus metrics for MoonBit — counters, gauges, histograms, summaries, a registry, the 0.0.4 and OpenMetrics 1.0 text formats, the protobuf format a scraper reads, a parser for them, push gateway requests, an ASGI handler, and the aggregation of several worker processes. Use when a MoonBit service has to expose /metrics, count requests, record latency, or read an exposition another process wrote.
---

# moonp8s

Metrics are recorded in this process and written as text; nothing here reads a clock or
opens a socket, so the caller schedules the scrape and hands in the time.

```bash
moon add moonbitstack/moonp8s
```

One package per job: `metric` (the model), `expo` (the two text formats, the protobuf
format, and the parser), `multiproc` and `multiproc/directory` (several processes),
`push` (gateway requests), `asgi` (the `/metrics` handler). `moonbitstack/moonp8s`
re-exports the common types.

## Record a metric and write it out

moon.pkg of the package that records:

```
import {
  "moonbitstack/moonp8s",
  "moonbitstack/moonp8s/metric",
}
```

```moonbit
fn main raise {
  let registry = @moonp8s.Registry::new(prefix="app", labels=[("region", "eu")])
  let requests = registry.counter("http_requests", "HTTP requests served.")
  requests.inc()
  let latency = registry.histogram(
    "request_seconds",
    "Seconds a request took.",
    buckets=[0.1, 0.5, 1.0, 5.0],
  )
  latency.observe(0.21)
  println(@moonp8s.text(registry.collect()))
}
```

`text` writes the compatibility format 0.0.4; `openmetrics` writes OpenMetrics 1.0 and
ends with `# EOF`. `Format::content_type` gives the header that matches the body, and
`negotiate(accept)` picks the format from a request's `Accept`.

`protobuf(families)` writes the same snapshot as the protobuf a scraper reads: the
`io.prometheus.client` families, length-delimited, with `protobuf_content_type` the
header. It is built on moonproto's wire primitives, so a counter's value goes in the
counter field and Prometheus stores it as `<name>_total`, the series `text` spells.

```moonbit
fn proto(registry : @moonp8s.Registry) -> Bytes {
  @moonp8s.protobuf(registry.collect())
}
```

A counter is a total: `inc` refuses a negative step and NaN. A gauge may go down. A
histogram answers with cumulative buckets, so `observe` once per event and let the
scrape do the arithmetic.

## One metric, many series

Label names are fixed when the family is built; `labels` gets or creates the child for
one combination of values and refuses the wrong number of them.

```moonbit
fn by_route(registry : @moonp8s.Registry) -> Unit raise {
  let served = @moonp8s.Family::new(["method", "code"], fn() {
    @moonp8s.Counter::new()
  })
  registry.register("served", "Requests served, by route.", served)
  served.labels(["GET", "200"]).inc()
  served.labels(["POST", "500"]).inc(by=2.0)
}
```

## Several worker processes

Each process writes what it has counted to its own file in one directory, and the
process that answers `/metrics` reads the directory. A gauge needs a mode, because
three workers' queue depths are three answers to one question.

```
import {
  "moonbitstack/moonp8s/multiproc",
  "moonbitstack/moonp8s/multiproc/directory",
}
```

```mbt native
async fn flush(
  dir : String,
  pid : Int,
  families : Array[@moonp8s.MetricFamily],
) -> Unit raise {
  let written = @directory.write(
    dir,
    pid,
    families,
    modes=[("queue_depth", @multiproc.Mode::Sum)],
  )
  println(written.files.to_string() + " files")
}
```

`mode` is one of `All` (the default: one series per process, labelled `pid`), `Min`,
`Max`, `Sum`, `MostRecent`, or a `Live` spelling of any of them. At a scrape the live
spellings aggregate the same way; afterwards, `@directory.mark_dead(dir, pid)` deletes
the live gauges of a process that has exited and leaves the counters, whose totals are
still true.

```mbt native
async fn scrape(dir : String) -> Unit raise {
  println(@moonp8s.text(@directory.collect(dir)))
}
```

A flush replaces the process's files with its totals since the process started, so
flushing twice is flushing once. The files are the layout the official Prometheus
clients' multiprocess mode uses, so a directory written here can be read by another
client and the other way round.

## Serve it

```moonbit
import {
  "moonbitstack/moonp8s",
  "moonbitstack/moonp8s/metric",
  "moonbitstack/moonp8s/asgi",
}
```

```moonbit
fn wire(registry : @moonp8s.Registry) -> Unit {
  let metrics = @asgi.app(registry)
  ignore(metrics)
}
```

`app` answers `GET /metrics` with the negotiated format. `middleware` counts requests
and observes their duration; it takes the clock, so a test can drive time.

## Rules that bite

- **No clock, no socket.** `collect(at=...)` stamps samples with the moment you pass;
  `Gauge::set` takes a timestamp when a sample is worth dating. Nothing is read for you.
- **A name is spent once.** A second registration of the same name is refused, and so is
  a name that would collide with another family's sample — a gauge called `orders_total`
  next to a counter called `orders`.
- **Refused is the only error.** `Refused(message)`; pattern-match it or print it.
- **Multi-process is native only.** The merge is portable, but reading and writing a
  worker's file needs a file system.
- **Summary quantiles do not travel across processes**, and an info metric or a state
  set is process-local; `write` returns the names it left out instead of hiding them.
