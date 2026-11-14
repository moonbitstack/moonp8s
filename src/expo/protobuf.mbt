// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
// The io.prometheus.client schema as Prometheus scrapes it, built on moonproto's
// wire primitives. Each sub-message is a tag then a length, in that order, the
// order the reference clients write and the one a real scraper re-derives. The
// field numbers are the ones in metrics.proto; a single wrong one corrupts a
// whole field.
//
// A sub-message is encoded into a side buffer and spliced in as one
// length-delimited field. The top level is a stream of such messages, each
// preceded by its length, the `encoding=delimited` framing of the content type.

///|
/// The `Content-Type` an HTTP response should carry for the protobuf format:
/// the metric family the stream holds and the framing of the messages.
pub let protobuf_content_type : String = "application/vnd.google.protobuf; proto=io.prometheus.client.MetricFamily; encoding=delimited"

///|
// The numeric value the wire enum MetricType takes. The order differs from the
// kinds' declaration: histogram and gauge histogram follow untyped, and info and
// state sets have no type of their own, so the reference clients expose them as
// gauges.
fn proto_type(kind : @metric.Kind) -> Int32 {
  match kind {
    @metric.Kind::Counter => 0
    @metric.Kind::Gauge => 1
    @metric.Kind::Summary => 2
    @metric.Kind::Unknown => 3
    @metric.Kind::Histogram => 4
    @metric.Kind::GaugeHistogram => 5
    @metric.Kind::Info => 1
    @metric.Kind::StateSet => 1
  }
}

///|
fn append_double(buf : Buffer, number : Int32, value : Double) -> Unit {
  @wire.append_tag(buf, number, @wire.WireType::Fixed64)
  @wire.append_fixed64(buf, value.reinterpret_as_uint64())
}

///|
// A varint field. Counts are non-negative, so the two's-complement form is the
// plain value.
fn append_uint(buf : Buffer, number : Int32, value : Int64) -> Unit {
  @wire.append_tag(buf, number, @wire.WireType::Varint)
  @wire.append_varint(buf, value.reinterpret_as_uint64())
}

///|
// A signed varint field in the zigzag form `sint32` and `sint64` use.
fn append_sint(buf : Buffer, number : Int32, value : Int64) -> Unit {
  @wire.append_tag(buf, number, @wire.WireType::Varint)
  @wire.append_varint(buf, @wire.encode_zigzag(value))
}

///|
// A google.protobuf.Timestamp from Unix seconds: whole seconds, then the nanoseconds left.
fn timestamp_proto(seconds : Double) -> Bytes {
  let whole = seconds.floor()
  let nanos = ((seconds - whole) * 1.0e9).round().to_int()
  let body = Buffer()
  if whole != 0.0 {
    append_uint(body, 1, whole.to_int64())
  }
  if nanos != 0 {
    append_uint(body, 2, nanos.to_int64())
  }
  body.to_bytes()
}

///|
fn append_enum(buf : Buffer, number : Int32, value : Int32) -> Unit {
  @wire.append_tag(buf, number, @wire.WireType::Varint)
  @wire.append_varint(buf, value.to_uint64())
}

///|
fn append_string(buf : Buffer, number : Int32, value : String) -> Unit {
  @wire.append_tag(buf, number, @wire.WireType::LengthDelimited)
  @wire.append_string(buf, value)
}

///|
// A length-delimited sub-message: its tag, its length, and its bytes.
fn append_message(buf : Buffer, number : Int32, body : Bytes) -> Unit {
  @wire.append_tag(buf, number, @wire.WireType::LengthDelimited)
  @wire.append_bytes(buf, body)
}

///|
fn label_pair(name : String, value : String) -> Bytes {
  let body = Buffer()
  append_string(body, 1, name)
  append_string(body, 2, value)
  body.to_bytes()
}

///|
fn quantile(quantile : Double, value : Double) -> Bytes {
  let body = Buffer()
  append_double(body, 1, quantile)
  append_double(body, 2, value)
  body.to_bytes()
}

///|
fn bucket(
  upper_bound : Double,
  cumulative_count : Int64,
  exemplar : @metric.Exemplar?,
) -> Bytes {
  let body = Buffer()
  append_uint(body, 1, cumulative_count)
  append_double(body, 2, upper_bound)
  if exemplar is Some(ex) {
    append_message(body, 3, exemplar_proto(ex))
  }
  body.to_bytes()
}

///|
fn gauge(value : Double) -> Bytes {
  let body = Buffer()
  append_double(body, 1, value)
  body.to_bytes()
}

///|
fn exemplar_proto(ex : @metric.Exemplar) -> Bytes {
  let body = Buffer()
  for pair in ex.labels {
    append_message(body, 1, label_pair(pair.0, pair.1))
  }
  append_double(body, 2, ex.value)
  // The schema's timestamp is a google.protobuf.Timestamp message, not a number.
  match ex.timestamp {
    Some(t) => append_message(body, 3, timestamp_proto(t))
    None => ()
  }
  body.to_bytes()
}

