// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A parsed sample line before it is folded into a family.
priv struct RawSample {
  name : String
  labels : Array[(String, String)]
  value : Double
  timestamp : Double?
  ex_labels : Array[(String, String)]
  ex_value : Double?
  ex_timestamp : Double?
}

///|
priv struct Cursor {
  chars : Array[Char]
  mut i : Int32
}

///|
fn Cursor::new(s : String) -> Cursor {
  { chars: s.to_array(), i: 0, }
}

///|
fn Cursor::at_end(self : Cursor) -> Bool {
  self.i >= self.chars.length()
}

///|
fn Cursor::peek(self : Cursor) -> Char? {
  if self.i < self.chars.length() {
    Some(self.chars[self.i])
  } else {
    None
  }
}

///|
fn Cursor::bump(self : Cursor) -> Unit {
  self.i = self.i + 1
}

///|
fn Cursor::skip_space(self : Cursor) -> Unit {
  while !self.at_end() {
    let c = self.chars[self.i]
    if c == ' ' || c == '\t' {
      self.bump()
    } else {
      break
    }
  }
}

///|
fn Cursor::take_until(self : Cursor, stop : (Char) -> Bool) -> String {
  let sb = StringBuilder()
  while !self.at_end() && !stop(self.chars[self.i]) {
    sb.write_char(self.chars[self.i])
    self.bump()
  }
  sb.to_string()
}

///|
fn parse_float(s : String) -> Double? {
  let text = s.trim()
  // The three values every exposition may carry by name. `parse_double` reads
  // decimals only, and a parser that refused these would fail a conformant
  // exposition.
  match text {
    "NaN" | "nan" | "NAN" => Some(0.0 / 0.0)
    "+Inf" | "Inf" | "inf" | "+inf" | "INF" | "infinity" | "Infinity" =>
      Some(1.0 / 0.0)
    "-Inf" | "-inf" | "-INF" | "-infinity" | "-Infinity" =>
      Some(0.0 - 1.0 / 0.0)
    _ => Some(@string.parse_double(text)) catch { _ => None }
  }
}

///|
fn parse_label_value(c : Cursor) -> String raise @metric.Refused {
  match c.peek() {
    Some('"') => c.bump()
    _ =>
      raise @metric.Refused(
        "expected a quoted label value at " + c.i.to_string(),
      )
  }
  let sb = StringBuilder()
  while !c.at_end() {
    let ch = c.chars[c.i]
    if ch == '"' {
      c.bump()
      return sb.to_string()
    }
    if ch == '\\' {
      c.bump()
      if c.at_end() {
        raise @metric.Refused("unterminated escape in label value")
      }
      let e = c.chars[c.i]
      if e == '\\' {
        sb.write_char('\\')
      } else if e == '"' {
        sb.write_char('"')
      } else if e == 'n' {
        sb.write_char('\n')
      } else {
        sb.write_char(e)
      }
      c.bump()
    } else {
      sb.write_char(ch)
      c.bump()
    }
  }
  raise @metric.Refused("unterminated label value")
}

///|
fn parse_labels(c : Cursor) -> Array[(String, String)] raise @metric.Refused {
  let out : Array[(String, String)] = []
  c.skip_space()
  match c.peek() {
    Some('{') => c.bump()
    _ => return out
  }
  c.skip_space()
  match c.peek() {
    Some('}') => {
      c.bump()
      return out
    }
    _ => ()
  }
  while true {
    c.skip_space()
    let name = c.take_until(fn(ch) {
      ch == '=' || ch == ' ' || ch == '}' || ch == ','
    })
    if name == "" {
      raise @metric.Refused("empty label name at " + c.i.to_string())
    }
    c.skip_space()
    match c.peek() {
      Some('=') => c.bump()
      _ => raise @metric.Refused("expected = after label name " + name)
    }
    c.skip_space()
    let value = parse_label_value(c)
    out.push((name, value))
    c.skip_space()
    match c.peek() {
      Some(',') => {
        c.bump()
        continue
      }
      Some('}') => {
        c.bump()
        break
      }
      _ => raise @metric.Refused("expected , or } in label set")
    }
  }
  out
}

