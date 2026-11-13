// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn refused_key(key : String) -> Bool {
  try {
    ignore(entry_of_key(key))
    false
  } catch {
    @metric.Refused(_) => true
  }
}

///|
fn shown(labels : Array[(String, String)]) -> String {
  let sorted : Array[(String, String)] = []
  for pair in labels {
    sorted.push(pair)
  }
  sorted.sort_by(fn(a, b) { String::lexical_compare(a.0, b.0) })
  let sb = StringBuilder()
  let mut first = true
  for pair in sorted {
    if !first {
      sb.write_char(';')
    }
    first = false
    sb.write_string(pair.0)
    sb.write_char('=')
    sb.write_string(pair.1)
  }
  sb.to_string()
}

///|
test "a key is the four-field array a reader of these files expects" {
  let key = key_of(
    Entry::new("orders", "orders_total", [("code", "200")], "Orders.", 1.0),
  )
  assert_eq(key, "[\"orders\",\"orders_total\",{\"code\":\"200\"},\"Orders.\"]")
}

///|
test "a key comes back with every character it carried" {
  let entry = Entry::new(
    "orders",
    "orders_total",
    [("path", "a\"b\\c"), ("note", "line\nbreak\ttab\u{0001}中文🙂")],
    "Orders \"asked\" for.",
    1.0,
  )
  let key = key_of(entry)
  // The key is one line of JSON: a newline in it would cut the record in two.
  assert_false(key.contains("\n"))
  let back = entry_of_key(key) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(back.metric, "orders")
  assert_eq(back.sample, "orders_total")
  assert_eq(back.help, "Orders \"asked\" for.")
  assert_eq(
    shown(back.labels),
    "note=line\nbreak\ttab\u{0001}中文🙂;path=a\"b\\c",
  )
}

///|
test "a key written by another client is read, escapes and all" {
  let back = entry_of_key(
    "[\"orders\",\"orders_total\",{\"code\":\"200\",\"path\":\"a\\\"b\\\\c\\u4e2d\"},\"Orders.\"]",
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(shown(back.labels), "code=200;path=a\"b\\c中")
}

///|
test "a label name repeated in a key keeps the last value" {
  // RFC 8259 leaves the answer to the reader, and every client these files are
  // exchanged with keeps the last one.
  let back = entry_of_key(
    "[\"orders\",\"orders_total\",{\"code\":\"200\",\"code\":\"500\"},\"Orders.\"]",
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  assert_eq(shown(back.labels), "code=500")
}

///|
test "a key that is not the four fields is refused" {
  // Not JSON at all, and JSON of the wrong shape.
  assert_true(refused_key("orders"))
  assert_true(refused_key(""))
  assert_true(refused_key("[\"orders\",\"orders_total\","))
  assert_true(
    refused_key("[\"orders\",\"orders_total\",{},\"Orders.\"] trailing"),
  )
  assert_true(refused_key("{\"metric\":\"orders\"}"))
  assert_true(refused_key("[\"orders\",\"orders_total\",{}]"))
  assert_true(refused_key("[\"orders\",\"orders_total\",{},\"Orders.\",1]"))
  // Four fields of the wrong types.
  assert_true(refused_key("[1,\"orders_total\",{},\"Orders.\"]"))
  assert_true(refused_key("[\"orders\",2,{},\"Orders.\"]"))
  assert_true(refused_key("[\"orders\",\"orders_total\",[],\"Orders.\"]"))
  assert_true(
    refused_key("[\"orders\",\"orders_total\",{\"code\":200},\"Orders.\"]"),
  )
  assert_true(refused_key("[\"orders\",\"orders_total\",{},null]"))
}

///|
test "a key with a control character left raw is refused" {
  // A writer that let a newline through would split the record, so a reader
  // must not accept one that arrives that way.
  assert_true(
    refused_key("[\"orders\",\"orders_total\",{\"code\":\"a\nb\"},\"Orders.\"]"),
  )
}