///|
fn counter(value : Double, exemplar : @metric.Exemplar?) -> Bytes {
  let body = Buffer()
  append_double(body, 1, value)
  match exemplar {
    Some(ex) => append_message(body, 2, exemplar_proto(ex))
    None => ()
  }
  body.to_bytes()
}

///|
fn summary(
  count : Int64,
  sum : Double,
  quantiles : Array[(Double, Double)],
) -> Bytes {
  let body = Buffer()
  append_uint(body, 1, count)
  append_double(body, 2, sum)
  for q in quantiles {
    append_message(body, 3, quantile(q.0, q.1))
  }
  body.to_bytes()
}

///|
// The exemplar a classic bucket carries: the one whose value falls in it. `bounds.length()`
// stands for the `+Inf` bucket.
fn exemplar_in(
  exemplars : Array[@metric.Exemplar],
  bounds : Array[(Double, Int64)],
  index : Int32,
) -> @metric.Exemplar? {
  for ex in exemplars {
    let mut at = bounds.length()
    for i, entry in bounds {
      if ex.value <= entry.0 {
        at = i
        break
      }
    }
    if at == index {
      return Some(ex)
    }
  }
  None
}

///|
// The populated buckets of one side as spans and deltas. A gap of one or two empty buckets is
// carried as zero deltas inside the span rather than as a new span, as client_golang does, so
// that the same buckets come out as the same bytes.
fn spans_of(
  buckets : Array[(Int32, Int64)],
) -> (Array[(Int32, Int32)], Array[Int64]) {
  let spans : Array[(Int32, Int32)] = []
  let deltas : Array[Int64] = []
  let mut previous = 0L
  let mut next = 0
  for n, entry in buckets {
    let gap = entry.0 - next
    if n == 0 || gap > 2 {
      spans.push((gap, 0))
    } else {
      for _ in 0..<gap {
        let last = spans.length() - 1
        spans[last] = (spans[last].0, spans[last].1 + 1)
        deltas.push(0L - previous)
        previous = 0L
      }
    }
    let last = spans.length() - 1
    spans[last] = (spans[last].0, spans[last].1 + 1)
    deltas.push(entry.1 - previous)
    previous = entry.1
    next = entry.0 + 1
  }
  (spans, deltas)
}

///|
fn span(offset : Int32, length : Int32) -> Bytes {
  let body = Buffer()
  append_sint(body, 1, offset.to_int64())
  append_uint(body, 2, length.to_int64())
  body.to_bytes()
}

///|
fn histogram(
  count : Int64,
  sum : Double,
  buckets : Array[(Double, Int64)],
  exemplars : Array[@metric.Exemplar],
  sparse : @metric.Sparse?,
) -> Bytes {
  let body = Buffer()
  append_uint(body, 1, count)
  append_double(body, 2, sum)
  // The +Inf bucket is not written: the count is that bucket, and a scraper
  // adds it back, as client_golang leaves it out. It is written when it carries an
  // exemplar, which has nowhere else to go.
  for i, entry in buckets {
    if entry.0 != 1.0 / 0.0 {
      append_message(
        body,
        3,
        bucket(entry.0, entry.1, exemplar_in(exemplars, buckets, i)),
      )
    }
  }
  if exemplar_in(exemplars, buckets, buckets.length()) is Some(ex) {
    append_message(body, 3, bucket(1.0 / 0.0, count, Some(ex)))
  }
  if sparse is Some(native) {
    append_sint(body, 5, native.schema.to_int64())
    append_double(body, 6, native.zero_threshold)
    append_uint(body, 7, native.zero_count)
    let (negative, negative_deltas) = spans_of(native.negative)
    let (positive, positive_deltas) = spans_of(native.positive)
    for s in negative {
      append_message(body, 9, span(s.0, s.1))
    }
    for d in negative_deltas {
      append_sint(body, 10, d)
    }
    // A native histogram with no observation and an exact zero bucket would otherwise look
    // like a classic one; an empty span says it is native.
    if native.zero_threshold == 0.0 &&
      native.zero_count == 0L &&
      positive.is_empty() &&
      negative.is_empty() {
      append_message(body, 12, span(0, 0))
    }
    for s in positive {
      append_message(body, 12, span(s.0, s.1))
    }
    for d in positive_deltas {
      append_sint(body, 13, d)
    }
  }
  if sparse is Some(native) {
    for ex in native.exemplars {
      append_message(body, 16, exemplar_proto(ex))
    }
  }
  body.to_bytes()
}

///|
fn first_exemplar(exemplars : Array[@metric.Exemplar]) -> @metric.Exemplar? {
  match exemplars.length() {
    0 => None
    _ => Some(exemplars[0])
  }
}

