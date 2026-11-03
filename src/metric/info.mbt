// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An info metric: a fixed set of labels whose value is always 1. It carries
/// build and version metadata, which is why it never changes after creation.
pub struct Info {
  priv labels : Array[(String, String)]
}

///|
/// An info metric with these labels.
pub fn Info::new(labels : Array[(String, String)]) -> Info raise Refused {
  for pair in labels {
    check_label_name(pair.0)
  }
  { labels, }
}

///|
/// The labels this info metric carries.
pub fn Info::labels(self : Info) -> Array[(String, String)] {
  self.labels
}

///|
pub impl Metric for Info with fn kind(_self) {
  Kind::Info
}

///|
pub impl Metric for Info with fn points(self) {
  [
    {
      labels: self.labels,
      value: Number(1.0),
      timestamp: None,
      created: None,
      exemplars: [],
    },
  ]
}

///|
pub extend Info with Metric::{kind, points}

///|
/// A set of named states, each true or false. A state set with exactly one true
/// state is the `Enum` of the Python client.
pub struct StateSet {
  priv states : Array[String]
  priv values : Map[String, Bool]
  priv mut exclusive : Bool
}

///|
/// A state set whose states all start false, in the order given.
pub fn StateSet::new(states : Array[String]) -> StateSet {
  let values : Map[String, Bool] = Map([])
  for s in states {
    values[s] = false
  }
  { states, values, exclusive: false, }
}

///|
/// A state set with exactly one state true: the first, which is the Python
/// client's default.
pub fn StateSet::exclusive(states : Array[String]) -> StateSet {
  let set = StateSet::new(states)
  set.exclusive = true
  if states.length() > 0 {
    set.values[states[0]] = true
  }
  set
}

///|
fn StateSet::remember(self : StateSet, state : String) -> Unit {
  let known = match self.values.get(state) {
    Some(_) => true
    None => false
  }
  if !known {
    self.states.push(state)
  }
}

///|
/// Set one state true, leaving the others as they are.
pub fn StateSet::set(self : StateSet, state : String) -> Unit {
  self.remember(state)
  if self.exclusive {
    for s in self.states {
      self.values[s] = false
    }
  }
  self.values[state] = true
}

///|
/// Set one state false.
pub fn StateSet::unset(self : StateSet, state : String) -> Unit {
  self.remember(state)
  self.values[state] = false
}

///|
/// Apply a whole map of states at once.
pub fn StateSet::set_many(self : StateSet, states : Map[String, Bool]) -> Unit {
  for name, value in states {
    self.remember(name)
    self.values[name] = value
  }
}

///|
/// Whether `state` is true.
pub fn StateSet::get(self : StateSet, state : String) -> Bool {
  self.values.get(state).unwrap_or(false)
}

///|
pub impl Metric for StateSet with fn kind(_self) {
  Kind::StateSet
}

///|
pub impl Metric for StateSet with fn points(self) {
  let states : Array[(String, Bool)] = []
  for s in self.states {
    states.push((s, self.values.get(s).unwrap_or(false)))
  }
  [
    {
      labels: [],
      value: State(states~),
      timestamp: None,
      created: None,
      exemplars: [],
    },
  ]
}

///|
pub extend StateSet with Metric::{kind, points}
