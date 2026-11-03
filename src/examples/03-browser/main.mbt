// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Runs this library for the picture the front plate draws, and leaves the result
/// where the page can read it.
///
/// Nothing on the page is counted by the page: a fifteen-second window of latency
/// samples is handed to a `Histogram`, the histogram is read back through the same
/// snapshot the exposition is written from, and the page only lays it out. The
/// numbers in the field, in the bars, and in the specimen are therefore the numbers
/// this library produced — not a table typed into a script.
///
///     moon build --target js src/examples/03-browser
extern "js" fn publish(text : String) -> Unit =
  #|(text) => { globalThis.moonp8s = JSON.parse(text) }

///|
/// The window the plate draws, in seconds. A scrape every fifteen seconds is the
/// default the Prometheus documentation uses, and the bucket edges are the ones the
/// official clients share.
let window_seconds : Int32 = 15

///|
/// The 100 ms budget the plate measures against. Nothing in the library knows about
/// it: it is the reader's threshold, applied to the counters the library kept.
let budget_seconds : Double = 0.1

///|
/// The fixed moment the window starts. A clock would make the artwork different on
/// every visit, and there is nothing here that a clock would tell the reader.
let window_start : Double = 1700000000.0

///|
/// How many samples arrived in each second. The shape is the point: a quiet first
/// half, a burst around nine seconds, then a tail. Sum is 1,027 — the number the
/// plate prints.
let arrivals : Array[Int32] = [
  41, 46, 43, 49, 53, 56, 59, 63, 67, 125, 135, 112, 69, 59, 50,
]

///|
/// The latency distribution, as quantiles of one service under load: a long body
/// between four and forty milliseconds, and a tail that reaches a second. The
/// generator reads this curve rather than drawing from a distribution, so the same
/// window comes out the same on every visit and in every browser.
let curve : Array[Double] = [
  0.0060, 0.0080, 0.0100, 0.0120, 0.0140, 0.0160, 0.0190, 0.0220, 0.0250, 0.0290,
  0.0330, 0.0380, 0.0440, 0.0510, 0.0590, 0.0680, 0.0790, 0.0920, 0.1080, 0.1300,
  0.1600, 0.2000, 0.2600, 0.3600, 0.5600, 1.2000,
]

///|
/// A counter that walks a fixed sequence: one state word, multiplied and shifted.
/// Deterministic on purpose — the plate is an instrument, not a dice cup.
fn step(state : Ref[UInt64]) -> Double {
  state.val = state.val * 6364136223846793005UL + 1442695040888963407UL
  // The top 53 bits are the ones a double can hold without rounding.
  (state.val >> 11).to_double() / 9007199254740992.0
}

///|
/// A latency at the quantile `u`, read off the curve by linear interpolation. `heat`
/// is how busy the second is, from 0 to 1; a busier second is a little slower, which
/// is what makes the field in the plate lean to the right at the burst.
fn latency_at(u : Double, heat : Double) -> Double {
  let span = (curve.length() - 1).to_double()
  let at = u * span
  let low = at.to_int()
  let index = if low < 0 {
    0
  } else if low >= curve.length() - 1 {
    curve.length() - 2
  } else {
    low
  }
  let fraction = at - index.to_double()
  let base = curve[index] + (curve[index + 1] - curve[index]) * fraction
  base * (1.0 + 0.14 * heat)
}

///|
/// The window, as the library holds it: one histogram for the whole window and one
/// per second, so the plate can show both the field and its fold.
struct Window {
  all : @metric.Histogram
  per_second : Array[@metric.Histogram]
  counter : @metric.Counter
}

///|
/// Feed the window. Every sample goes to the window histogram, to its own second's
/// histogram, and to the counter — three readings of one arrival.
fn build_window() -> Window raise @metric.Refused {
  let all = @metric.Histogram::new(created=window_start)
  let counter = @metric.Counter::new(created=window_start)
  let per_second : Array[@metric.Histogram] = []
  for _s = 0; _s < window_seconds; _s = _s + 1 {
    per_second.push(@metric.Histogram::new(created=window_start))
  }
  let state = Ref(0xC0FFEEUL)
  let busiest = 135.0
  for second = 0; second < window_seconds; second = second + 1 {
    let count = arrivals[second]
    let heat = count.to_double() / busiest
    for _sample = 0; _sample < count; _sample = _sample + 1 {
      let value = latency_at(step(state), heat)
      all.observe(value)
      per_second[second].observe(value)
      counter.inc()
    }
  }
  { all, per_second, counter, }
}

