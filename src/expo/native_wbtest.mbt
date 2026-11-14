///|
/// The same observations through moonp8s give the Histogram message client_golang wrote:
/// schema, zero bucket, spans, deltas and the classic buckets beside them, byte for byte.
test "native histograms write what client_golang writes" {
  for v in vectors() {
    let h = @metric.Histogram::new(
      buckets?=v.buckets,
      native=@metric.Native::new(
        factor=v.factor,
        zero_threshold=v.zero_threshold,
        max_buckets=v.max_buckets,
        min_reset=0.0,
        max_zero_threshold=v.max_zero_threshold,
        max_exemplars=0,
      ),
      clock=() => 0.0,
    )
    for b in v.values {
      h.observe(b.reinterpret_as_double())
    }
    guard h.snapshot().value is Native(buckets~, sparse~, sum~, count~) else {
      fail(v.name + ": not a native histogram")
    }
    let got = @base16.encode(histogram(count, sum, buckets, [], Some(sparse)))
    if got != v.message {
      fail(v.name + ":\n  got  " + got + "\n  want " + v.message)
    }
  }
}

///|
/// Without `native` the protobuf of a histogram is the classic one, unchanged.
test "a histogram without native buckets writes no native field" {
  let h = @metric.Histogram::new(buckets=[1.0, 2.0])
  h.observe(1.5)
  guard h.snapshot().value is Buckets(buckets~, sum~, count~) else {
    fail("a classic histogram")
  }
  inspect(
    @base16.encode(histogram(count, sum, buckets, [], None)),
    content="080111000000000000f83f1a0b080011000000000000f03f1a0b0801110000000000000040",
  )
}
