// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Escape a label value: backslash, double quote, and newline are
/// backslash-escaped, every other character passes through as UTF-8.
pub fn escape_label_value(v : String) -> String {
  let sb = StringBuilder()
  for c in v {
    if c == '\\' {
      sb.write_string("\\\\")
    } else if c == '"' {
      sb.write_string("\\\"")
    } else if c == '\n' {
      sb.write_string("\\n")
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// Escape help text. The compatibility format escapes backslash and newline;
/// OpenMetrics also escapes the double quote, so help text survives a round trip
/// inside a line-oriented document.
pub fn escape_help(v : String, quotes : Bool) -> String {
  let sb = StringBuilder()
  for c in v {
    if c == '\\' {
      sb.write_string("\\\\")
    } else if c == '\n' {
      sb.write_string("\\n")
    } else if quotes && c == '"' {
      sb.write_string("\\\"")
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}