///|
fn parse_sample(line : String) -> RawSample raise @metric.Refused {
  let c = Cursor::new(line)
  c.skip_space()
  let name = c.take_until(fn(ch) { ch == '{' || ch == ' ' || ch == '\t' })
  if name == "" {
    raise @metric.Refused("empty sample name")
  }
  let labels = parse_labels(c)
  c.skip_space()
  let value_token = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
  let value = match parse_float(value_token) {
    Some(v) => v
    None => raise @metric.Refused("bad sample value: " + value_token)
  }
  c.skip_space()
  let mut timestamp : Double? = None
  let mut ex_labels : Array[(String, String)] = []
  let mut ex_value : Double? = None
  let mut ex_timestamp : Double? = None
  match c.peek() {
    Some('#') => {
      c.bump()
      c.skip_space()
      ex_labels = parse_labels(c)
      c.skip_space()
      let t = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
      ex_value = parse_float(t)
      c.skip_space()
      if !c.at_end() {
        let ts = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
        ex_timestamp = parse_float(ts)
      }
    }
    Some(_) => {
      let t = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
      timestamp = parse_float(t)
      c.skip_space()
      match c.peek() {
        Some('#') => {
          c.bump()
          c.skip_space()
          ex_labels = parse_labels(c)
          c.skip_space()
          let v = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
          ex_value = parse_float(v)
          c.skip_space()
          if !c.at_end() {
            let ts = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
            ex_timestamp = parse_float(ts)
          }
        }
        _ => ()
      }
    }
    None => ()
  }
  { name, labels, value, timestamp, ex_labels, ex_value, ex_timestamp, }
}

///|
priv struct Staged {
  name : String
  mut kind : @metric.Kind?
  help : String
  mut unit : String?
  samples : Array[RawSample]
}

///|
fn strip_prefix(s : String, prefix : String) -> String? {
  if s.length() >= prefix.length() && s[0:prefix.length()].to_owned() == prefix {
    Some(s[prefix.length():].to_owned())
  } else {
    None
  }
}

///|
fn strip_suffix(s : String, suffix : String) -> String? {
  if s.length() >= suffix.length() &&
    s[s.length() - suffix.length():].to_owned() == suffix {
    Some(s[0:s.length() - suffix.length()].to_owned())
  } else {
    None
  }
}

///|
fn unescape_help(s : String) -> String {
  let sb = StringBuilder()
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\\' && i + 1 < chars.length() {
      let n = chars[i + 1]
      if n == '\\' {
        sb.write_char('\\')
        i = i + 2
      } else if n == 'n' {
        sb.write_char('\n')
        i = i + 2
      } else if n == '"' {
        sb.write_char('"')
        i = i + 2
      } else {
        sb.write_char(chars[i])
        i = i + 1
      }
    } else {
      sb.write_char(chars[i])
      i = i + 1
    }
  }
  sb.to_string()
}

///|
fn label_key(labels : Array[(String, String)]) -> String {
  let sorted : Array[(String, String)] = []
  for p in labels {
    sorted.push(p)
  }
  sorted.sort_by(fn(a, b) { String::lexical_compare(a.0, b.0) })
  let sb = StringBuilder()
  for p in sorted {
    sb.write_string(p.0.length().to_string())
    sb.write_char(':')
    sb.write_string(p.0)
    sb.write_string(p.1.length().to_string())
    sb.write_char(':')
    sb.write_string(p.1)
  }
  sb.to_string()
}

///|
priv struct Group {
  labels : Array[(String, String)]
  mut number : Double?
  mut sum : Double?
  mut count : Double?
  mut created : Double?
  buckets : Array[(Double, Double)]
  quantiles : Array[(Double, Double)]
  states : Array[(String, Bool)]
  exemplars : Array[@metric.Exemplar]
}

