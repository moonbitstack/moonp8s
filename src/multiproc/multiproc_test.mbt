// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn value_of(point : @metric.Point) -> Double {
  match point.value {
    @metric.Value::Number(v) => v
    _ => abort("not a number")
  }
}

///|
fn refused(f : () -> Unit raise @metric.Refused) -> Bool {
  try {
    f()
    false
  } catch {
    @metric.Refused(_) => true
  }
}

///|
test "a part survives the bytes a worker writes" {
  let part = @multiproc.Part::new("43", @metric.Kind::Counter, None, [
    @multiproc.Entry::new(
      "orders",
      "orders_total",
      [("code", "200"), ("method", "GET")],
      "Orders asked for.",
      3.5,
      timestamp=1700000000.25,
    ),
    @multiproc.Entry::new(
      "orders",
      "orders_total",
      [],
      "Orders asked for.",
      1.0,
    ),
  ])
  let back = @multiproc.Part::decode(part.file_name(), part.encode()) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(back.pid, "43")
  assert_eq(back.kind.code(), "counter")
  assert_true(back.mode is None)
  assert_eq(back.entries.length(), 2)
  assert_eq(back.entries[0].metric, "orders")
  assert_eq(back.entries[0].sample, "orders_total")
  assert_eq(back.entries[0].help, "Orders asked for.")
  assert_true(back.entries[0].value == 3.5)
  assert_true(back.entries[0].timestamp == 1700000000.25)
  assert_eq(back.entries[0].labels.length(), 2)
}

///|
test "a record pads by the bytes of its key, not by its characters" {
  // A key of multi-byte characters is longer on disk than it looks; padding to
  // an eight-byte boundary has to count the bytes, or the value that follows is
  // read from the wrong offset.
  let part = @multiproc.Part::new(
    "5",
    @metric.Kind::Gauge,
    Some(@multiproc.Mode::All),
    [
      @multiproc.Entry::new(
        "queue",
        "queue_depth",
        [("名字", "队列一"), ("note", "a\"b\\c🙂")],
        "深度",
        7.0,
        timestamp=1700000001.5,
      ),
    ],
  )
  let back = @multiproc.Part::decode(part.file_name(), part.encode()) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(back.entries.length(), 1)
  assert_eq(back.entries[0].help, "深度")
  assert_true(back.entries[0].value == 7.0)
  assert_true(back.entries[0].timestamp == 1700000001.5)
  assert_eq(back.entries[0].labels.length(), 2)
}

///|
test "a gauge file carries its mode in its name" {
  let part = @multiproc.Part::new(
    "9",
    @metric.Kind::Gauge,
    Some(@multiproc.Mode::LiveSum),
    [],
  )
  assert_eq(part.file_name(), "gauge_livesum_9.db")
  let (pid, kind, mode) = @multiproc.Part::name_of("gauge_livesum_9.db") catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(pid, "9")
  assert_eq(kind.code(), "gauge")
  assert_eq(mode.unwrap().code(), "livesum")
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@multiproc.Part::name_of("gauge_9.db"))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@multiproc.Part::name_of("counter_9.txt"))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@multiproc.Part::name_of("histogram_9_extra.db"))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@multiproc.Part::name_of("gauge_sideways_9.db"))
    }),
  )
}

///|
test "an empty file holds nothing, and a torn one is refused" {
  let empty = @multiproc.Part::decode(
    "counter_1.db",
    Bytes::from_array([
      b'\x08', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    ]),
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(empty.entries.length(), 0)
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(
        @multiproc.Part::decode(
          "counter_1.db",
          Bytes::from_array([b'\x40', b'\x00', b'\x00', b'\x00']),
        ),
      )
    }),
  )
}

///|
test "counters from three processes add up" {
  let parts = [
    @multiproc.Part::new("1", @metric.Kind::Counter, None, [
      @multiproc.Entry::new(
        "orders",
        "orders_total",
        [("code", "200")],
        "Orders.",
        2.0,
      ),
    ]),
    @multiproc.Part::new("2", @metric.Kind::Counter, None, [
      @multiproc.Entry::new(
        "orders",
        "orders_total",
        [("code", "200")],
        "Orders.",
        3.0,
      ),
    ]),
    @multiproc.Part::new("3", @metric.Kind::Counter, None, [
      @multiproc.Entry::new(
        "orders",
        "orders_total",
        [("code", "500")],
        "Orders.",
        1.0,
      ),
    ]),
  ]
  let families = @multiproc.merge(parts) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(families.length(), 1)
  assert_eq(families[0].kind.code(), "counter")
  assert_eq(families[0].metrics.length(), 2)
  assert_true(value_of(families[0].metrics[0]) == 5.0)
  assert_true(value_of(families[0].metrics[1]) == 1.0)
}

