// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn with_pair(
  labels : Array[(String, String)],
  name : String,
  value : String,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for p in labels {
    out.push(p)
  }
  out.push((name, value))
  out
}

///|
fn compare_pair(a : (String, String), b : (String, String)) -> Int32 {
  String::lexical_compare(a.0, b.0)
}

///|
fn render_labels(labels : Array[(String, String)]) -> String {
  if labels.length() == 0 {
    return ""
  }
  let sorted : Array[(String, String)] = []
  for p in labels {
    sorted.push(p)
  }
  sorted.sort_by(fn(a, b) { compare_pair(a, b) })
  let sb = StringBuilder()
  sb.write_char('{')
  for i = 0; i < sorted.length(); i = i + 1 {
    if i > 0 {
      sb.write_char(',')
    }
    sb.write_string(sorted[i].0)
    sb.write_string("=\"")
    sb.write_string(escape_label_value(sorted[i].1))
    sb.write_char('"')
  }
  sb.write_char('}')
  sb.to_string()
}

///|
fn exemplar_text(ex : @metric.Exemplar) -> String {
  if ex.labels.length() == 0 {
    return ""
  }
  let sb = StringBuilder()
  sb.write_string(" # ")
  sb.write_string(render_labels(ex.labels))
  sb.write_char(' ')
  sb.write_string(format_float(ex.value))
  match ex.timestamp {
    Some(t) => {
      sb.write_char(' ')
      sb.write_string(format_float(t))
    }
    None => ()
  }
  sb.to_string()
}

///|
fn timestamp_text(ts : Double, milliseconds : Bool) -> String {
  if milliseconds {
    " " + (ts * 1000.0).to_int64().to_string()
  } else {
    " " + format_float(ts)
  }
}

///|
fn write_line(
  sb : StringBuilder,
  name : String,
  labels : Array[(String, String)],
  value : String,
  timestamp : Double?,
  milliseconds : Bool,
  exemplar : String,
) -> Unit {
  sb.write_string(name)
  sb.write_string(render_labels(labels))
  sb.write_char(' ')
  sb.write_string(value)
  match timestamp {
    Some(ts) => sb.write_string(timestamp_text(ts, milliseconds))
    None => ()
  }
  sb.write_string(exemplar)
  sb.write_char('\n')
}

///|
fn is_counter(kind : @metric.Kind) -> Bool {
  match kind {
    @metric.Kind::Counter => true
    _ => false
  }
}

///|
fn is_gauge_histogram(kind : @metric.Kind) -> Bool {
  match kind {
    @metric.Kind::GaugeHistogram => true
    _ => false
  }
}

///|
fn number_name(kind : @metric.Kind, base : String) -> String {
  match kind {
    @metric.Kind::Counter => base + "_total"
    @metric.Kind::Info => base + "_info"
    _ => base
  }
}

///|
fn text_declared(kind : @metric.Kind, base : String) -> (String, String) {
  match kind {
    @metric.Kind::Counter => (base + "_total", "counter")
    @metric.Kind::Info => (base + "_info", "gauge")
    @metric.Kind::StateSet => (base, "gauge")
    @metric.Kind::GaugeHistogram => (base, "histogram")
    @metric.Kind::Unknown => (base, "untyped")
    _ => (base, kind.code())
  }
}

///|
fn find_exemplar(
  exemplars : Array[@metric.Exemplar],
  low : Double,
  high : Double,
  infinity : Bool,
) -> String {
  for ex in exemplars {
    let hit = if infinity {
      ex.value > low
    } else {
      ex.value > low && ex.value <= high
    }
    if hit {
      return exemplar_text(ex)
    }
  }
  ""
}

///|
fn write_created_family(
  sb : StringBuilder,
  name : String,
  help : String,
  lines : StringBuilder,
) -> Unit {
  sb.write_string("# HELP ")
  sb.write_string(name)
  sb.write_char(' ')
  sb.write_string(escape_help(help, false))
  sb.write_char('\n')
  sb.write_string("# TYPE ")
  sb.write_string(name)
  sb.write_string(" gauge\n")
  sb.write_string(lines.to_string())
}