///|
fn group_for(
  groups : Map[String, Group],
  labels : Array[(String, String)],
) -> Group {
  let key = label_key(labels)
  match groups.get(key) {
    Some(g) => g
    None => {
      let g : Group = {
        labels,
        number: None,
        sum: None,
        count: None,
        created: None,
        buckets: [],
        quantiles: [],
        states: [],
        exemplars: [],
      }
      groups[key] = g
      g
    }
  }
}

///|
fn sort_buckets(buckets : Array[(Double, Double)]) -> Array[(Double, Double)] {
  let out : Array[(Double, Double)] = []
  for b in buckets {
    out.push(b)
  }
  out.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  out
}

///|
fn finish_counter(staged : Staged) -> @metric.MetricFamily {
  let kind = @metric.Kind::Counter
  let base = match strip_suffix(staged.name, "_total") {
    Some(b) => b
    None => staged.name
  }
  let groups : Map[String, Group] = Map([])
  for s in staged.samples {
    if s.name == base + "_total" {
      let g = group_for(groups, s.labels)
      g.number = Some(s.value)
      match s.ex_value {
        Some(v) =>
          g.exemplars.push({
            labels: s.ex_labels,
            value: v,
            timestamp: s.ex_timestamp,
          })
        None => ()
      }
    } else if s.name == base + "_created" {
      let g = group_for(groups, s.labels)
      g.created = Some(s.value)
    }
  }
  let points : Array[@metric.Point] = []
  for _, g in groups {
    points.push({
      labels: g.labels,
      value: @metric.Value::Number(g.number.unwrap_or(0.0)),
      timestamp: None,
      created: g.created,
      exemplars: g.exemplars,
    })
  }
  { name: base, kind, help: staged.help, unit: staged.unit, metrics: points, }
}

///|
fn finish_histogram(
  staged : Staged,
  kind : @metric.Kind,
) -> @metric.MetricFamily {
  let base = staged.name
  let (count_name, sum_name) = match kind {
    @metric.Kind::GaugeHistogram => ("_gcount", "_gsum")
    _ => ("_count", "_sum")
  }
  let groups : Map[String, Group] = Map([])
  for s in staged.samples {
    if s.name == base + "_bucket" {
      let mut le = 0.0
      let mut has_le = false
      let rest : Array[(String, String)] = []
      for p in s.labels {
        if p.0 == "le" {
          has_le = true
          match parse_float(p.1) {
            Some(v) => le = v
            None => ()
          }
        } else {
          rest.push(p)
        }
      }
      if has_le {
        let g = group_for(groups, rest)
        g.buckets.push((le, s.value))
        match s.ex_value {
          Some(v) =>
            g.exemplars.push({
              labels: s.ex_labels,
              value: v,
              timestamp: s.ex_timestamp,
            })
          None => ()
        }
      }
    } else if s.name == base + count_name {
      let g = group_for(groups, s.labels)
      g.count = Some(s.value)
    } else if s.name == base + sum_name {
      let g = group_for(groups, s.labels)
      g.sum = Some(s.value)
    } else if s.name == base + "_created" {
      let g = group_for(groups, s.labels)
      g.created = Some(s.value)
    }
  }
  let points : Array[@metric.Point] = []
  for _, g in groups {
    let sorted = sort_buckets(g.buckets)
    let finite : Array[(Double, Int64)] = []
    let mut last = 0.0
    for b in sorted {
      if b.0 != 1.0 / 0.0 {
        finite.push((b.0, b.1.to_int64()))
      }
      last = b.1
    }
    let total = match g.count {
      Some(c) => c.to_int64()
      None => last.to_int64()
    }
    points.push({
      labels: g.labels,
      value: @metric.Value::Buckets(
        buckets=finite,
        sum=g.sum.unwrap_or(0.0),
        count=total,
      ),
      timestamp: None,
      created: g.created,
      exemplars: g.exemplars,
    })
  }
  { name: base, kind, help: staged.help, unit: staged.unit, metrics: points, }
}

