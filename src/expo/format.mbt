// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The exposition formats this library writes and reads.
pub(all) enum Format {
  /// Prometheus text exposition format, version 0.0.4.
  Text004
  /// OpenMetrics text format, version 1.0.0.
  OpenMetrics100
}

///|
/// The `Content-Type` an HTTP response should carry for this format.
pub fn Format::content_type(self : Format) -> String {
  match self {
    Format::Text004 => "text/plain; version=0.0.4; charset=utf-8"
    Format::OpenMetrics100 =>
      "application/openmetrics-text; version=1.0.0; charset=utf-8"
  }
}

///|
fn first_int(s : String) -> Int32 {
  let mut n = 0
  let mut any = false
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else {
      break
    }
  }
  if any {
    n
  } else {
    0
  }
}

///|
fn media_type(part : String) -> String {
  let mut end = part.length()
  for i, c in part {
    if c == ';' {
      end = i
      break
    }
  }
  part[0:end].to_owned().trim().to_owned()
}

///|
fn parameter(part : String, key : String) -> String? {
  for piece in part.split(";") {
    let p = piece.to_owned().trim().to_owned()
    let mut eq = -1
    for i, c in p {
      if c == '=' {
        eq = i
        break
      }
    }
    if eq >= 0 {
      let k = p[0:eq].to_owned().trim().to_owned()
      if k == key {
        return Some(p[eq + 1:].to_owned().trim().to_owned())
      }
    }
  }
  None
}

///|
fn version_at_least_one(version : String) -> Bool {
  let parts = version.split(".").collect()
  if parts.length() == 0 {
    return false
  }
  first_int(parts[0].to_owned()) >= 1
}

///|
/// Pick a format from an HTTP `Accept` header. `application/openmetrics-text`
/// wins when it names a version this library speaks (or names no version);
/// otherwise a scrape gets the compatibility format, which is also the default
/// when the header is absent or unrecognised.
pub fn negotiate(accept : String) -> Format {
  for part in accept.split(",") {
    let p = part.to_owned()
    let m = media_type(p)
    if m == "application/openmetrics-text" {
      match parameter(p, "version") {
        Some(v) => if version_at_least_one(v) { return Format::OpenMetrics100 }
        None => return Format::OpenMetrics100
      }
    } else if m == "text/plain" {
      return Format::Text004
    }
  }
  Format::Text004
}
