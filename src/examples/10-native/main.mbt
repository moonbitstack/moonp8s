// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A native histogram beside a classic one, both fed the same 500 sizes, and the
/// protobuf exposition Prometheus scrapes. The bytes are printed as hex, since that
/// is the only format a scraper reads native buckets from; the text formats below
/// carry the classic buckets alone. `scripts/native/check_scrape.py` serves the
/// bytes to a real Prometheus next to client_golang fed the same sizes.
fn main raise {
  let registry = @metric.Registry::new()
  let sizes = registry.histogram(
    "request_size_bytes",
    "Request sizes, in native buckets.",
    native=@metric.native,
  )
  let classic = registry.histogram(
    "request_size_classic_bytes",
    "Request sizes, in classic buckets.",
    buckets=[100.0, 1000.0, 10000.0],
  )
  for i in 0..<500 {
    // Integer arithmetic and one division: Go computes the same doubles bit for bit.
    let size = ((i * i % 9973 + 1) * 37).to_double() / 7.0
    sizes.observe(size)
    classic.observe(size)
  }
  let families = registry.collect()
  println(@base16.encode(@expo.protobuf(families)))
  println(@expo.text(families))
}
