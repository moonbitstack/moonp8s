// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `#p8s.counter` and `#p8s.timed` on a free function, turned into `<name>_metered`, which counts
/// and times the call, a metric for each annotation, and `register_metrics`, which puts them all in
/// a registry. The function itself is not touched, since a generator can only add code.
priv struct Metrics {}

///|
impl @gen.Generator for Metrics with fn name(_) {
  "moonp8s metrics"
}

///|
let counter_spec : @attr.Spec = @attr.Spec::new("p8s.counter")
  .positional("name", Str)
  .required("help", Str)
  .optional("on", Ident)

///|
let timed_spec : @attr.Spec = @attr.Spec::new("p8s.timed")
  .positional("name", Str)
  .required("help", Str)
  .optional("buckets", Str)

///|
fn at(attr : @attribute.Attribute, file : String) -> String {
  "\{file}:\{attr.loc.start.lnum}:\{attr.loc.start.column()}"
}

///|
/// When a counter moves: on every call, on a call that returned, or on one that raised.
priv enum On {
  Call
  Done
  Raised
}

///|
priv enum Meter {
  Counter(name~ : String, help~ : String, on~ : On)
  Timed(name~ : String, help~ : String, buckets~ : String?)
}

///|
fn Meter::name(self : Meter) -> String {
  match self {
    Counter(name~, ..) | Timed(name~, ..) => name
  }
}

///|
/// A bucket list such as `0.01,0.1,1`, as the array literal it becomes. Checked here, because the
/// metric is a top-level `let` and a bad list would otherwise only show when the program starts.
fn buckets_of(text : String, where_ : String) -> String raise {
  let values = []
  for part in text.split(",") {
    let value = @string.parse_double(part.trim(chars=" ")) catch {
      _ => fail("\{where_}: `\{part}` in `buckets` is not a number")
    }
    if values.last() is Some(previous) && value <= previous {
      fail("\{where_}: `buckets` go up, and `\{part}` does not")
    }
    values.push(value)
  }
  guard values is [_, ..] else { fail("\{where_}: `buckets` is empty") }
  let literal = (v : Double) => {
    let text = "\{v}"
    if text.contains(".") || text.contains("e") {
      text
    } else {
      text + ".0"
    }
  }
  "[" + values.map(literal).join(", ") + "]"
}

///|
fn meter_of(attr : @attribute.Attribute, file : String) -> Meter raise {
  let where_ = at(attr, file)
  guard @attr.name_of(attr) is Some(kind) else { fail("\{where_}: unnamed") }
  let checked = (name : String) => {
    if !@metric.is_valid_metric_name(name) {
      fail("\{where_}: `\{name}` is not a metric name")
    }
    name
  }
  match kind {
    "p8s.counter" => {
      let args = counter_spec.bind(attr)
      let on = match args.get("on") {
        [] => Call
        [Ident("call")] => Call
        [Ident("done")] => Done
        [Ident("raised")] => Raised
        _ => fail("\{where_}: `on` is call, done or raised")
      }
      Counter(
        name=checked(args.str("name").unwrap_or("")),
        help=args.str("help").unwrap_or(""),
        on~,
      )
    }
    "p8s.timed" => {
      let args = timed_spec.bind(attr)
      Timed(
        name=checked(args.str("name").unwrap_or("")),
        help=args.str("help").unwrap_or(""),
        buckets=args.str("buckets").map(text => buckets_of(text, where_)),
      )
    }
    _ => fail("\{where_}: `\{attr.raw}` is not a moonp8s annotation")
  }
}

///|
/// The top-level `let` a metric lives in.
fn holder(meter : Meter, public : Bool) -> String {
  let vis = if public { "pub " } else { "" }
  match meter {
    Counter(name~, ..) =>
      "\{vis}let \{name} : @moonp8s.Counter = @moonp8s.Counter::new()"
    Timed(name~, buckets=None, ..) =>
      "\{vis}let \{name} : @moonp8s.Histogram = @moonp8s.Histogram::new() catch { _ => abort(\"\{name}\") }"
    Timed(name~, buckets=Some(list), ..) =>
      "\{vis}let \{name} : @moonp8s.Histogram = @moonp8s.Histogram::new(buckets=\{list}) catch { _ => abort(\"\{name}\") }"
  }
}

///|
/// One count. `inc` raises only for a negative amount, and this is not one.
fn counted(metric : String) -> String {
  "\{metric}.inc() catch { _ => () }"
}

