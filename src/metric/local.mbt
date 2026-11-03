// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A non-atomic shard of a counter. Increments land in the shard and are added
/// to the shared counter on `flush`, which is the local accumulation the Rust
/// client offers; it keeps a hot path off the shared value without requiring
/// thread-local storage.
pub struct LocalCounter {
  priv counter : Counter
  priv mut value : Double
}

///|
/// A shard of this counter. Many shards may feed one counter; each flushes its
/// own accumulations.
pub fn Counter::shard(self : Counter) -> LocalCounter {
  { counter: self, value: 0.0, }
}

///|
/// Increase the shard by `by`.
pub fn LocalCounter::inc(
  self : LocalCounter,
  by~ : Double = 1.0,
) -> Unit raise Refused {
  if by < 0.0 {
    raise Refused("counter can only increase, got " + by.to_string())
  }
  self.value = self.value + by
}

///|
/// The shard's unflushed value.
pub fn LocalCounter::get(self : LocalCounter) -> Double {
  self.value
}

///|
/// Drop the unflushed value.
pub fn LocalCounter::reset(self : LocalCounter) -> Unit {
  self.value = 0.0
}

///|
/// Add the shard's value to the shared counter and clear the shard.
pub fn LocalCounter::flush(self : LocalCounter) -> Unit {
  if self.value != 0.0 {
    self.counter.accrue(self.value)
    self.value = 0.0
  }
}

///|
pub impl Metric for LocalCounter with fn kind(_self) {
  Kind::Counter
}

///|
pub impl Metric for LocalCounter with fn points(self) {
  self.flush()
  Metric::points(self.counter)
}

///|
pub extend LocalCounter with Metric::{kind, points}