///|
fn finish_summary(staged : Staged) -> @metric.MetricFamily {
  let base = staged.name
  let groups : Map[String, Group] = Map([])
  for s in staged.samples {
    let mut has_quantile = false
    for p in s.labels {
      if p.0 == "quantile" {
        has_quantile = true
      }
    }
    if s.name == base && has_quantile {
      let mut q = 0.0
      let rest : Array[(String, String)] = []
      for p in s.labels {
        if p.0 == "quantile" {
          match parse_float(p.1) {
            Some(v) => q = v
            None => ()
          }
        } else {
          rest.push(p)
        }
      }
      let g = group_for(groups, rest)
      g.quantiles.push((q, s.value))
    } else if s.name == base + "_count" {
      let g = group_for(groups, s.labels)
      g.count = Some(s.value)
    } else if s.name == base + "_sum" {
      let g = group_for(groups, s.labels)
      g.sum = Some(s.value)
    } else if s.name == base + "_created" {
      let g = group_for(groups, s.labels)
      g.created = Some(s.value)
    }
  }
  let points : Array[@metric.Point] = []
  for _, g in groups {
    let qs : Array[(Double, Double)] = []
    for q in g.quantiles {
      qs.push(q)
    }
    qs.sort_by(fn(a, b) {
      if a.0 < b.0 {
        -1
      } else if a.0 > b.0 {
        1
      } else {
        0
      }
    })
    points.push({
      labels: g.labels,
      value: @metric.Value::Quantiles(
        quantiles=qs,
        sum=g.sum.unwrap_or(0.0),
        count=g.count.unwrap_or(0.0).to_int64(),
      ),
      timestamp: None,
      created: g.created,
      exemplars: [],
    })
  }
  {
    name: base,
    kind: @metric.Kind::Summary,
    help: staged.help,
    unit: staged.unit,
    metrics: points,
  }
}

///|
fn finish_info(staged : Staged) -> @metric.MetricFamily {
  let mut om_style = false
  for s in staged.samples {
    if s.name == staged.name + "_info" {
      om_style = true
    }
  }
  let base = if om_style {
    staged.name
  } else {
    match strip_suffix(staged.name, "_info") {
      Some(b) => b
      None => staged.name
    }
  }
  let points : Array[@metric.Point] = []
  for s in staged.samples {
    points.push({
      labels: s.labels,
      value: @metric.Value::Number(1.0),
      timestamp: s.timestamp,
      created: None,
      exemplars: [],
    })
  }
  {
    name: base,
    kind: @metric.Kind::Info,
    help: staged.help,
    unit: staged.unit,
    metrics: points,
  }
}

///|
fn finish_stateset(staged : Staged) -> @metric.MetricFamily {
  let base = staged.name
  let groups : Map[String, Group] = Map([])
  for s in staged.samples {
    let mut state = ""
    let rest : Array[(String, String)] = []
    for p in s.labels {
      if p.0 == base {
        state = p.1
      } else {
        rest.push(p)
      }
    }
    let g = group_for(groups, rest)
    g.states.push((state, s.value != 0.0))
  }
  let points : Array[@metric.Point] = []
  for _, g in groups {
    points.push({
      labels: g.labels,
      value: @metric.Value::State(states=g.states),
      timestamp: None,
      created: None,
      exemplars: [],
    })
  }
  {
    name: base,
    kind: @metric.Kind::StateSet,
    help: staged.help,
    unit: staged.unit,
    metrics: points,
  }
}

