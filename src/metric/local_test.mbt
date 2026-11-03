// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a counter shard accumulates locally and flushes" {
  let counter = @metric.Counter::new()
  let shard = counter.shard()
  shard.inc(by=2.0)
  shard.inc()
  assert_true(shard.get() == 3.0)
  assert_true(counter.get() == 0.0)
  shard.flush()
  assert_true(counter.get() == 3.0)
  assert_true(shard.get() == 0.0)
}

///|
test "a shard refuses a negative step" {
  let shard = @metric.Counter::new().shard()
  let refused = try {
    shard.inc(by=-1.0)
    false
  } catch {
    @metric.Refused(_) => true
  }
  assert_true(refused)
  assert_true(shard.get() == 0.0)
}

///|
test "a registered shard flushes when the registry collects" {
  let shard = @metric.Counter::new().shard()
  shard.inc(by=5.0)
  let registry = try {
    let registry = @metric.Registry::new()
    registry.register("sharded", "Sharded.", shard)
    registry
  } catch {
    @metric.Refused(message) => abort(message)
  }
  let families = registry.collect()
  match families[0].metrics[0].value {
    @metric.Value::Number(v) => assert_true(v == 5.0)
    _ => abort("expected a number")
  }
  assert_true(shard.get() == 0.0)
}
