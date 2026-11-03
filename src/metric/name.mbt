// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn is_ascii_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Whether `name` is a metric name under the OpenMetrics character rules:
/// `[a-zA-Z_:][a-zA-Z0-9_:]*`.
pub fn is_valid_metric_name(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let mut first = true
  for c in name {
    let ok = if first {
      is_ascii_alpha(c) || c == '_' || c == ':'
    } else {
      is_ascii_alpha(c) || is_ascii_digit(c) || c == '_' || c == ':'
    }
    if !ok {
      return false
    }
    first = false
  }
  true
}

///|
/// Whether `name` is a label name under the OpenMetrics character rules:
/// `[a-zA-Z_][a-zA-Z0-9_]*`.
pub fn is_valid_label_name(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let mut first = true
  for c in name {
    let ok = if first {
      is_ascii_alpha(c) || c == '_'
    } else {
      is_ascii_alpha(c) || is_ascii_digit(c) || c == '_'
    }
    if !ok {
      return false
    }
    first = false
  }
  true
}

///|
/// Whether `unit` may be appended to a metric name. A unit starts with a letter
/// and continues with letters, digits, or underscores.
pub fn is_valid_unit(unit : String) -> Bool {
  if unit.length() == 0 {
    return false
  }
  let mut first = true
  for c in unit {
    let ok = if first {
      is_ascii_alpha(c)
    } else {
      is_ascii_alpha(c) || is_ascii_digit(c) || c == '_'
    }
    if !ok {
      return false
    }
    first = false
  }
  true
}

///|
/// Refuse a value that is not a metric name.
fn check_metric_name(name : String) -> Unit raise Refused {
  if !is_valid_metric_name(name) {
    raise Refused("invalid metric name: " + name)
  }
}

///|
/// Refuse a value that is not a label name.
fn check_label_name(name : String) -> Unit raise Refused {
  if !is_valid_label_name(name) {
    raise Refused("invalid label name: " + name)
  }
}

///|
/// Refuse a value that is not a unit.
fn check_unit(unit : String) -> Unit raise Refused {
  if !is_valid_unit(unit) {
    raise Refused("invalid unit: " + unit)
  }
}
