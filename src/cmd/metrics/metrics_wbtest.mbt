// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn flat(code : String) -> String {
  let out = StringBuilder()
  for c in code {
    if c != ' ' && c != '\n' {
      out.write_char(c)
    }
  }
  out.to_string().replace_all(old=",)", new=")").replace_all(old=",]", new="]")
}

///|
fn generate(source : String) -> String raise {
  flat(@gen.render(Metrics::{ }, [("m.mbt", source)]))
}

///|
fn refused(source : String) -> String {
  try {
    ignore(generate(source))
    ""
  } catch {
    e => "\{e}"
  }
}

///|
test "a counter counts every call, and needs no clock" {
  let code = generate(
    "#p8s.counter(\"orders_total\", help=\"Orders.\")\npub fn place(id : Int) -> Int {\n  id\n}",
  )
  assert_true(
    code.contains(
      flat("pub let orders_total : @moonp8s.Counter = @moonp8s.Counter::new()"),
    ),
  )
  assert_true(code.contains(flat("pub fn place_metered(id : Int) -> Int")))
  assert_true(code.contains(flat("orders_total.inc()")))
  assert_true(code.contains(flat("let result = place(id)")))
  assert_true(
    code.contains(
      flat("registry.register(\"orders_total\", \"Orders.\", orders_total)"),
    ),
  )
  assert_false(code.contains("now~"))
}

///|
test "a timed function takes a clock and observes on both ways out" {
  let code = generate(
    "#p8s.timed(\"place_seconds\", help=\"Time.\", buckets=\"0.1, 1\")\npub async fn place(id : Int, tag~ : String, note? : String, retries~ : Int = 3) -> Int raise @a.Bad {\n  id\n}",
  )
  assert_true(
    code.contains(
      flat(
        "pub async fn place_metered(id : Int, tag~ : String, note? : String, retries? : Int, now~ : () -> Double) -> Int raise @a.Bad",
      ),
    ),
  )
  assert_true(code.contains(flat("place(id, tag~, note?, retries?)")))
  assert_true(code.contains(flat("buckets=[0.1, 1.0]")))
  // Once where it returned, and once where it raised.
  assert_eq(
    code.split(flat("place_seconds.observe(now() - started)")).count(),
    3,
  )
}

///|
test "counters move on a call, on a return, or on a raise" {
  let code = generate(
    "#p8s.counter(\"a_total\", help=\"a\")\n#p8s.counter(\"b_total\", help=\"b\", on=done)\n#p8s.counter(\"c_total\", help=\"c\", on=raised)\nfn f() -> Int raise {\n  1\n}",
  )
  let call = code.find("a_total.inc()").unwrap()
  let run = code.find(flat("let result = f()")).unwrap()
  let raised = code.find("c_total.inc()").unwrap()
  let done = code.find("b_total.inc()").unwrap()
  assert_true(call < raised)
  assert_true(code.contains("errdefer"))
  assert_true(raised < run)
  assert_true(run < done)
}

///|
test "what cannot work is refused where it is written" {
  assert_true(
    refused("#p8s.counter(\"0bad\", help=\"h\")\nfn f() -> Int {\n  1\n}").contains(
      "not a metric name",
    ),
  )
  assert_true(
    refused(
      "#p8s.timed(\"t\", help=\"h\", buckets=\"1, 0.5\")\nfn f() -> Int {\n  1\n}",
    ).contains("go up"),
  )
  assert_true(
    refused(
      "#p8s.timed(\"t\", help=\"h\", buckets=\"x\")\nfn f() -> Int {\n  1\n}",
    ).contains("not a number"),
  )
  assert_true(
    refused(
      "#p8s.counter(\"t\", help=\"h\", on=raised)\nfn f() -> Int {\n  1\n}",
    ).contains("does not raise"),
  )
  assert_true(
    refused(
      "#p8s.counter(\"t\", help=\"h\", on=sometimes)\nfn f() -> Int {\n  1\n}",
    ).contains("`on` is"),
  )
  assert_true(
    refused(
      "#p8s.counter(\"t\", help=\"h\")\n#p8s.counter(\"t\", help=\"h\")\nfn f() -> Int {\n  1\n}",
    ).contains("declared twice"),
  )
  assert_true(
    refused("#p8s.gauge(\"t\", help=\"h\")\nfn f() -> Int {\n  1\n}").contains(
      "not a moonp8s annotation",
    ),
  )
  assert_true(
    refused(
      "#p8s.counter(\"t\", help=\"h\")\nfn T::f(self : T) -> Int {\n  1\n}",
    ).contains("free function"),
  )
  assert_true(
    refused("#p8s.counter(\"t\", help=\"h\")\nstruct S {\n  x : Int\n}").contains(
      "free function",
    ),
  )
  assert_true(
    refused("#p8s.counter(type=\"t\")\nfn f() -> Int {\n  1\n}").contains(
      "does not parse",
    ),
  )
  assert_true(
    refused("#p8s.counter(\"t\", help=\"h\")\nfn f(_ : Int) -> Int {\n  1\n}").contains(
      "named and typed",
    ),
  )
}

///|
test "a file with no annotation writes nothing" {
  assert_eq(
    generate("fn f() -> Int {\n  1\n}").contains("register_metrics"),
    false,
  )
}
