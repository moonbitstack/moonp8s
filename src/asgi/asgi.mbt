// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn now_seconds() -> Double {
  @env.now().reinterpret_as_int64().to_double() / 1000.0
}

///|
fn plain(status : Int32, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("Content-Type", "text/plain; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// A `/metrics` handler for a registry. `GET` negotiates the format from the
/// `Accept` header, `OPTIONS` advertises the allowed methods, anything else is
/// refused with 405, and `/favicon.ico` is answered empty so a browser probing
/// the endpoint stays quiet.
pub fn app(registry : @metric.Registry) -> @moonasgi.Handler {
  fn(request) {
    if request.http_method == "OPTIONS" {
      @moonasgi.Response::new(200, [("Allow", "OPTIONS,GET")], @utf8.encode(""))
    } else if request.http_method != "GET" {
      plain(405, "# HTTP 405: use OPTIONS or GET\n")
    } else if request.path == "/favicon.ico" {
      @moonasgi.Response::new(200, [], @utf8.encode(""))
    } else {
      let accept = request.header("Accept").unwrap_or("")
      let format = @expo.negotiate(accept)
      let families = registry.collect()
      let body = match format {
        @expo.Format::Text004 => @expo.text(families)
        @expo.Format::OpenMetrics100 => @expo.openmetrics(families)
      }
      @moonasgi.Response::new(
        200,
        [("Content-Type", format.content_type())],
        @utf8.encode(body),
      )
    }
  }
}

///|
/// A middleware that counts handled requests (`http_requests`, labelled by
/// method, route, and status) and observes their duration in seconds
/// (`http_request_duration_seconds`, labelled by method and route). The clock is
/// a parameter so a test can drive time; it defaults to wall-clock seconds.
pub fn middleware(
  registry : @metric.Registry,
  now? : () -> Double,
) -> @moonasgi.Middleware raise @metric.Refused {
  let clock = now.unwrap_or(fn() { now_seconds() })
  let requests = @metric.Family::new(["method", "route", "status"], fn() {
    @metric.Counter::new()
  })
  registry.register("http_requests", "HTTP requests handled.", requests)
  let duration = @metric.Family::new(["method", "route"], fn() raise @metric.Refused {
    @metric.Histogram::new()
  })
  registry.register(
    "http_request_duration_seconds", "HTTP request duration in seconds.", duration,
  )
  fn(next : (@moonasgi.Request) -> @moonasgi.Response) {
    fn(request : @moonasgi.Request) -> @moonasgi.Response {
      let start = clock()
      let response = next(request)
      let elapsed = clock() - start
      try {
        requests
        .labels([request.http_method, request.path, response.status.to_string()])
        .inc()
        duration.labels([request.http_method, request.path]).observe(elapsed)
      } catch {
        @metric.Refused(_) => ()
      }
      response
    }
  }
}
