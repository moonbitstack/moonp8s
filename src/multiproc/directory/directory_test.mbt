// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
async fn scratch() -> String {
  @fs.tmpdir(prefix="moonp8s-")
}

///|
async fn discard(dir : String) -> Unit {
  @fs.rmdir(dir, recursive=true)
}

///|
async fn flush(
  dir : String,
  pid : Int32,
  families : Array[@metric.MetricFamily],
  modes? : Array[(String, @multiproc.Mode)],
) -> @directory.Written {
  @directory.write(dir, pid, families, modes?) catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
async fn scrape(dir : String, at? : Double) -> Array[@metric.MetricFamily] {
  @directory.collect(dir, at?) catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
async fn files_of(dir : String) -> Array[String] {
  let names = @fs.readdir(dir) catch { _ => abort("no directory") }
  names.sort_by(fn(a, b) { String::lexical_compare(a, b) })
  names
}

///|
fn findings(
  families : Array[@metric.MetricFamily],
  name : String,
) -> @metric.MetricFamily {
  for family in families {
    if family.name == name {
      return family
    }
  }
  abort("no family named " + name)
}

///|
fn number_of(point : @metric.Point) -> Double {
  match point.value {
    @metric.Value::Number(v) => v
    _ => abort("not a number")
  }
}

///|
fn worker_registry() -> @metric.Registry {
  try {
    let registry = @metric.Registry::new()
    let hits = registry.counter("hits", "Hits.")
    hits.inc(by=2.0)
    let depth = registry.gauge("depth", "Depth.")
    depth.set(4.0)
    let latency = registry.histogram("latency", "Latency.", buckets=[0.5, 1.0])
    latency.observe(0.25)
    latency.observe(2.0)
    let size = @metric.Summary::new()
    size.observe(3.0)
    size.observe(5.0)
    registry.register("size", "Size.", size)
    registry
  } catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
async test "a process's values survive a flush and a scrape" {
  let dir = scratch()
  let written = flush(dir, 7, worker_registry().collect())
  assert_eq(written.files, 4)
  assert_eq(written.skipped.length(), 0)
  let families = scrape(dir)
  assert_true(number_of(findings(families, "hits").metrics[0]) == 2.0)
  assert_true(number_of(findings(families, "depth").metrics[0]) == 4.0)
  match findings(families, "latency").metrics[0].value {
    @metric.Value::Buckets(buckets~, sum~, count~) => {
      assert_eq(buckets.length(), 2)
      assert_eq(buckets[0].1, 1L)
      assert_eq(buckets[1].1, 1L)
      assert_eq(count, 2L)
      assert_true(sum == 2.25)
    }
    _ => abort("not buckets")
  }
  match findings(families, "size").metrics[0].value {
    @metric.Value::Quantiles(quantiles=_, sum~, count~) => {
      assert_eq(count, 2L)
      assert_true(sum == 8.0)
    }
    _ => abort("not quantiles")
  }
  discard(dir)
}

///|
async test "flushing twice is flushing once" {
  let dir = scratch()
  let registry = worker_registry()
  let first = flush(dir, 3, registry.collect())
  let once = @expo.text(scrape(dir))
  let second = flush(dir, 3, registry.collect())
  let twice = @expo.text(scrape(dir))
  assert_eq(first.entries, second.entries)
  assert_eq(once, twice)
  discard(dir)
}

///|
async test "a process's file is replaced, not added to" {
  let dir = scratch()
  let registry = @metric.Registry::new()
  let hits = registry.counter("hits", "Hits.")
  hits.inc()
  let _ = flush(dir, 5, registry.collect())
  hits.inc()
  let _ = flush(dir, 5, registry.collect())
  let families = scrape(dir)
  assert_true(number_of(findings(families, "hits").metrics[0]) == 2.0)
  discard(dir)
}

///|
async test "a gauge that changes its mode loses the file of the old mode" {
  let dir = scratch()
  let registry = @metric.Registry::new()
  let depth = registry.gauge("depth", "Depth.")
  depth.set(4.0)
  let _ = flush(dir, 2, registry.collect(), modes=[
    ("depth", @multiproc.Mode::Sum),
  ])
  assert_eq(files_of(dir), ["gauge_sum_2.db"])
  let _ = flush(dir, 2, registry.collect(), modes=[
    ("depth", @multiproc.Mode::Max),
  ])
  assert_eq(files_of(dir), ["gauge_max_2.db"])
  discard(dir)
}

///|
async test "an info metric and a state set are reported, not written" {
  let dir = scratch()
  let registry = @metric.Registry::new()
  let build = @metric.Info::new([("version", "1.2.3")]) catch {
    @metric.Refused(message) => abort(message)
  }
  registry.register("build", "Build.", build)
  let state = @metric.StateSet::new(["cold", "warm"])
  registry.register("mode", "Mode.", state)
  let hits = registry.counter("hits", "Hits.")
  hits.inc()
  let written = flush(dir, 1, registry.collect())
  assert_eq(written.skipped, ["build", "mode"])
  assert_eq(written.files, 1)
  discard(dir)
}

///|
async test "mark_dead forgets a live gauge and keeps everything else" {
  let dir = scratch()
  let registry = @metric.Registry::new()
  let live = registry.gauge("live_depth", "Live depth.")
  live.set(1.0)
  let kept = registry.gauge("kept_depth", "Kept depth.")
  kept.set(2.0)
  let hits = registry.counter("hits", "Hits.")
  hits.inc()
  let _ = flush(dir, 8, registry.collect(), modes=[
    ("live_depth", @multiproc.Mode::LiveSum),
  ])
  let removed = @directory.mark_dead(dir, 8) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(removed, 1)
  assert_eq(files_of(dir), ["counter_8.db", "gauge_all_8.db"])
  discard(dir)
}

///|
async test "another process's files are left alone" {
  let dir = scratch()
  let registry = @metric.Registry::new()
  let hits = registry.counter("hits", "Hits.")
  hits.inc()
  let _ = flush(dir, 1, registry.collect())
  let _ = flush(dir, 2, registry.collect())
  let removed = @directory.mark_dead(dir, 2) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(removed, 0)
  assert_eq(files_of(dir), ["counter_1.db", "counter_2.db"])
  discard(dir)
}

///|
async test "a scrape stamps a sample that has no time of its own" {
  let dir = scratch()
  let registry = @metric.Registry::new()
  let hits = registry.counter("hits", "Hits.")
  hits.inc()
  let _ = flush(dir, 1, registry.collect())
  let families = scrape(dir, at=1700000000.0)
  assert_true(
    findings(families, "hits").metrics[0].timestamp.unwrap() == 1700000000.0,
  )
  discard(dir)
}
