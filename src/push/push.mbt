// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A push gateway request: the method, the absolute URL path, the headers, and
/// the body. The caller sends it with whatever HTTP client it has; this package
/// never touches a socket.
pub(all) struct PushRequest {
  http_method : String
  path : String
  headers : Array[(String, String)]
  body : String
}

///|
fn normalize_gateway(gateway : String) -> String {
  let trimmed = gateway.trim().to_owned()
  let trimmed = if trimmed.length() > 0 && trimmed[trimmed.length() - 1] == '/' {
    trimmed[0:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
  if trimmed.contains("://") {
    trimmed
  } else {
    "http://" + trimmed
  }
}

///|
fn is_unreserved(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '-' ||
  c == '_' ||
  c == '.' ||
  c == '~'
}

///|
fn hex_digit(n : Int32) -> Char {
  let digits : Array[Char] = "0123456789ABCDEF".to_array()
  digits[n]
}

///|
fn quote_plus(v : String) -> String {
  let sb = StringBuilder()
  for c in v {
    if is_unreserved(c) {
      sb.write_char(c)
    } else if c == ' ' {
      sb.write_char('+')
    } else {
      for byte in @utf8.encode(c.to_string()) {
        let n = byte.to_int()
        sb.write_char('%')
        sb.write_char(hex_digit(n >> 4))
        sb.write_char(hex_digit(n & 15))
      }
    }
  }
  sb.to_string()
}

///|
fn escape_pair(name : String, value : String) -> String {
  if value == "" {
    name + "@base64/="
  } else if value.contains("/") || value.contains(" ") {
    name +
    "@base64/" +
    @base64.encode(@utf8.encode(value), kind=@base64.Kind::Url, padding=false)
  } else {
    name + "/" + quote_plus(value)
  }
}

///|
fn push_path(
  gateway : String,
  job : String,
  grouping_key : Array[(String, String)],
) -> String {
  let sorted : Array[(String, String)] = []
  for pair in grouping_key {
    sorted.push(pair)
  }
  sorted.sort_by(fn(a, b) { String::lexical_compare(a.0, b.0) })
  let sb = StringBuilder()
  sb.write_string(normalize_gateway(gateway))
  sb.write_string("/metrics/")
  sb.write_string(escape_pair("job", job))
  for pair in sorted {
    sb.write_char('/')
    sb.write_string(escape_pair(pair.0, pair.1))
  }
  sb.to_string()
}

///|
fn build(
  http_method : String,
  gateway : String,
  job : String,
  families : Array[@metric.MetricFamily],
  grouping_key : Array[(String, String)],
  format : @expo.Format,
) -> PushRequest {
  let body = match format {
    @expo.Format::Text004 => @expo.text(families)
    @expo.Format::OpenMetrics100 => @expo.openmetrics(families)
  }
  {
    http_method,
    path: push_path(gateway, job, grouping_key),
    headers: [("Content-Type", format.content_type())],
    body,
  }
}

///|
/// Build a `PUT` that replaces every series under `job` and `grouping_key` with
/// the exposition of `families`.
pub fn push(
  gateway : String,
  job : String,
  families : Array[@metric.MetricFamily],
  grouping_key? : Array[(String, String)],
  format~ : @expo.Format = @expo.Format::Text004,
) -> PushRequest {
  build("PUT", gateway, job, families, grouping_key.unwrap_or([]), format)
}

///|
/// Build a `POST` that replaces only the series named in `families`, leaving
/// other series under the same job and grouping key alone.
pub fn push_add(
  gateway : String,
  job : String,
  families : Array[@metric.MetricFamily],
  grouping_key? : Array[(String, String)],
  format~ : @expo.Format = @expo.Format::Text004,
) -> PushRequest {
  build("POST", gateway, job, families, grouping_key.unwrap_or([]), format)
}

///|
/// Build a `DELETE` that removes every series under `job` and `grouping_key`.
pub fn delete(
  gateway : String,
  job : String,
  grouping_key? : Array[(String, String)],
) -> PushRequest {
  {
    http_method: "DELETE",
    path: push_path(gateway, job, grouping_key.unwrap_or([])),
    headers: [("Content-Type", @expo.Format::Text004.content_type())],
    body: "",
  }
}