///|
/// The wrapper of one annotated function.
fn wrapper(
  meters : Array[Meter],
  name : String,
  params : Array[@gen.Param],
  returns : String?,
  is_async : Bool,
  public : Bool,
  raises : String,
  where_ : String,
) -> String raise {
  let declared = []
  let passed = []
  for param in params {
    guard param.declared() is Some(d) && param.passed() is Some(p) else {
      fail(
        "\{where_}: the arguments of a metered function are passed on, so they are named and typed",
      )
    }
    declared.push(d)
    passed.push(p)
  }
  let raising = raises != ""
  let clocked = meters.iter().any(m => m is Timed(..))
  if clocked {
    declared.push("now~ : () -> Double")
  }
  let before = []
  let after = []
  let failed = []
  if clocked {
    before.push("let started = now()")
  }
  for meter in meters {
    match meter {
      Counter(name=metric, on=Call, ..) => before.push(counted(metric))
      Counter(name=metric, on=Done, ..) => after.push(counted(metric))
      Counter(name=metric, on=Raised, ..) => {
        if !raising {
          fail(
            "\{where_}: `\{name}` does not raise, so `on=raised` never counts",
          )
        }
        failed.push(counted(metric))
      }
      Timed(name=metric, ..) => {
        after.push("\{metric}.observe(now() - started)")
        if raising {
          failed.push("\{metric}.observe(now() - started)")
        }
      }
    }
  }
  // errdefer, not catch: a cancelled call leaves through here as well, and catch will not see it.
  if failed is [_, ..] {
    before.push("errdefer {\n    \{failed.join("\n    ")}\n  }")
  }
  let vis = if public { "pub " } else { "" }
  let run = if is_async { "async " } else { "" }
  let result = returns.unwrap_or("Unit")
  let tail = if raising { " \{raises}" } else { "" }
  (
    $|\{vis}\{run}fn \{name}_metered(\{declared.join(", ")}) -> \{result}\{tail} {
    $|  \{before.join("\n  ")}
    $|  let result = \{name}(\{passed.join(", ")})
    $|  \{after.join("\n  ")}
    $|  result
    $|}
  )
}

///|
impl @gen.Generator for Metrics with fn generate(_, decls) {
  let holders = []
  let wrappers = []
  let registered = []
  let seen : Set[String] = Set([])
  let mut any_public = false
  for decl in decls {
    match decl {
      Func(
        owner~,
        name~,
        params~,
        returns~,
        is_async~,
        attrs~,
        public~,
        file~,
        ..
      ) => {
        for attr in @attr.malformed(attrs, "p8s") {
          fail(
            "\{at(attr, file)}: `\{attr.raw}` does not parse as an annotation",
          )
        }
        let found = @attr.under(attrs, "p8s")
        guard found is [first, ..] else { continue }
        if owner is Some(_) {
          fail("\{at(first, file)}: `#p8s.*` goes on a free function")
        }
        let meters = []
        for attr in found {
          let meter = meter_of(attr, file)
          if !seen.add_and_check(meter.name()) {
            fail(
              "\{at(attr, file)}: the metric `\{meter.name()}` is declared twice",
            )
          }
          holders.push(holder(meter, public))
          registered.push(meter)
          meters.push(meter)
        }
        any_public = any_public || public
        wrappers.push(
          wrapper(
            meters,
            name,
            params,
            returns,
            is_async,
            public,
            decl.raises(),
            at(first, file),
          ),
        )
      }
      Struct(attrs~, file~, ..) | Enum(attrs~, file~, ..) =>
        if @attr.under(attrs, "p8s") is [first, ..] {
          fail("\{at(first, file)}: `#p8s.*` goes on a free function")
        }
      Other(..) => ()
    }
  }
  guard wrappers is [_, ..] else { return @quote.items("").render() }
  let vis = if any_public { "pub " } else { "" }
  let lines = registered.map(meter => {
    match meter {
      Counter(name~, help~, ..) | Timed(name~, help~, ..) =>
        "registry.register(\{@quote.string(name)}, \{@quote.string(help)}, \{name})"
    }
  })
  let register =
    $|\{vis}fn register_metrics(registry : @moonp8s.Registry) -> Unit raise @metric.Refused {
    $|  \{lines.join("\n  ")}
    $|}
  let parts = [..holders, register, ..wrappers]
  @quote.items(parts.join("\n\n")).render()
}
