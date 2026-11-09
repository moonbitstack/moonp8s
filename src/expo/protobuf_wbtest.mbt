// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
// Byte-exact golden vectors: the delimited io.prometheus.client encoding of one
// family each, as Prometheus's client_golang (`expfmt`, delimited protobuf over
// client_model 0.6.3) writes the same families. A change in a single field
// number, wire type or name moves these bytes.

///|
fn point(
  value : @metric.Value,
  labels : Array[(String, String)],
) -> @metric.Point {
  { labels, value, timestamp: None, created: None, exemplars: [], }
}

///|
fn gauge_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "temp",
      kind: @metric.Kind::Gauge,
      help: "C.",
      unit: None,
      metrics: [point(@metric.Value::Number(42.0), [])],
    },
  ]
}

///|
fn counter_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "http_requests",
      kind: @metric.Kind::Counter,
      help: ".",
      unit: None,
      metrics: [point(@metric.Value::Number(7.5), [])],
    },
  ]
}

///|
fn labeled_gauge_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "q",
      kind: @metric.Kind::Gauge,
      help: ".",
      unit: None,
      metrics: [point(@metric.Value::Number(1.0), [("k", "v")])],
    },
  ]
}

///|
fn summary_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "lat",
      kind: @metric.Kind::Summary,
      help: ".",
      unit: None,
      metrics: [
        point(
          @metric.Value::Quantiles(quantiles=[(0.5, 0.4)], sum=1.5, count=3),
          [],
        ),
      ],
    },
  ]
}

///|
fn histogram_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "h",
      kind: @metric.Kind::Histogram,
      help: ".",
      unit: None,
      metrics: [
        point(
          @metric.Value::Buckets(buckets=[(0.5, 1), (1.0, 2)], sum=1.3, count=2),
          [],
        ),
      ],
    },
  ]
}

///|
fn untyped_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "u",
      kind: @metric.Kind::Unknown,
      help: ".",
      unit: None,
      metrics: [point(@metric.Value::Number(1.25), [])],
    },
  ]
}

///|
fn info_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "ver",
      kind: @metric.Kind::Info,
      help: "v.",
      unit: None,
      metrics: [point(@metric.Value::Number(1.0), [("version", "1.2")])],
    },
  ]
}

///|
fn stateset_family() -> Array[@metric.MetricFamily] {
  [
    {
      name: "mode",
      kind: @metric.Kind::StateSet,
      help: "m.",
      unit: None,
      metrics: [
        point(@metric.Value::State(states=[("idle", true), ("busy", false)]), []),
      ],
    },
  ]
}

///|
test "gauge family is the golden bytes" {
  assert_eq(
    protobuf(gauge_family()),
    b"\x19\x0a\x04\x74\x65\x6d\x70\x12\x02\x43\x2e\x18\x01\x22\x0b\x12\x09\x09\x00\x00\x00\x00\x00\x00\x45\x40",
  )
}

///|
test "counter family is the golden bytes" {
  assert_eq(
    protobuf(counter_family()),
    b"\x27\x0a\x13\x68\x74\x74\x70\x5f\x72\x65\x71\x75\x65\x73\x74\x73\x5f\x74\x6f\x74\x61\x6c\x12\x01\x2e\x18\x00\x22\x0b\x1a\x09\x09\x00\x00\x00\x00\x00\x00\x1e\x40",
  )
}

///|
test "labeled gauge family is the golden bytes" {
  assert_eq(
    protobuf(labeled_gauge_family()),
    b"\x1d\x0a\x01\x71\x12\x01\x2e\x18\x01\x22\x13\x0a\x06\x0a\x01\x6b\x12\x01\x76\x12\x09\x09\x00\x00\x00\x00\x00\x00\xf0\x3f",
  )
}

///|
test "summary family is the golden bytes" {
  assert_eq(
    protobuf(summary_family()),
    b"\x2d\x0a\x03\x6c\x61\x74\x12\x01\x2e\x18\x02\x22\x21\x22\x1f\x08\x03\x11\x00\x00\x00\x00\x00\x00\xf8\x3f\x1a\x12\x09\x00\x00\x00\x00\x00\x00\xe0\x3f\x11\x9a\x99\x99\x99\x99\x99\xd9\x3f",
  )
}