///|
fn gauge_parts(
  values : Array[(String, Double, Double)],
  mode : @multiproc.Mode,
) -> Array[@multiproc.Part] {
  let parts : Array[@multiproc.Part] = []
  for pair in values {
    parts.push(
      @multiproc.Part::new(pair.0, @metric.Kind::Gauge, Some(mode), [
        @multiproc.Entry::new(
          "queue",
          "queue",
          [("worker", "a")],
          "Queued.",
          pair.1,
          timestamp=pair.2,
        ),
      ]),
    )
  }
  parts
}

///|
test "a gauge keeps the processes apart under all, and collapses them under sum" {
  let separate = gauge_parts(
    [("1", 2.0, 0.0), ("2", 3.0, 0.0)],
    @multiproc.Mode::All,
  )
  let families = @multiproc.merge(separate) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(families[0].metrics.length(), 2)
  assert_eq(families[0].metrics[0].labels.length(), 2)
  assert_eq(families[0].metrics[0].labels[0].0, "pid")
  let added = @multiproc.merge(
    gauge_parts([("1", 2.0, 0.0), ("2", 3.0, 0.0)], @multiproc.Mode::Sum),
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(added[0].metrics.length(), 1)
  assert_true(value_of(added[0].metrics[0]) == 5.0)
}

///|
test "min and max take the smallest and the largest of the processes" {
  let parts = gauge_parts(
    [("1", 2.0, 0.0), ("2", 7.0, 0.0)],
    @multiproc.Mode::Max,
  )
  let families = @multiproc.merge(parts) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_true(value_of(families[0].metrics[0]) == 7.0)
  let smallest = @multiproc.merge(
    gauge_parts([("1", 2.0, 0.0), ("2", 7.0, 0.0)], @multiproc.Mode::Min),
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_true(value_of(smallest[0].metrics[0]) == 2.0)
}

///|
test "mostrecent keeps the value set last, and the earlier file wins a tie" {
  let newer = @multiproc.merge(
    gauge_parts(
      [("1", 2.0, 100.0), ("2", 7.0, 200.0)],
      @multiproc.Mode::MostRecent,
    ),
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_true(value_of(newer[0].metrics[0]) == 7.0)
  let tie = @multiproc.merge(
    gauge_parts(
      [("1", 2.0, 100.0), ("2", 7.0, 100.0)],
      @multiproc.Mode::MostRecent,
    ),
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_true(value_of(tie[0].metrics[0]) == 2.0)
}

///|
test "a histogram's per-process buckets are added up and made cumulative" {
  let bucket = fn(_pid : String, le : String, v : Double) {
    @multiproc.Entry::new(
      "latency",
      "latency_bucket",
      [("le", le)],
      "Latency.",
      v,
    )
  }
  let sum = fn(_pid : String, v : Double) {
    @multiproc.Entry::new("latency", "latency_sum", [], "Latency.", v)
  }
  let parts = [
    @multiproc.Part::new("1", @metric.Kind::Histogram, None, [
      bucket("1", "0.1", 2.0),
      bucket("1", "1", 1.0),
      bucket("1", "+Inf", 1.0),
      sum("1", 2.5),
    ]),
    @multiproc.Part::new("2", @metric.Kind::Histogram, None, [
      bucket("2", "0.1", 1.0),
      bucket("2", "+Inf", 3.0),
      sum("2", 4.5),
    ]),
  ]
  let families = @multiproc.merge(parts) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(families[0].metrics.length(), 1)
  match families[0].metrics[0].value {
    @metric.Value::Buckets(buckets~, sum~, count~) => {
      assert_eq(buckets.length(), 2)
      assert_true(buckets[0].0 == 0.1)
      assert_eq(buckets[0].1, 3L)
      assert_eq(buckets[1].1, 4L)
      assert_true(sum == 7.0)
      assert_eq(count, 8L)
    }
    _ => abort("not buckets")
  }
}

///|
test "a summary adds count and sum across processes, without quantiles" {
  let parts = [
    @multiproc.Part::new("1", @metric.Kind::Summary, None, [
      @multiproc.Entry::new("size", "size_count", [], "Size.", 3.0),
      @multiproc.Entry::new("size", "size_sum", [], "Size.", 12.0),
    ]),
    @multiproc.Part::new("2", @metric.Kind::Summary, None, [
      @multiproc.Entry::new("size", "size_count", [], "Size.", 2.0),
      @multiproc.Entry::new("size", "size_sum", [], "Size.", 8.0),
    ]),
  ]
  let families = @multiproc.merge(parts) catch {
    @metric.Refused(message) => abort(message)
  }
  match families[0].metrics[0].value {
    @metric.Value::Quantiles(quantiles~, sum~, count~) => {
      assert_eq(quantiles.length(), 0)
      assert_eq(count, 5L)
      assert_true(sum == 20.0)
    }
    _ => abort("not quantiles")
  }
}

///|
test "a name that is two kinds at once is refused" {
  let parts = [
    @multiproc.Part::new("1", @metric.Kind::Counter, None, [
      @multiproc.Entry::new("orders", "orders_total", [], "Orders.", 1.0),
    ]),
    @multiproc.Part::new("2", @metric.Kind::Histogram, None, [
      @multiproc.Entry::new(
        "orders",
        "orders_bucket",
        [("le", "1")],
        "Orders.",
        1.0,
      ),
    ]),
  ]
  assert_true(
    refused(fn() raise @metric.Refused { ignore(@multiproc.merge(parts)) }),
  )
}

///|
test "one gauge written under two modes is refused" {
  let parts = [
    @multiproc.Part::new("1", @metric.Kind::Gauge, Some(@multiproc.Mode::Sum), [
      @multiproc.Entry::new("queue", "queue", [], "Queue.", 1.0),
    ]),
    @multiproc.Part::new("2", @metric.Kind::Gauge, Some(@multiproc.Mode::Max), [
      @multiproc.Entry::new("queue", "queue", [], "Queue.", 2.0),
    ]),
  ]
  assert_true(
    refused(fn() raise @metric.Refused { ignore(@multiproc.merge(parts)) }),
  )
}

///|
test "families and series keep the order they were first seen in" {
  let parts = [
    @multiproc.Part::new("1", @metric.Kind::Counter, None, [
      @multiproc.Entry::new("b", "b_total", [("x", "1")], "B.", 1.0),
      @multiproc.Entry::new("a", "a_total", [("y", "2")], "A.", 1.0),
    ]),
    @multiproc.Part::new("2", @metric.Kind::Counter, None, [
      @multiproc.Entry::new("b", "b_total", [("x", "2")], "B.", 1.0),
      @multiproc.Entry::new("b", "b_total", [("x", "1")], "B.", 1.0),
    ]),
  ]
  let families = @multiproc.merge(parts) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(families.map(f => f.name), ["b", "a"])
  assert_eq(families[0].metrics.length(), 2)
  assert_eq(families[0].metrics[0].labels[0].1, "1")
  assert_eq(families[0].metrics[1].labels[0].1, "2")
}

///|
test "only the live modes forget a process that exits" {
  let live = [
    @multiproc.Mode::LiveAll,
    @multiproc.Mode::LiveMin,
    @multiproc.Mode::LiveMax,
    @multiproc.Mode::LiveSum,
    @multiproc.Mode::LiveMostRecent,
  ]
  let kept = [
    @multiproc.Mode::All,
    @multiproc.Mode::Min,
    @multiproc.Mode::Max,
    @multiproc.Mode::Sum,
    @multiproc.Mode::MostRecent,
  ]
  for mode in live {
    assert_true(mode.is_live())
  }
  for mode in kept {
    assert_true(!mode.is_live())
  }
  // The same split the file names carry, so a mode that round-trips through its
  // name keeps its behaviour.
  for mode in live {
    let back = @multiproc.Mode::of(mode.code()) catch {
      @metric.Refused(message) => abort(message)
    }
    assert_true(back.is_live())
  }
}
