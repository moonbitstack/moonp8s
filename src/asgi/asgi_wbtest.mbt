// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn empty_request(
  http_method : String,
  path : String,
  headers : Array[(String, String)],
) -> @moonasgi.Request {
  {
    http_method,
    path,
    query_string: @utf8.encode(""),
    headers,
    body: @utf8.encode(""),
  }
}

///|
test "a GET renders the compatibility format by default" {
  let registry = @metric.Registry::new() catch {
    @metric.Refused(message) => abort(message)
  }
  let counter = registry.counter("requests", "Requests.") catch {
    @metric.Refused(message) => abort(message)
  }
  counter.inc()
  let response = app(registry)(empty_request("GET", "/metrics", []))
  assert_eq(response.status, 200)
  assert_eq(
    response.header("Content-Type"),
    Some("text/plain; version=0.0.4; charset=utf-8"),
  )
  assert_eq(response.body, @utf8.encode(@expo.text(registry.collect())))
}

///|
test "a GET negotiates OpenMetrics" {
  let registry = @metric.Registry::new() catch {
    @metric.Refused(message) => abort(message)
  }
  let response = app(registry)(
    empty_request("GET", "/metrics", [
      ("Accept", "application/openmetrics-text; version=1.0.0"),
    ]),
  )
  assert_eq(
    response.header("Content-Type"),
    Some("application/openmetrics-text; version=1.0.0; charset=utf-8"),
  )
}

///|
test "other methods are refused" {
  let registry = @metric.Registry::new() catch {
    @metric.Refused(message) => abort(message)
  }
  let response = app(registry)(empty_request("POST", "/metrics", []))
  assert_eq(response.status, 405)
}

///|
test "OPTIONS advertises the allowed methods" {
  let registry = @metric.Registry::new() catch {
    @metric.Refused(message) => abort(message)
  }
  let response = app(registry)(empty_request("OPTIONS", "/metrics", []))
  assert_eq(response.status, 200)
  assert_eq(response.header("Allow"), Some("OPTIONS,GET"))
}

///|
test "middleware counts requests and observes duration" {
  let registry = @metric.Registry::new() catch {
    @metric.Refused(message) => abort(message)
  }
  let mut tick = 0.0
  let clock = fn() {
    let value = tick
    tick = tick + 0.5
    value
  }
  let wrap = middleware(registry, now=clock) catch {
    @metric.Refused(message) => abort(message)
  }
  let handler = fn(_request : @moonasgi.Request) -> @moonasgi.Response {
    @moonasgi.Response::new(200, [], @utf8.encode("ok"))
  }
  let response = wrap(handler)(empty_request("GET", "/items", []))
  assert_eq(response.status, 200)
  let families = registry.collect()
  assert_eq(families.length(), 2)
  let requests = families[0]
  assert_eq(requests.name, "http_requests")
  match requests.metrics[0].value {
    @metric.Value::Number(v) => assert_eq(v, 1.0)
    _ => abort("expected a number")
  }
  let duration = families[1]
  assert_eq(duration.name, "http_request_duration_seconds")
  match duration.metrics[0].value {
    @metric.Value::Buckets(sum~, count~, ..) => {
      assert_eq(sum, 0.5)
      assert_eq(count, 1L)
    }
    _ => abort("expected buckets")
  }
}