///|
// The timestamp field, in the milliseconds the schema counts.
fn append_timestamp(buf : Buffer, timestamp : Double?) -> Unit {
  match timestamp {
    Some(ts) => append_uint(buf, 6, (ts * 1000.0).to_int64())
    None => ()
  }
}

///|
// The sub-message a numeric point fills: a counter's value goes in the counter
// field with its exemplar, an untyped point in the untyped field, and every
// other kind as a gauge.
fn number_metric(family : @metric.MetricFamily, point : @metric.Point) -> Bytes {
  let body = Buffer()
  for pair in point.labels {
    append_message(body, 1, label_pair(pair.0, pair.1))
  }
  match point.value {
    @metric.Value::Number(v) =>
      match family.kind {
        @metric.Kind::Counter =>
          append_message(body, 3, counter(v, first_exemplar(point.exemplars)))
        @metric.Kind::Unknown => append_message(body, 5, gauge(v))
        _ => append_message(body, 2, gauge(v))
      }
    _ => ()
  }
  append_timestamp(body, point.timestamp)
  body.to_bytes()
}

///|
// The sub-message a histogram point fills, in the histogram field.
fn histogram_metric(point : @metric.Point) -> Bytes {
  let body = Buffer()
  for pair in point.labels {
    append_message(body, 1, label_pair(pair.0, pair.1))
  }
  match point.value {
    @metric.Value::Buckets(buckets~, sum~, count~) =>
      append_message(
        body,
        7,
        histogram(count, sum, buckets, point.exemplars, None),
      )
    @metric.Value::Native(buckets~, sparse~, sum~, count~) =>
      append_message(
        body,
        7,
        histogram(count, sum, buckets, point.exemplars, Some(sparse)),
      )
    _ => ()
  }
  append_timestamp(body, point.timestamp)
  body.to_bytes()
}

///|
// The sub-message a summary point fills, in the summary field.
fn summary_metric(point : @metric.Point) -> Bytes {
  let body = Buffer()
  for pair in point.labels {
    append_message(body, 1, label_pair(pair.0, pair.1))
  }
  match point.value {
    @metric.Value::Quantiles(quantiles~, sum~, count~) =>
      append_message(body, 4, summary(count, sum, quantiles))
    _ => ()
  }
  append_timestamp(body, point.timestamp)
  body.to_bytes()
}

///|
// A state set is not one series: it is one gauge per state, each named by a
// label that carries the state. Each state becomes its own Metric.
fn state_metrics(
  family : @metric.MetricFamily,
  point : @metric.Point,
  out : Buffer,
) -> Unit {
  match point.value {
    @metric.Value::State(states~) =>
      for state in states {
        let body = Buffer()
        for pair in point.labels {
          append_message(body, 1, label_pair(pair.0, pair.1))
        }
        append_message(body, 1, label_pair(family.name, state.0))
        append_message(body, 2, gauge(if state.1 { 1.0 } else { 0.0 }))
        append_timestamp(body, point.timestamp)
        append_message(out, 4, body.to_bytes())
      }
    _ => ()
  }
}

///|
// The Metrics of one family: a point that is a state set yields one Metric per
// state, and any other point yields one.
fn encode_family_metrics(
  family : @metric.MetricFamily,
  point : @metric.Point,
  out : Buffer,
) -> Unit {
  match point.value {
    @metric.Value::State(_) => state_metrics(family, point, out)
    @metric.Value::Number(_) =>
      append_message(out, 4, number_metric(family, point))
    @metric.Value::Buckets(_) | @metric.Value::Native(_) =>
      append_message(out, 4, histogram_metric(point))
    @metric.Value::Quantiles(_) => append_message(out, 4, summary_metric(point))
  }
}

///|
fn encode_family(family : @metric.MetricFamily) -> Bytes {
  let body = Buffer()
  // Prometheus takes a protobuf family's name as the series name, as
  // client_golang writes it: a counter's carries `_total`, an info's `_info`.
  append_string(body, 1, text_declared(family.kind, family.name).0)
  append_string(body, 2, family.help)
  append_enum(body, 3, proto_type(family.kind))
  for point in family.metrics {
    encode_family_metrics(family, point, body)
  }
  body.to_bytes()
}

///|
/// Write families in the Prometheus protobuf format: a length-delimited stream
/// of `io.prometheus.client.MetricFamily` messages, the bytes a scraper reads
/// when it answers `application/vnd.google.protobuf`. It shares the text
/// formats' snapshot, so one scrape is every format. A family is named as the
/// text format declares it, so a counter is `<name>_total` with its value in
/// the counter field and an info is `<name>_info`; a histogram keeps its
/// cumulative buckets, sum, and count, its `+Inf` bucket being the count; a summary keeps
/// its count, sum, and quantiles; a state set is a gauge per state.
pub fn protobuf(families : Array[@metric.MetricFamily]) -> Bytes {
  let out = Buffer()
  for family in families {
    @wire.append_bytes(out, encode_family(family))
  }
  out.to_bytes()
}
