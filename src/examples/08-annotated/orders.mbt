// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
suberror Sold {
  Sold(String)
}

///|
#p8s.counter("orders_total", help="Orders asked for.")
#p8s.counter("orders_refused_total", help="Orders refused.", on=raised)
#p8s.timed("order_seconds", help="Seconds to place an order.", buckets="0.5, 1, 5")
fn place(item : String) -> Int32 raise Sold {
  if item == "gold" {
    raise Sold(item)
  }
  item.length()
}
