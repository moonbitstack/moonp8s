// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

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
fn counter_family() -> @metric.Family[@metric.Counter] {
  @metric.Family::new(["method"], fn() { @metric.Counter::new() }) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
}

///|
test "counter only increases" {
  let c = @metric.Counter::new()
  c.inc()
  c.inc(by=2.5)
  assert_true(c.get() == 3.5)
  assert_true(refused(fn() raise @metric.Refused { c.inc(by=-1.0) }))
  assert_true(c.get() == 3.5)
}

///|
test "a counter's name may say `_total`, and it comes out once, as client_python writes it" {
  let registry = @metric.Registry::new()
  let said = registry.counter("orders_total", "Said.")
  said.inc()
  let plain = registry.counter("visits", "Plain.")
  plain.inc()
  let names = registry.collect().map(family => family.name)
  assert_eq(names, ["orders", "visits"])
  // The family owns the name, so the two spellings are one metric.
  let twice = try {
    ignore(registry.counter("orders", "Again."))
    false
  } catch {
    @metric.Refused(_) => true
  }
  assert_true(twice)
  // Only a counter's samples get the suffix, so nothing else loses it.
  let gauge = registry.gauge("left_total", "A gauge.")
  gauge.set(1.0)
  assert_true(
    registry.collect().map(family => family.name).contains("left_total"),
  )
}

///|
test "an info or a state set cannot have a unit" {
  let registry = @metric.Registry::new()
  let info = @metric.Info::new([("version", "1")]) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  let refused = try {
    registry.register("build", "Build.", info, unit="seconds")
    false
  } catch {
    @metric.Refused(_) => true
  }
  assert_true(refused)
}

///|
test "gauge moves both ways and dates a sample" {
  let g = @metric.Gauge::new(initial=10.0)
  g.inc(by=2.0)
  g.dec(by=5.0)
  assert_true(g.get() == 7.0)
  g.set(3.5, timestamp=1700000000.0)
  let points = g.points()
  assert_true(points.length() == 1)
  match points[0].timestamp {
    Some(t) => assert_true(t == 1700000000.0)
    None => abort("expected a timestamp")
  }
}

///|
test "histogram buckets are cumulative on snapshot" {
  let h = @metric.Histogram::new(buckets=[1.0, 2.0, 4.0]) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  h.observe(0.5)
  h.observe(1.5)
  h.observe(3.0)
  h.observe(9.0)
  let point = h.snapshot()
  match point.value {
    @metric.Value::Buckets(buckets~, sum~, count~) => {
      assert_true(buckets.length() == 3)
      assert_true(buckets[0].0 == 1.0 && buckets[0].1 == 1L)
      assert_true(buckets[1].0 == 2.0 && buckets[1].1 == 2L)
      assert_true(buckets[2].0 == 4.0 && buckets[2].1 == 3L)
      assert_true(sum == 14.0)
      assert_true(count == 4L)
    }
    _ => abort("expected buckets")
  }
}

///|
test "histogram refuses unordered bounds" {
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.Histogram::new(buckets=[2.0, 1.0]))
    }),
  )
}

///|
test "linear and exponential helpers" {
  let l = @metric.linear(1.0, 2.0, 3) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  assert_true(l.length() == 3)
  assert_true(l[0] == 1.0 && l[1] == 3.0 && l[2] == 5.0)
  let e = @metric.exponential(1.0, 2.0, 4) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  assert_true(e.length() == 4)
  assert_true(e[0] == 1.0 && e[1] == 2.0 && e[2] == 4.0 && e[3] == 8.0)
}

///|
fn near(got : Double, want : Double) -> Bool {
  ((got - want) / want).abs() < 1.0e-9
}

///|
test "exponential_range keeps both ends and grows by one factor between them" {
  let range = @metric.exponential_range(1.0, 1000.0, 4) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  assert_eq(range.length(), 4)
  assert_true(range[0] == 1.0)
  assert_true(near(range[1], 10.0))
  assert_true(near(range[2], 100.0))
  assert_true(near(range[3], 1000.0))
  // The bounds the helper returns are a histogram's bounds as they are.
  let h = @metric.Histogram::new(buckets=range) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  h.observe(5.0)
  assert_true(h.total() == 1L)
}

///|
test "exponential_range refuses a span that is not one" {
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.exponential_range(1.0, 10.0, 1))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.exponential_range(1.0, 10.0, 0))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.exponential_range(0.0, 10.0, 4))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.exponential_range(-1.0, 10.0, 4))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.exponential_range(10.0, 10.0, 4))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.exponential_range(10.0, 1.0, 4))
    }),
  )
}

