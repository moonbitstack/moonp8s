// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A worker process and the scrape that reads it, on one command line.
//
//   moon run src/examples/09-multiprocess                  one worker, then its scrape
//   moon run src/examples/09-multiprocess -- --dir D --pid 3
//                                                          this process only, its file in D
//   moon run src/examples/09-multiprocess -- --dir D --print
//                                                          the scrape of every file in D
//   moon run src/examples/09-multiprocess -- --dir D --print --format openmetrics
//                                                          the same scrape, OpenMetrics 1.0
//   moon run src/examples/09-multiprocess -- --dir D --out body.bin --format protobuf
//                                                          the bytes a /metrics would send, as protobuf
//
// A real deployment runs the first form in each worker and the last in the
// process that answers /metrics; nothing is shared but the directory.

///|
/// The work one worker did. The numbers differ per process so the merge has
/// something to add up.
fn registry_for(pid : Int32) -> @metric.Registry raise @metric.Refused {
  let registry = @metric.Registry::new(prefix="p8s", labels=[
    ("service", "checkout"),
  ])
  let orders = registry.counter("orders", "Orders placed, by response code.")
  let accepted = @metric.Family::new(["code"], fn() { @metric.Counter::new() })
  registry.register(
    "orders_by_code", "Orders placed, by response code.", accepted,
  )
  orders.inc(by=(pid * 10).to_double())
  accepted.labels(["200"]).inc(by=pid.to_double())
  accepted.labels(["500"]).inc()
  let latency = registry.histogram(
    "request_seconds",
    "Seconds a request took.",
    buckets=[0.1, 0.5, 1.0, 5.0],
  )
  for i = 0; i < pid; i = i + 1 {
    latency.observe(0.05 + 0.2 * i.to_double())
  }
  let payload = @metric.Summary::new()
  payload.observe(512.0 * pid.to_double())
  registry.register("payload_bytes", "Bytes in a request body.", payload)
  let depth = registry.gauge("queue_depth", "Jobs waiting in this worker.")
  depth.set(pid.to_double() * 3.0)
  registry
}

///|
async fn flush(dir : String, pid : Int32) -> Unit raise @metric.Refused {
  let registry = registry_for(pid)
  let written = @directory.write(dir, pid, registry.collect(), modes=[
    ("p8s_queue_depth", @multiproc.Mode::Sum),
  ])
  println(
    "worker " +
    pid.to_string() +
    ": " +
    written.files.to_string() +
    " files, " +
    written.entries.to_string() +
    " values",
  )
}

///|
// The bytes a /metrics would send for the format, written to a file. The
// protobuf format is binary, the text formats are strings.
async fn to_file(
  dir : String,
  format : String,
  out : String,
) -> Unit raise @metric.Refused {
  let families = @directory.collect(dir)
  if format == "protobuf" {
    let body = @expo.protobuf(families)
    @fs.write_file(out, body) catch {
      _ => raise @metric.Refused("cannot write " + out)
    }
  } else {
    let body = if format == "openmetrics" {
      @expo.openmetrics(families)
    } else {
      @expo.text(families)
    }
    @fs.write_file(out, body) catch {
      _ => raise @metric.Refused("cannot write " + out)
    }
  }
}

///|
// The text a /metrics would send for the format, for the terminal. The
// protobuf format is binary, so it reports its length instead of printing it.
async fn render(dir : String, format : String) -> String raise @metric.Refused {
  let families = @directory.collect(dir)
  if format == "protobuf" {
    @expo.protobuf(families).length().to_string() + " bytes of protobuf"
  } else if format == "openmetrics" {
    @expo.openmetrics(families)
  } else {
    @expo.text(families)
  }
}

///|
async fn main {
  let args = @env.args()
  let mut dir = ""
  let mut pid = 0
  let mut print_only = false
  let mut format = "text"
  let mut out = ""
  let mut write = false
  for i = 1; i < args.length(); i = i + 1 {
    if args[i] == "--dir" && i + 1 < args.length() {
      dir = args[i + 1]
    } else if args[i] == "--pid" && i + 1 < args.length() {
      pid = @string.parse_int(args[i + 1]) catch { _ => 0 }
    } else if args[i] == "--print" {
      print_only = true
    } else if args[i] == "--format" && i + 1 < args.length() {
      format = args[i + 1]
    } else if args[i] == "--out" && i + 1 < args.length() {
      out = args[i + 1]
      write = true
    }
  }
  let scratch = dir == ""
  let place = if scratch {
    @fs.tmpdir(prefix="moonp8s-example-") catch {
      _ => abort("no temporary directory")
    }
  } else {
    dir
  }
  try {
    if write {
      to_file(place, format, out)
    } else if print_only {
      println(render(place, format))
    } else if pid > 0 {
      flush(place, pid)
    } else {
      // Three workers, one after another: each writes its own file, and the
      // scrape below reads all three.
      for worker = 1; worker <= 3; worker = worker + 1 {
        flush(place, worker)
      }
      println("")
      println(render(place, format))
    }
  } catch {
    @metric.Refused(message) => println("refused: " + message)
  }
  if scratch {
    @fs.rmdir(place, recursive=true) catch {
      _ => ()
    }
  }
}
