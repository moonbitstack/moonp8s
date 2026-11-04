// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A clock that moves a quarter of a second every time it is read, so the output is the same on
/// every run.
fn ticking() -> () -> Double {
  let mut at = 0.0
  fn() {
    at = at + 0.25
    at
  }
}

///|
fn run() -> Unit raise {
  let registry = @moonp8s.Registry::new()
  register_metrics(registry)
  let now = ticking()
  ignore(place_metered("tea", now~))
  ignore(place_metered("coffee", now~))
  ignore(place_metered("gold", now~) catch { _ => 0 })
  println(@moonp8s.text(registry.collect()))
}

///|
#coverage.skip
fn main {
  run() catch {
    e => println("refused: \{e}")
  }
}