///|
test "summary counts and sums without quantiles" {
  let s = @metric.Summary::new()
  s.observe(2.0)
  s.observe(4.0)
  let point = s.snapshot()
  match point.value {
    @metric.Value::Quantiles(quantiles~, sum~, count~) => {
      assert_true(quantiles.length() == 0)
      assert_true(sum == 6.0)
      assert_true(count == 2L)
    }
    _ => abort("expected quantiles")
  }
}

///|
test "summary estimates a quantile within its error" {
  let s = @metric.Summary::new(quantiles=[(0.5, 0.05), (0.9, 0.05)]) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  for i = 1; i <= 100; i = i + 1 {
    s.observe(i.to_double())
  }
  let point = s.snapshot()
  match point.value {
    @metric.Value::Quantiles(quantiles~, ..) => {
      assert_true(quantiles.length() == 2)
      let median = quantiles[0].1
      assert_true(median >= 40.0 && median <= 60.0)
    }
    _ => abort("expected quantiles")
  }
}

///|
test "family creates one child per label combination" {
  let family = counter_family()
  let a = family.labels(["GET"])
  let b = family.labels(["GET"])
  let c = family.labels(["POST"])
  a.inc()
  assert_true(b.get() == 1.0)
  assert_true(c.get() == 0.0)
  assert_true(family.size() == 2)
}

///|
test "family refuses a wrong label count" {
  let family = counter_family()
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(family.labels(["GET", "extra"]))
    }),
  )
}

///|
test "state set exclusive keeps one state true" {
  let set = @metric.StateSet::exclusive(["a", "b", "c"])
  assert_true(set.get("a"))
  assert_true(!set.get("b"))
  set.set("b")
  assert_true(!set.get("a"))
  assert_true(set.get("b"))
  assert_true(!set.get("c"))
}

///|
test "registry collects in registration order" {
  let registry = @metric.Registry::new()
  let requests = registry.counter("requests", "Requests.") catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  requests.inc()
  let gauge = registry.gauge("temperature", "Temperature.") catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  gauge.set(3.0)
  let families = registry.collect()
  assert_true(families.length() == 2)
  assert_true(families[0].name == "requests")
  match families[0].kind {
    @metric.Kind::Counter => ()
    _ => abort("expected counter")
  }
  assert_true(families[1].name == "temperature")
  match families[1].kind {
    @metric.Kind::Gauge => ()
    _ => abort("expected gauge")
  }
}

///|
test "registry refuses duplicate names and invalid names" {
  let registry = @metric.Registry::new()
  ignore(
    registry.counter("requests", "Requests.") catch {
      @metric.Refused(_) => abort("unexpected refusal")
    },
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(registry.counter("requests", "Again."))
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(registry.counter("1bad", "Bad."))
    }),
  )
}

///|
test "registry applies a prefix and constant labels" {
  let registry = @metric.Registry::new(prefix="app", labels=[("region", "eu")]) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  let counter = registry.counter("requests", "Requests.") catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  counter.inc()
  let families = registry.collect()
  assert_true(families[0].name == "app_requests")
  assert_true(families[0].metrics[0].labels.length() == 1)
  assert_true(families[0].metrics[0].labels[0].0 == "region")
  assert_true(families[0].metrics[0].labels[0].1 == "eu")
}

///|
test "sub registry extends the prefix and labels" {
  let registry = @metric.Registry::new(prefix="app") catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  let sub = registry.sub(prefix="http", labels=[("region", "eu")]) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  let counter = sub.counter("requests", "Requests.") catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  counter.inc()
  let families = sub.collect()
  assert_true(families[0].name == "app_http_requests")
  assert_true(families[0].metrics[0].labels[0].1 == "eu")
}

///|
test "names are validated by the OpenMetrics character rules" {
  assert_true(@metric.is_valid_metric_name("http_requests"))
  assert_true(!@metric.is_valid_metric_name("1http"))
  assert_true(@metric.is_valid_label_name("_method"))
  assert_true(!@metric.is_valid_label_name("1method"))
  assert_true(@metric.is_valid_unit("seconds"))
  assert_true(!@metric.is_valid_unit("1seconds"))
}