///|
test "histogram family is the golden bytes" {
  assert_eq(
    protobuf(histogram_family()),
    b"\x31\x0a\x01\x68\x12\x01\x2e\x18\x04\x22\x27\x3a\x25\x08\x02\x11\xcd\xcc\xcc\xcc\xcc\xcc\xf4\x3f\x1a\x0b\x08\x01\x11\x00\x00\x00\x00\x00\x00\xe0\x3f\x1a\x0b\x08\x02\x11\x00\x00\x00\x00\x00\x00\xf0\x3f",
  )
}

///|
test "untyped family is the golden bytes" {
  assert_eq(
    protobuf(untyped_family()),
    b"\x15\x0a\x01\x75\x12\x01\x2e\x18\x03\x22\x0b\x2a\x09\x09\x00\x00\x00\x00\x00\x00\xf4\x3f",
  )
}

///|
test "an info family is the golden bytes, a gauge with its labels" {
  assert_eq(
    protobuf(info_family()),
    b"\x2d\x0a\x08\x76\x65\x72\x5f\x69\x6e\x66\x6f\x12\x02\x76\x2e\x18\x01\x22\x1b\x0a\x0e\x0a\x07\x76\x65\x72\x73\x69\x6f\x6e\x12\x03\x31\x2e\x32\x12\x09\x09\x00\x00\x00\x00\x00\x00\xf0\x3f",
  )
}

///|
test "a state set is one gauge per state" {
  assert_eq(
    protobuf(stateset_family()),
    b"\x42\x0a\x04\x6d\x6f\x64\x65\x12\x02\x6d\x2e\x18\x01\x22\x19\x0a\x0c\x0a\x04\x6d\x6f\x64\x65\x12\x04\x69\x64\x6c\x65\x12\x09\x09\x00\x00\x00\x00\x00\x00\xf0\x3f\x22\x19\x0a\x0c\x0a\x04\x6d\x6f\x64\x65\x12\x04\x62\x75\x73\x79\x12\x09\x09\x00\x00\x00\x00\x00\x00\x00\x00",
  )
}

///|
// The stream is delimited: a varint length before each family, and the two
// families in registration order.
test "two families are a delimited stream" {
  let both = counter_family() + gauge_family()
  assert_eq(
    protobuf(both),
    b"\x27\x0a\x13\x68\x74\x74\x70\x5f\x72\x65\x71\x75\x65\x73\x74\x73\x5f\x74\x6f\x74\x61\x6c\x12\x01\x2e\x18\x00\x22\x0b\x1a\x09\x09\x00\x00\x00\x00\x00\x00\x1e\x40\x19\x0a\x04\x74\x65\x6d\x70\x12\x02\x43\x2e\x18\x01\x22\x0b\x12\x09\x09\x00\x00\x00\x00\x00\x00\x45\x40",
  )
}

///|
// A point given a timestamp is written as its milliseconds in the timestamp
// field.
test "a point keeps its timestamp in milliseconds" {
  let family : @metric.MetricFamily = {
    name: "t",
    kind: @metric.Kind::Gauge,
    help: "t.",
    unit: None,
    metrics: [
      {
        labels: [],
        value: @metric.Value::Number(1.0),
        timestamp: Some(1700000000.0),
        created: None,
        exemplars: [],
      },
    ],
  }
  assert_eq(
    protobuf([family]),
    b"\x1d\x0a\x01\x74\x12\x02\x74\x2e\x18\x01\x22\x12\x12\x09\x09\x00\x00\x00\x00\x00\x00\xf0\x3f\x30\x80\xd0\x95\xff\xbc\x31",
  )
}

///|
// A counter keeps its exemplar in the counter sub-message.
test "a counter keeps its exemplar" {
  let ex = @metric.Exemplar::new(
    [("trace_id", "abc")],
    7.5,
    timestamp=1700000000.0,
  ) catch {
    @metric.Refused(message) => abort(message)
  }
  let family : @metric.MetricFamily = {
    name: "http_requests",
    kind: @metric.Kind::Counter,
    help: ".",
    unit: None,
    metrics: [
      {
        labels: [],
        value: @metric.Value::Number(7.5),
        timestamp: None,
        created: None,
        exemplars: [ex],
      },
    ],
  }
  let bytes = protobuf([family])
  // The exemplar is inside the counter: a label pair for trace_id.
  assert_true(bytes_has(bytes, b"trace_id"))
  assert_true(bytes_has(bytes, b"abc"))
}

