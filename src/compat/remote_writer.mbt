// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The periodic stat report the legacy remote writer posted as JSON.
pub(all) struct StatReport {
  name : String
  timestamp : Int64
  pid : Int64
  reqs_per_second : Double
  drops : Int64
  average : Double
  median : Double
  top90th : Double
  top99th : Double
  top99p9th : Double
}

///|
/// A report request, ready for the caller to send: a POST of JSON to the
/// reporting endpoint.
pub(all) struct RemoteRequest {
  http_method : String
  url : String
  headers : Array[(String, String)]
  body : String
}

///|
fn json_string(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    if c == '"' {
      sb.write_string("\\\"")
    } else if c == '\\' {
      sb.write_string("\\\\")
    } else if c == '\n' {
      sb.write_string("\\n")
    } else if c == '\r' {
      sb.write_string("\\r")
    } else if c == '\t' {
      sb.write_string("\\t")
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// A remote writer bound to one reporting endpoint.
pub struct RemoteWriter {
  priv endpoint : String
}

///|
/// A writer for `endpoint`.
pub fn RemoteWriter::new(endpoint : String) -> RemoteWriter {
  { endpoint, }
}

///|
/// Build the POST a remote writer sends for `report`.
pub fn RemoteWriter::request(
  self : RemoteWriter,
  report : StatReport,
) -> RemoteRequest {
  let sb = StringBuilder()
  sb.write_string("{\"name\":")
  sb.write_string(json_string(report.name))
  sb.write_string(",\"tm\":")
  sb.write_string(report.timestamp.to_string())
  sb.write_string(",\"pid\":")
  sb.write_string(report.pid.to_string())
  sb.write_string(",\"qps\":")
  sb.write_string(@expo.format_float(report.reqs_per_second))
  sb.write_string(",\"drops\":")
  sb.write_string(report.drops.to_string())
  sb.write_string(",\"avg\":")
  sb.write_string(@expo.format_float(report.average))
  sb.write_string(",\"med\":")
  sb.write_string(@expo.format_float(report.median))
  sb.write_string(",\"t90\":")
  sb.write_string(@expo.format_float(report.top90th))
  sb.write_string(",\"t99\":")
  sb.write_string(@expo.format_float(report.top99th))
  sb.write_string(",\"t99p9\":")
  sb.write_string(@expo.format_float(report.top99p9th))
  sb.write_char('}')
  {
    http_method: "POST",
    url: self.endpoint,
    headers: [("Content-Type", "application/json; charset=utf-8")],
    body: sb.to_string(),
  }
}