///|
test "a counter resets to zero" {
  let counter = @metric.Counter::new(created=1700000000.0)
  counter.inc(by=3.0)
  counter.reset(created=1700000100.0)
  assert_true(counter.get() == 0.0)
  let point = counter.points()[0]
  match point.created {
    Some(c) => assert_true(c == 1700000100.0)
    None => abort("expected a creation time")
  }
}

///|
test "a gauge can take its value from a function" {
  let gauge = @metric.Gauge::new()
  let mut current = 1.0
  gauge.set_function(fn() { current })
  assert_true(gauge.get() == 1.0)
  current = 4.0
  assert_true(gauge.get() == 4.0)
  gauge.set(9.0)
  assert_true(gauge.get() == 4.0)
  gauge.inc(by=2.0)
  assert_true(gauge.get() == 4.0)
}

///|
test "a scrape stamps the samples that carry no time of their own" {
  let registry = @metric.Registry::new() catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  let gauge = @metric.Gauge::new()
  let histogram = @metric.Histogram::new() catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  registry.register("g", "G.", gauge) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  registry.register("h", "H.", histogram) catch {
    @metric.Refused(_) => abort("unexpected refusal")
  }
  gauge.set(2.0)
  histogram.observe(0.02)
  let stamped = registry.collect(at=1700000000.0)
  for family in stamped {
    for point in family.metrics {
      match point.timestamp {
        Some(at) => assert_true(at == 1700000000.0)
        None => abort("a scrape left a sample unstamped")
      }
    }
  }
  // A point that already knows its time keeps it: a backfilled sample is not the
  // scrape's to date.
  gauge.set(3.0, timestamp=1699999999.0)
  let backfilled = registry.collect(at=1700000000.0)
  match backfilled[0].metrics[0].timestamp {
    Some(at) => assert_true(at == 1699999999.0)
    None => abort("a dated sample lost its date")
  }
}

///|
test "a counter refuses NaN, which would stop it being a total" {
  let counter = @metric.Counter::new()
  let nan = 0.0 / 0.0
  assert_true(refused(fn() raise @metric.Refused { counter.inc(by=nan) }))
  assert_true(counter.get() == 0.0)
}

///|
test "a counter reset without a new creation time forgets the old one" {
  let counter = @metric.Counter::new(created=1700000000.0)
  counter.inc(by=2.0)
  counter.reset()
  assert_true(counter.get() == 0.0)
  assert_true(counter.points()[0].created is None)
}

///|
test "a histogram refuses a bound it cannot carry a sum for" {
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.Histogram::new(buckets=[-1.0, 1.0]))
    }),
  )
}

///|
test "a family refuses a label name the sample already spends" {
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(
        @metric.Family::new(["le"], fn() raise @metric.Refused {
          @metric.Histogram::new()
        }),
      )
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(
        @metric.Family::new(["quantile"], fn() raise @metric.Refused {
          @metric.Summary::new()
        }),
      )
    }),
  )
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(@metric.Family::new(["a", "a"], fn() { @metric.Counter::new() }))
    }),
  )
  // The same name is fine for a kind that does not spend it.
  ignore(@metric.Family::new(["le"], fn() { @metric.Counter::new() })) catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
test "a name that would collide with another family's sample is refused" {
  let registry = @metric.Registry::new()
  let orders = registry.counter("orders", "Orders.")
  orders.inc()
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(registry.gauge("orders_total", "Not a counter."))
    }),
  )
  let latency = registry.histogram("latency", "Latency.")
  latency.observe(0.1)
  assert_true(
    refused(fn() raise @metric.Refused {
      ignore(registry.gauge("latency_count", "Counts, but a gauge."))
    }),
  )
  // A name that only looks similar is fine: `latency_seconds` is nobody's sample.
  ignore(registry.gauge("latency_seconds", "Seconds.")) catch {
    @metric.Refused(message) => abort(message)
  }
}

///|
test "a summary with no observations answers NaN, not zero" {
  let summary = @metric.Summary::new(quantiles=[(0.5, 0.01)])
  match summary.snapshot().value {
    @metric.Value::Quantiles(quantiles~, ..) => {
      assert_eq(quantiles.length(), 1)
      assert_true(quantiles[0].1 != quantiles[0].1)
    }
    _ => abort("not quantiles")
  }
  summary.observe(4.0)
  match summary.snapshot().value {
    @metric.Value::Quantiles(quantiles~, ..) =>
      assert_true(quantiles[0].1 == 4.0)
    _ => abort("not quantiles")
  }
}