///|
/// The exposition the scrape would receive. Built through `Registry`, so the family
/// order, the label order and the float spelling are the library's, not the page's.
fn build_registry(window : Window) -> @metric.Registry raise @metric.Refused {
  let registry = @metric.Registry::new()
  registry.register(
    "http_requests",
    "Requests the window counted.",
    window.counter,
  )
  registry.register(
    "http_request_duration_seconds",
    "Request latency over the window.",
    window.all,
  )
  registry
}

///|
/// One `Histogram` as its cumulative counts, which is what the exposition carries and
/// what the plate's fold draws. The population of a bucket — what the field's rows
/// hold — is the difference between two neighbours, taken on the page.
fn cumulative_json(histogram : @metric.Histogram) -> String {
  let point = histogram.snapshot()
  match point.value {
    @metric.Value::Buckets(buckets~, ..) => {
      let out : Array[String] = []
      for entry in buckets {
        out.push(entry.1.to_string())
      }
      "[" + out.join(",") + "]"
    }
    _ => "[]"
  }
}

///|
/// The bucket bounds, in the order the histogram keeps them.
fn bounds_json(histogram : @metric.Histogram) -> String {
  let point = histogram.snapshot()
  match point.value {
    @metric.Value::Buckets(buckets~, ..) => {
      let out : Array[String] = []
      for entry in buckets {
        out.push(@expo.format_float(entry.0))
      }
      out.join(",")
    }
    _ => ""
  }
}

///|
/// The count at or below `bound`, read off the snapshot rather than recomputed.
fn cumulative_at(histogram : @metric.Histogram, bound : Double) -> Int64 {
  let point = histogram.snapshot()
  match point.value {
    @metric.Value::Buckets(buckets~, ..) => {
      let mut found = 0L
      for entry in buckets {
        if entry.0 <= bound {
          found = entry.1
        }
      }
      found
    }
    _ => 0L
  }
}

///|
/// The exponent used for the median and the ninetieth percentile: a bucket bound, so
/// the page prints a bound the library itself declares rather than an interpolation
/// it made up.
fn bound_at(histogram : @metric.Histogram, fraction : Double) -> Double {
  let total = histogram.total().to_double()
  let point = histogram.snapshot()
  match point.value {
    @metric.Value::Buckets(buckets~, ..) => {
      let mut answer = 0.0
      let mut found = false
      for entry in buckets {
        if !found && entry.1.to_double() >= total * fraction {
          answer = entry.0
          found = true
        }
      }
      answer
    }
    _ => 0.0
  }
}

///|
/// The specimen: one line of the exposition, split into the four things a reader has
/// to be able to name — the metric, its labels, the value, the timestamp.
///
/// The line is taken from the exposition the encoder wrote; the fields are cut out of
/// that line, so the page cannot show a specimen the library did not produce.
pub(all) struct Specimen {
  line : String
  name : String
  labels : Array[(String, String)]
  value : String
  timestamp : String
}

///|
/// Cut the first line whose metric name is `name` into its parts. A label value here
/// is a bucket bound or a route, neither of which contains a space or a comma, so the
/// cut is the simple one; a specimen line with an escaped value would need the parser
/// in `expo`, and the reference page uses that instead.
fn specimen_of(exposition : String, name : String, label : String) -> Specimen {
  for raw in exposition.split("\n") {
    let line = raw.to_owned()
    if line.has_prefix(name + "{" + label + "}") {
      let cut = match line.find(" ") {
        Some(at) => at
        None => continue
      }
      let selector = line[0:cut].to_owned()
      let rest = line[cut + 1:].to_owned().trim().to_owned()
      let parts = rest.split(" ").collect()
      let value = if parts.length() > 0 { parts[0].to_owned() } else { "" }
      let timestamp = if parts.length() > 1 { parts[1].to_owned() } else { "" }
      let brace = match selector.find("{") {
        Some(at) => at
        None => selector.length()
      }
      let metric = selector[0:brace].to_owned()
      let labels : Array[(String, String)] = []
      if brace < selector.length() {
        let body = selector[brace + 1:selector.length() - 1].to_owned()
        for pair in body.split(",") {
          let equals = match pair.find("=") {
            Some(at) => at
            None => continue
          }
          let key = pair[0:equals].to_owned()
          let quoted = pair[equals + 1:].to_owned()
          let value_text = if quoted.length() >= 2 {
            quoted[1:quoted.length() - 1].to_owned()
          } else {
            quoted
          }
          labels.push((key, value_text))
        }
      }
      return { line, name: metric, labels, value, timestamp, }
    }
  }
  { line: "", name, labels: [], value: "", timestamp: "", }
}

