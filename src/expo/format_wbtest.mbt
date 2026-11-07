// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "negotiate picks OpenMetrics when it is requested" {
  assert_eq(
    negotiate("application/openmetrics-text; version=1.0.0").content_type(),
    "application/openmetrics-text; version=1.0.0; charset=utf-8",
  )
  assert_eq(
    negotiate("application/openmetrics-text").content_type(),
    "application/openmetrics-text; version=1.0.0; charset=utf-8",
  )
}

///|
test "negotiate falls back to the compatibility format" {
  assert_eq(
    negotiate("text/plain; version=0.0.4").content_type(),
    "text/plain; version=0.0.4; charset=utf-8",
  )
  assert_eq(
    negotiate("").content_type(),
    "text/plain; version=0.0.4; charset=utf-8",
  )
  assert_eq(
    negotiate("application/json").content_type(),
    "text/plain; version=0.0.4; charset=utf-8",
  )
}

///|
test "negotiate reads a version list" {
  assert_eq(
    negotiate(
      "text/plain; version=0.0.4, application/openmetrics-text; version=1.0.0",
    ).content_type(),
    "text/plain; version=0.0.4; charset=utf-8",
  )
  assert_eq(
    negotiate(
      "application/openmetrics-text; version=1.0.0, text/plain; version=0.0.4",
    ).content_type(),
    "application/openmetrics-text; version=1.0.0; charset=utf-8",
  )
}

///|
test "a protobuf scrape is recognised from the Accept header" {
  assert_true(
    wants_protobuf(
      "application/vnd.google.protobuf; proto=io.prometheus.client.MetricFamily; encoding=delimited",
    ),
  )
  assert_true(
    wants_protobuf(
      "application/vnd.google.protobuf; q=1.0, text/plain; version=0.0.4",
    ),
  )
  assert_true(!wants_protobuf("text/plain; version=0.0.4"))
  assert_true(!wants_protobuf(""))
  assert_true(!wants_protobuf("application/json"))
}