///|
fn encode_text_family(
  sb : StringBuilder,
  family : @metric.MetricFamily,
) -> Unit {
  let base = family.name
  let (declared, spelling) = text_declared(family.kind, base)
  sb.write_string("# HELP ")
  sb.write_string(declared)
  sb.write_char(' ')
  sb.write_string(escape_help(family.help, false))
  sb.write_char('\n')
  sb.write_string("# TYPE ")
  sb.write_string(declared)
  sb.write_char(' ')
  sb.write_string(spelling)
  sb.write_char('\n')
  let created = StringBuilder()
  let gcount = StringBuilder()
  let gsum = StringBuilder()
  for point in family.metrics {
    match point.value {
      @metric.Value::Number(v) => {
        write_line(
          sb,
          number_name(family.kind, base),
          point.labels,
          format_float(v),
          point.timestamp,
          true,
          "",
        )
        if is_counter(family.kind) {
          match point.created {
            Some(c) =>
              write_line(
                created,
                base + "_created",
                point.labels,
                format_float(c),
                point.timestamp,
                true,
                "",
              )
            None => ()
          }
        }
      }
      @metric.Value::Buckets(buckets~, sum~, count~) => {
        for entry in buckets {
          write_line(
            sb,
            base + "_bucket",
            with_pair(point.labels, "le", format_float(entry.0)),
            format_float(entry.1.to_double()),
            point.timestamp,
            true,
            "",
          )
        }
        write_line(
          sb,
          base + "_bucket",
          with_pair(point.labels, "le", "+Inf"),
          format_float(count.to_double()),
          point.timestamp,
          true,
          "",
        )

        if is_gauge_histogram(family.kind) {
          write_line(
            gcount,
            base + "_gcount",
            point.labels,
            format_float(count.to_double()),
            point.timestamp,
            true,
            "",
          )
          write_line(
            gsum,
            base + "_gsum",
            point.labels,
            format_float(sum),
            point.timestamp,
            true,
            "",
          )
        } else {
          write_line(
            sb,
            base + "_count",
            point.labels,
            format_float(count.to_double()),
            point.timestamp,
            true,
            "",
          )
          write_line(
            sb,
            base + "_sum",
            point.labels,
            format_float(sum),
            point.timestamp,
            true,
            "",
          )
        }
        match point.created {
          Some(c) =>
            write_line(
              created,
              base + "_created",
              point.labels,
              format_float(c),
              point.timestamp,
              true,
              "",
            )
          None => ()
        }
      }
      @metric.Value::Quantiles(quantiles~, sum~, count~) => {
        for q in quantiles {
          write_line(
            sb,
            base,
            with_pair(point.labels, "quantile", format_float(q.0)),
            format_float(q.1),
            point.timestamp,
            true,
            "",
          )
        }
        write_line(
          sb,
          base + "_count",
          point.labels,
          format_float(count.to_double()),
          point.timestamp,
          true,
          "",
        )
        write_line(
          sb,
          base + "_sum",
          point.labels,
          format_float(sum),
          point.timestamp,
          true,
          "",
        )
        match point.created {
          Some(c) =>
            write_line(
              created,
              base + "_created",
              point.labels,
              format_float(c),
              point.timestamp,
              true,
              "",
            )
          None => ()
        }
      }
      @metric.Value::State(states~) =>
        for state in states {
          write_line(
            sb,
            base,
            with_pair(point.labels, base, state.0),
            if state.1 {
              "1.0"
            } else {
              "0.0"
            },
            point.timestamp,
            true,
            "",
          )
        }
    }
  }
  if created.to_string() != "" {
    write_created_family(sb, base + "_created", family.help, created)
  }
  if gcount.to_string() != "" {
    write_created_family(sb, base + "_gcount", family.help, gcount)
  }
  if gsum.to_string() != "" {
    write_created_family(sb, base + "_gsum", family.help, gsum)
  }
}

