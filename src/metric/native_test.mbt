///|
/// The native side of a histogram's snapshot.
fn sparse_of(h : @metric.Histogram) -> @metric.Sparse {
  guard h.snapshot().value is Native(sparse~, ..) else {
    abort("not a native histogram")
  }
  sparse
}

///|
/// A clock the test moves by hand.
fn clock(at : Ref[Double]) -> () -> Double {
  () => at.val
}

///|
/// Factor 1.1 is schema 3: 1, 2 and 4 fall in buckets 0, 8 and 16.
fn limited(
  max_buckets~ : Int32,
  min_reset? : Double,
  max_zero_threshold? : Double,
  now~ : Ref[Double],
) -> @metric.Histogram raise {
  @metric.Histogram::new(
    native=@metric.Native::new(
      max_buckets~,
      min_reset=min_reset.unwrap_or(0.0),
      max_zero_threshold=max_zero_threshold.unwrap_or(0.0),
    ),
    clock=clock(now),
  )
}

///|
test "native buckets follow the factor's schema" {
  let h = @metric.Histogram::new(native=@metric.native)
  h.observe(1.0)
  h.observe(2.0)
  h.observe(-4.0)
  h.observe(0.0)
  let sparse = sparse_of(h)
  assert_eq(sparse.schema, 3)
  assert_eq(sparse.positive, [(0, 1L), (8, 1L)])
  assert_eq(sparse.negative, [(16, 1L)])
  assert_eq(sparse.zero_count, 1L)
}

///|
test "only native buckets when no classic ones are asked for" {
  let h = @metric.Histogram::new(native=@metric.native)
  h.observe(0.3)
  guard h.snapshot().value is Native(buckets~, count~, ..) else {
    fail("native")
  }
  assert_eq(buckets, [])
  assert_eq(count, 1L)
}

///|
test "a factor that does not grow is refused" {
  let refused = try {
    ignore(@metric.Histogram::new(native=@metric.Native::new(factor=1.0)))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "NaN counts but lands in no native bucket" {
  let h = @metric.Histogram::new(native=@metric.native)
  h.observe(0.0 / 0.0)
  guard h.snapshot().value is Native(count~, sparse~, ..) else {
    fail("native")
  }
  assert_eq(count, 1L)
  assert_eq(sparse.positive.length() + sparse.negative.length(), 0)
  assert_eq(sparse.zero_count, 0L)
}

///|
test "one bucket over the limit halves the resolution at once" {
  let h = limited(max_buckets=2, now=Ref(0.0))
  h.observe(1.0)
  h.observe(2.0)
  assert_eq(sparse_of(h).schema, 3)
  h.observe(4.0)
  assert_eq(sparse_of(h).schema, 2)
}

///|
test "the limit widens the zero bucket before it halves the resolution" {
  let h = limited(max_buckets=2, max_zero_threshold=1.5, now=Ref(0.0))
  h.observe(1.0)
  h.observe(2.0)
  h.observe(4.0)
  let sparse = sparse_of(h)
  // Bucket 0 ends at 1, within 1.5: it becomes part of the zero bucket.
  assert_eq(sparse.zero_threshold, 1.0)
  assert_eq(sparse.zero_count, 1L)
  assert_eq(sparse.schema, 3)
  assert_eq(sparse.positive, [(8, 1L), (16, 1L)])
}

///|
test "past min_reset the limit resets and keeps the last observation" {
  let now = Ref(0.0)
  let h = limited(max_buckets=2, min_reset=10.0, now~)
  h.observe(1.0)
  h.observe(2.0)
  now.val = 20.0
  h.observe(4.0)
  guard h.snapshot().value is Native(sparse~, count~, sum~, ..) else {
    fail("native")
  }
  assert_eq(count, 1L)
  assert_eq(sum, 4.0)
  assert_eq(sparse.schema, 3)
  assert_eq(sparse.positive, [(16, 1L)])
}

///|
test "before min_reset the limit coarsens and resets when the time comes" {
  let now = Ref(0.0)
  let h = limited(max_buckets=2, min_reset=10.0, now~)
  now.val = 5.0
  h.observe(1.0)
  h.observe(2.0)
  h.observe(4.0)
  assert_eq(sparse_of(h).schema, 2)
  now.val = 9.0
  guard h.snapshot().value is Native(count~, ..) else { fail("native") }
  assert_eq(count, 3L)
  now.val = 12.0
  guard h.snapshot().value is Native(count~, sparse~, ..) else {
    fail("native")
  }
  assert_eq(count, 0L)
  assert_eq(sparse.schema, 3)
}

///|
test "native exemplars are kept in value order and replace their nearest neighbour" {
  let now = Ref(0.0)
  let h = @metric.Histogram::new(
    native=@metric.Native::new(max_exemplars=2),
    clock=clock(now),
  )
  for v in [1.0, 3.0, 2.0] {
    now.val = now.val + 1.0
    h.observe(v, exemplar=@metric.Exemplar::new([("trace", v.to_string())], v))
  }
  assert_eq(sparse_of(h).exemplars.map(e => e.value), [1.0, 2.0])
}

///|
test "an exemplar older than the ttl is the one replaced" {
  let now = Ref(0.0)
  let h = @metric.Histogram::new(
    native=@metric.Native::new(max_exemplars=2, exemplar_ttl=60.0),
    clock=clock(now),
  )
  h.observe(1.0, exemplar=@metric.Exemplar::new([], 1.0))
  now.val = 50.0
  h.observe(3.0, exemplar=@metric.Exemplar::new([], 3.0))
  now.val = 100.0
  h.observe(2.0, exemplar=@metric.Exemplar::new([], 2.0))
  assert_eq(sparse_of(h).exemplars.map(e => e.value), [2.0, 3.0])
}

///|
test "max_exemplars 0 keeps no native exemplar" {
  let h = @metric.Histogram::new(native=@metric.Native::new(max_exemplars=0))
  h.observe(1.0, exemplar=@metric.Exemplar::new([], 1.0))
  assert_eq(sparse_of(h).exemplars.length(), 0)
}

///|
test "the three ways to write the settings agree" {
  let flat = @metric.Native::new(factor=1.05, max_buckets=50)
  let updated = { ..@metric.native, factor: 1.05, max_buckets: 50, }
  assert_eq(flat, updated)
  assert_eq(@metric.Native::new(), @metric.native)
}
