// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the remote writer builds a JSON post" {
  let writer = RemoteWriter::new("https://stats.example/report")
  let request = writer.request({
    name: "http",
    timestamp: 1700000000L,
    pid: 42L,
    reqs_per_second: 1.5,
    drops: 0L,
    average: 2.5,
    median: 2.0,
    top90th: 3.0,
    top99th: 4.0,
    top99p9th: 5.0,
  })
  assert_eq(request.http_method, "POST")
  assert_eq(request.url, "https://stats.example/report")
  assert_eq(request.headers[0].0, "Content-Type")
  assert_eq(request.headers[0].1, "application/json; charset=utf-8")
  assert_true(request.body.contains("\"name\":\"http\""))
  assert_true(request.body.contains("\"tm\":1700000000"))
  assert_true(request.body.contains("\"pid\":42"))
  assert_true(request.body.contains("\"qps\":1.5"))
  assert_true(request.body.contains("\"t99p9\":5.0"))
}