///|
fn encode_om_family(sb : StringBuilder, family : @metric.MetricFamily) -> Unit {
  let base = family.name
  sb.write_string("# HELP ")
  sb.write_string(base)
  sb.write_char(' ')
  sb.write_string(escape_help(family.help, true))
  sb.write_char('\n')
  sb.write_string("# TYPE ")
  sb.write_string(base)
  sb.write_char(' ')
  sb.write_string(family.kind.code())
  sb.write_char('\n')
  match family.unit {
    Some(u) => {
      sb.write_string("# UNIT ")
      sb.write_string(base)
      sb.write_char(' ')
      sb.write_string(u)
      sb.write_char('\n')
    }
    None => ()
  }
  let neg_inf = 0.0 - 1.0 / 0.0
  for point in family.metrics {
    match point.value {
      @metric.Value::Number(v) => {
        let ex = if point.exemplars.length() > 0 {
          if is_counter(family.kind) {
            exemplar_text(point.exemplars[0])
          } else {
            ""
          }
        } else {
          ""
        }
        write_line(
          sb,
          number_name(family.kind, base),
          point.labels,
          format_float(v),
          point.timestamp,
          false,
          ex,
        )
        if is_counter(family.kind) {
          match point.created {
            Some(c) =>
              write_line(
                sb,
                base + "_created",
                point.labels,
                format_float(c),
                point.timestamp,
                false,
                "",
              )
            None => ()
          }
        }
      }
      @metric.Value::Buckets(buckets~, sum~, count~) => {
        let mut low = neg_inf
        for entry in buckets {
          write_line(
            sb,
            base + "_bucket",
            with_pair(point.labels, "le", format_float(entry.0)),
            format_float(entry.1.to_double()),
            point.timestamp,
            false,
            find_exemplar(point.exemplars, low, entry.0, false),
          )
          low = entry.0
        }
        let last = if buckets.length() == 0 {
          0.0
        } else {
          buckets[buckets.length() - 1].0
        }
        write_line(
          sb,
          base + "_bucket",
          with_pair(point.labels, "le", "+Inf"),
          format_float(count.to_double()),
          point.timestamp,
          false,
          find_exemplar(point.exemplars, last, 0.0, true),
        )
        if is_gauge_histogram(family.kind) {
          write_line(
            sb,
            base + "_gcount",
            point.labels,
            format_float(count.to_double()),
            point.timestamp,
            false,
            "",
          )
          write_line(
            sb,
            base + "_gsum",
            point.labels,
            format_float(sum),
            point.timestamp,
            false,
            "",
          )
        } else {
          write_line(
            sb,
            base + "_count",
            point.labels,
            format_float(count.to_double()),
            point.timestamp,
            false,
            "",
          )
          write_line(
            sb,
            base + "_sum",
            point.labels,
            format_float(sum),
            point.timestamp,
            false,
            "",
          )
        }
        match point.created {
          Some(c) =>
            write_line(
              sb,
              base + "_created",
              point.labels,
              format_float(c),
              point.timestamp,
              false,
              "",
            )
          None => ()
        }
      }
      @metric.Value::Quantiles(quantiles~, sum~, count~) => {
        for q in quantiles {
          write_line(
            sb,
            base,
            with_pair(point.labels, "quantile", format_float(q.0)),
            format_float(q.1),
            point.timestamp,
            false,
            "",
          )
        }
        write_line(
          sb,
          base + "_count",
          point.labels,
          format_float(count.to_double()),
          point.timestamp,
          false,
          "",
        )
        write_line(
          sb,
          base + "_sum",
          point.labels,
          format_float(sum),
          point.timestamp,
          false,
          "",
        )
        match point.created {
          Some(c) =>
            write_line(
              sb,
              base + "_created",
              point.labels,
              format_float(c),
              point.timestamp,
              false,
              "",
            )
          None => ()
        }
      }
      @metric.Value::State(states~) =>
        for state in states {
          write_line(
            sb,
            base,
            with_pair(point.labels, base, state.0),
            if state.1 {
              "1.0"
            } else {
              "0.0"
            },
            point.timestamp,
            false,
            "",
          )
        }
    }
  }
}

///|
/// Write families in the Prometheus text exposition format, version 0.0.4.
/// Counters gain a `_total` suffix, info becomes a gauge ending in `_info`,
/// state sets become gauges, and `_created`, `_gcount`, and `_gsum` series are
/// emitted as separate gauge families, as the compatibility format requires.
pub fn text(families : Array[@metric.MetricFamily]) -> String {
  let sb = StringBuilder()
  for family in families {
    encode_text_family(sb, family)
  }
  sb.to_string()
}

///|
/// Write families in the OpenMetrics text format, version 1.0.0, ending with the
/// `# EOF` marker the format requires.
pub fn openmetrics(families : Array[@metric.MetricFamily]) -> String {
  let sb = StringBuilder()
  for family in families {
    encode_om_family(sb, family)
  }
  sb.write_string("# EOF\n")
  sb.to_string()
}