///|
fn finish_plain(staged : Staged, kind : @metric.Kind) -> @metric.MetricFamily {
  let points : Array[@metric.Point] = []
  for s in staged.samples {
    if s.name == staged.name {
      points.push({
        labels: s.labels,
        value: @metric.Value::Number(s.value),
        timestamp: s.timestamp,
        created: None,
        exemplars: [],
      })
    }
  }
  {
    name: staged.name,
    kind,
    help: staged.help,
    unit: staged.unit,
    metrics: points,
  }
}

///|
fn finish(staged : Staged) -> @metric.MetricFamily {
  match staged.kind {
    Some(@metric.Kind::Counter) => finish_counter(staged)
    Some(@metric.Kind::Histogram) =>
      finish_histogram(staged, @metric.Kind::Histogram)
    Some(@metric.Kind::GaugeHistogram) =>
      finish_histogram(staged, @metric.Kind::GaugeHistogram)
    Some(@metric.Kind::Summary) => finish_summary(staged)
    Some(@metric.Kind::Info) => finish_info(staged)
    Some(@metric.Kind::StateSet) => finish_stateset(staged)
    Some(k) => finish_plain(staged, k)
    None => finish_plain(staged, @metric.Kind::Unknown)
  }
}

///|
/// Parse an exposition back into families. The compatibility format is lossy for
/// info and state sets, which it spells as gauges; OpenMetrics keeps them. The
/// format argument selects which spelling conventions to expect, and the same
/// parser accepts both because the syntax is a superset.
pub fn parse(
  text : String,
  format~ : Format = Format::Text004,
) -> Array[@metric.MetricFamily] raise @metric.Refused {
  let _ = format
  let out : Array[@metric.MetricFamily] = []
  let mut current : Staged? = None
  for raw_line in text.split("\n") {
    let line = raw_line.to_owned()
    let line = if line.length() > 0 && line[line.length() - 1] == '\r' {
      line[0:line.length() - 1].to_owned()
    } else {
      line
    }
    if line == "" {
      continue
    }
    match strip_prefix(line, "# HELP ") {
      Some(rest) => {
        let c = Cursor::new(rest)
        let name = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
        c.skip_space()
        let help = c.take_until(fn(_ch) { false })
        match current {
          Some(staged) => out.push(finish(staged))
          None => ()
        }
        current = Some({
          name,
          kind: None,
          help: unescape_help(help),
          unit: None,
          samples: [],
        })
        continue
      }
      None => ()
    }
    match strip_prefix(line, "# TYPE ") {
      Some(rest) => {
        let c = Cursor::new(rest)
        let name = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
        c.skip_space()
        let spelling = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
        let kind = @metric.Kind::of(spelling)
        match current {
          Some(staged) =>
            if staged.name == name {
              staged.kind = Some(kind)
            } else {
              out.push(finish(staged))
              current = Some({
                name,
                kind: Some(kind),
                help: "",
                unit: None,
                samples: [],
              })
            }
          None =>
            current = Some({
              name,
              kind: Some(kind),
              help: "",
              unit: None,
              samples: [],
            })
        }
        continue
      }
      None => ()
    }
    match strip_prefix(line, "# UNIT ") {
      Some(rest) => {
        let c = Cursor::new(rest)
        let name = c.take_until(fn(ch) { ch == ' ' || ch == '\t' })
        c.skip_space()
        let unit = c.take_until(fn(_ch) { false })
        match current {
          Some(staged) => if staged.name == name { staged.unit = Some(unit) }
          None => ()
        }
        continue
      }
      None => ()
    }
    if line == "# EOF" {
      break
    }
    if strip_prefix(line, "#") is Some(_) {
      continue
    }
    let sample = parse_sample(line)
    match current {
      Some(staged) => staged.samples.push(sample)
      None =>
        current = Some({
          name: sample.name,
          kind: None,
          help: "",
          unit: None,
          samples: [sample],
        })
    }
  }
  match current {
    Some(staged) => out.push(finish(staged))
    None => ()
  }
  out
}
