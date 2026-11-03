// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "format_float keeps a trailing .0 on integers" {
  assert_eq(format_float(1.0), "1.0")
  assert_eq(format_float(0.0), "0.0")
  assert_eq(format_float(10.0), "10.0")
  assert_eq(format_float(-1.0), "-1.0")
}

///|
test "format_float matches the reference exponent switch" {
  assert_eq(format_float(999999.0), "999999.0")
  assert_eq(format_float(123456.0), "123456.0")
  assert_eq(format_float(1000000.0), "1e+06")
  assert_eq(format_float(1234567.0), "1.234567e+06")
  assert_eq(format_float(10000000.0), "1e+07")
  assert_eq(format_float(0.0001), "0.0001")
  assert_eq(format_float(0.00001), "1e-05")
}

///|
test "format_float names the non-finite values" {
  let inf = 1.0 / 0.0
  assert_eq(format_float(inf), "+Inf")
  assert_eq(format_float(0.0 - inf), "-Inf")
  assert_eq(format_float(0.0 / 0.0), "NaN")
}

///|
test "format_float preserves negative zero" {
  assert_eq(format_float(-0.0), "-0.0")
}

///|
test "format_float keeps the shortest round-trip digits" {
  assert_eq(format_float(0.1 + 0.2), "0.30000000000000004")
  assert_eq(format_float(1.0 / 3.0), "0.3333333333333333")
  assert_eq(format_float(3.141592653589793), "3.141592653589793")
}