///|
fn bytes_has(haystack : Bytes, needle : Bytes) -> Bool {
  let h = haystack.to_array()
  let n = needle.to_array()
  if n.length() > h.length() {
    return false
  }
  let mut i = 0
  let limit = h.length() - n.length()
  while i <= limit {
    let mut j = 0
    let mut ok = true
    while j < n.length() {
      if h[i + j] != n[j] {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      return true
    }
    i = i + 1
  }
  false
}

///|
// Read a delimited family back with the wire primitives: the name, the type, and
// the sample's value must come out. A broken field number or wire type would
// surface here as a wrong name or a missing value.
fn decode_first(bytes : Bytes) -> (String, Int32, Double) raise @wire.Refused {
  // The delimited framing: a varint length, then the family.
  let (length, start) = @wire.consume_varint(bytes)
  if length != (bytes.length() - start).to_uint64() {
    abort("the delimited length does not cover the family")
  }
  // Each field is a tag then its value. The family's name is field 1.
  let (f1, _, a1) = @wire.consume_tag(bytes, at=start)
  if f1 != 1 {
    abort("expected the name field, got " + f1.to_string())
  }
  let (name, a2) = @wire.consume_string(bytes, at=a1)
  // The help is field 2.
  let (f2, _, a3) = @wire.consume_tag(bytes, at=a2)
  if f2 != 2 {
    abort("expected the help field, got " + f2.to_string())
  }
  let (_, a4) = @wire.consume_string(bytes, at=a3)
  // The type is field 3, a varint.
  let (f3, _, a5) = @wire.consume_tag(bytes, at=a4)
  if f3 != 3 {
    abort("expected the type field, got " + f3.to_string())
  }
  let (type_num, a6) = @wire.consume_varint(bytes, at=a5)
  // The first metric is field 4.
  let (f4, _, a7) = @wire.consume_tag(bytes, at=a6)
  if f4 != 4 {
    abort("expected the metric field, got " + f4.to_string())
  }
  let (metric, _) = @wire.consume_bytes(bytes, at=a7)
  // The metric's value sub-message is field 2 for a gauge, 3 for a counter.
  let (vf, _, v0) = @wire.consume_tag(metric)
  if vf != 2 && vf != 3 {
    abort("expected a value field, got " + vf.to_string())
  }
  let (value, _) = @wire.consume_bytes(metric, at=v0)
  // The value's number is field 1, a fixed64.
  let (vf1, _, v1) = @wire.consume_tag(value)
  if vf1 != 1 {
    abort("expected the number field, got " + vf1.to_string())
  }
  let (bits, _) = @wire.consume_fixed64(value, at=v1)
  (name, type_num.to_int(), bits.reinterpret_as_double())
}

///|
test "the gauge family decodes back to what was written" {
  let (name, typ, value) = decode_first(protobuf(gauge_family())) catch {
    e => abort("decode failed: " + e.to_string())
  }
  assert_eq(name, "temp")
  assert_eq(typ, 1)
  assert_eq(value, 42.0)
}

///|
test "the counter family decodes back to its series name and value" {
  let (name, typ, value) = decode_first(protobuf(counter_family())) catch {
    e => abort("decode failed: " + e.to_string())
  }
  assert_eq(name, "http_requests_total")
  assert_eq(typ, 0)
  assert_eq(value, 7.5)
}

///|
// The same snapshot, two formats: the text format spells the counter's sample
// `name_total` and declares it a counter, and the protobuf stream names the
// family by its base, so a real Prometheus stores it under the same series.
test "a counter is the same series in text and protobuf" {
  let families = counter_family()
  let document = text(families)
  assert_true(document.contains("http_requests_total 7.5\n"))
  assert_true(document.contains("# TYPE http_requests_total counter\n"))
  let (name, typ, value) = decode_first(protobuf(families)) catch {
    _ => abort("decode failed")
  }
  assert_eq(name, "http_requests_total")
  assert_eq(typ, 0)
  assert_eq(value, 7.5)
}

///|
test "the content type names the proto and the framing" {
  assert_eq(
    protobuf_content_type, "application/vnd.google.protobuf; proto=io.prometheus.client.MetricFamily; encoding=delimited",
  )
}

///|
// An empty registry is an empty stream, not a family.
test "no families is an empty stream" {
  assert_eq(protobuf([]), b"")
}