///|
/// A string as a JSON string.
fn json_string(value : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in value {
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else if c == '\n' {
      out.write_string("\\n")
    } else if c == '\r' {
      out.write_string("\\r")
    } else if c == '\t' {
      out.write_string("\\t")
    } else {
      out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// The page's copy of the window.
fn specimen_json(specimen : Specimen) -> String {
  let labels : Array[String] = []
  for pair in specimen.labels {
    labels.push("[" + json_string(pair.0) + "," + json_string(pair.1) + "]")
  }
  "{" +
  "\"line\":" +
  json_string(specimen.line) +
  "," +
  "\"name\":" +
  json_string(specimen.name) +
  "," +
  "\"labels\":[" +
  labels.join(",") +
  "]," +
  "\"value\":" +
  json_string(specimen.value) +
  "," +
  "\"timestamp\":" +
  json_string(specimen.timestamp) +
  "}"
}

///|
fn window_json(
  window : Window,
  exposition : String,
  openmetrics : String,
) -> String {
  let seconds : Array[String] = []
  for histogram in window.per_second {
    seconds.push(cumulative_json(histogram))
  }
  let total = window.all.total()
  let inside = cumulative_at(window.all, budget_seconds)
  let bucket = "http_request_duration_seconds_bucket"
  let label = "le=\"" + @expo.format_float(budget_seconds) + "\""
  let specimen = specimen_of(exposition, bucket, label)
  let specimen_om = specimen_of(openmetrics, bucket, label)
  let out = StringBuilder()
  out.write_string("{")
  out.write_string("\"window\":" + window_seconds.to_string())
  out.write_string(",\"start\":" + @expo.format_float(window_start))
  out.write_string(",\"scrape\":127")
  out.write_string(",\"budget\":" + @expo.format_float(budget_seconds))
  out.write_string(",\"buckets\":[" + bounds_json(window.all) + "]")
  out.write_string(",\"seconds\":[" + seconds.join(",") + "]")
  out.write_string(",\"total\":" + total.to_string())
  out.write_string(",\"inside\":" + inside.to_string())
  out.write_string(",\"over\":" + (total - inside).to_string())
  out.write_string(
    ",\"median\":" + @expo.format_float(bound_at(window.all, 0.5)),
  )
  out.write_string(",\"p90\":" + @expo.format_float(bound_at(window.all, 0.9)))
  out.write_string(
    ",\"rate\":" +
    @expo.format_float(total.to_double() / window_seconds.to_double()),
  )
  out.write_string(",\"sum\":" + @expo.format_float(window.all.sum_value()))
  out.write_string(",\"exposition\":" + json_string(exposition))
  out.write_string(",\"openmetrics\":" + json_string(openmetrics))
  out.write_string(",\"specimen\":" + specimen_json(specimen))
  out.write_string(",\"specimen_om\":" + specimen_json(specimen_om))
  out.write_string("}")
  out.to_string()
}

///|
/// Build the window, write it as a scrape, and hand both to the page.
fn main {
  let window = build_window() catch {
    @metric.Refused(message) => {
      publish("{\"error\":" + json_string(message) + "}")
      return
    }
  }
  let registry = build_registry(window) catch {
    @metric.Refused(message) => {
      publish("{\"error\":" + json_string(message) + "}")
      return
    }
  }
  // The scrape happens at the end of the window, and the registry stamps every
  // sample that has no time of its own with that moment.
  let families = registry.collect(at=window_start + window_seconds.to_double())
  let exposition = @expo.text(families)
  let openmetrics = @expo.openmetrics(families)
  publish(window_json(window, exposition, openmetrics))
}
