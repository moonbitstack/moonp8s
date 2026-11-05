// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A record that can name its own label pairs. Implementing this for a struct
/// and using `TypedFamily` gives a family keyed by a typed label set instead of
/// an array of strings.
pub(open) trait LabelSet {
  fn pairs(Self) -> Array[(String, String)]
}

///|
fn key_of(values : Array[String]) -> String {
  let sb = StringBuilder()
  for v in values {
    sb.write_string(v.length().to_string())
    sb.write_char(':')
    sb.write_string(v)
  }
  sb.to_string()
}

///|
struct FamilyEntry[M] {
  values : Array[String]
  metric : M
}

///|
/// A family of metrics sharing one name and one fixed list of label names. The
/// label names are fixed at construction; `labels` gets or creates the child for
/// one combination of values.
pub struct Family[M] {
  priv names : Array[String]
  priv make : () -> M raise Refused
  priv mut children : Map[String, FamilyEntry[M]]
  priv cached_kind : Kind?
}

///|
/// A family over `names`, creating a child with `make` on first sight.
pub fn[M : Metric] Family::new(
  names : Array[String],
  make : () -> M raise Refused,
) -> Family[M] raise Refused {
  let probe = make()
  let kind = Metric::kind(probe)
  // These names are spent by the rendered sample: a histogram writes `le`, a
  // summary writes `quantile`, and a second label of that name would make the
  // line unreadable. Refused here, where the family's labels are decided.
  for i = 0; i < names.length(); i = i + 1 {
    check_label_name(names[i])
    for j = i + 1; j < names.length(); j = j + 1 {
      if names[i] == names[j] {
        raise Refused("a label name appears twice: " + names[i])
      }
    }
    match kind {
      Kind::Histogram | Kind::GaugeHistogram =>
        if names[i] == "le" {
          raise Refused("a histogram cannot have a label named le")
        }
      Kind::Summary =>
        if names[i] == "quantile" {
          raise Refused("a summary cannot have a label named quantile")
        }
      _ => ()
    }
  }
  { names, make, children: Map([]), cached_kind: Some(kind), }
}

///|
/// The child for `values`, created if this is the first time it is seen. A
/// value count that does not match the family's label names is refused.
pub fn[M] Family::labels(
  self : Family[M],
  values : Array[String],
) -> M raise Refused {
  if values.length() != self.names.length() {
    raise Refused(
      "expected " +
      self.names.length().to_string() +
      " label values, got " +
      values.length().to_string(),
    )
  }
  let key = key_of(values)
  match self.children.get(key) {
    Some(entry) => entry.metric
    None => {
      let metric = (self.make)()
      self.children[key] = { values, metric, }
      metric
    }
  }
}

///|
/// Drop the child for `values` if it exists.
pub fn[M] Family::remove(self : Family[M], values : Array[String]) -> Unit {
  self.children.remove(key_of(values))
}

///|
/// Drop every child.
pub fn[M] Family::clear(self : Family[M]) -> Unit {
  self.children = Map([])
}

///|
/// The number of children seen so far.
pub fn[M] Family::size(self : Family[M]) -> Int32 {
  self.children.length()
}

///|
pub impl[M : Metric] Metric for Family[M] with fn kind(self) {
  match self.cached_kind {
    Some(k) => k
    None => Kind::Unknown
  }
}

///|
pub impl[M : Metric] Metric for Family[M] with fn points(self) {
  let out : Array[Point] = []
  for _, entry in self.children {
    let pairs : Array[(String, String)] = []
    for i = 0; i < self.names.length(); i = i + 1 {
      pairs.push((self.names[i], entry.values[i]))
    }
    for p in Metric::points(entry.metric) {
      out.push({ ..p, labels: pairs + p.labels, })
    }
  }
  out
}

///|
pub extend Family with Metric::{kind, points}

///|
struct TypedChild[M] {
  pairs : Array[(String, String)]
  metric : M
}

///|
/// A family keyed by a typed label set. Use this instead of `Family` when the
/// label combination is better expressed as a record than as an array of
/// strings; the record must implement `LabelSet` and be hashable and comparable.
pub struct TypedFamily[L, M] {
  priv make : () -> M raise Refused
  priv mut children : Array[TypedChild[M]]
  priv mut index : Map[L, Int32]
  priv cached_kind : Kind?
}

///|
/// A typed family, creating a child with `make` on first sight.
pub fn[L : Hash + Eq, M : Metric] TypedFamily::new(
  make : () -> M raise Refused,
) -> TypedFamily[L, M] raise Refused {
  let probe = make()
  {
    make,
    children: [],
    index: Map([]),
    cached_kind: Some(Metric::kind(probe)),
  }
}

///|
/// The child for `labels`, created if this is the first time it is seen.
pub fn[L : Hash + Eq + LabelSet, M] TypedFamily::get(
  self : TypedFamily[L, M],
  labels : L,
) -> M raise Refused {
  match self.index.get(labels) {
    Some(i) => self.children[i].metric
    None => {
      let pairs = LabelSet::pairs(labels)
      let metric = (self.make)()
      let i = self.children.length()
      self.children.push({ pairs, metric, })
      self.index[labels] = i
      metric
    }
  }
}

///|
/// Drop the child for `labels` if it exists.
pub fn[L : Hash + Eq, M] TypedFamily::remove(
  self : TypedFamily[L, M],
  labels : L,
) -> Unit {
  match self.index.get(labels) {
    Some(i) => {
      ignore(self.children.remove(i))
      ignore(self.index.remove(labels))
      let rebuilt : Map[L, Int32] = Map([])
      for key, old in self.index {
        if old > i {
          rebuilt[key] = old - 1
        } else {
          rebuilt[key] = old
        }
      }
      self.index = rebuilt
    }
    None => ()
  }
}

///|
/// Drop every child.
pub fn[L : Hash + Eq, M] TypedFamily::clear(self : TypedFamily[L, M]) -> Unit {
  self.children = []
  self.index = Map([])
}

///|
/// The number of children seen so far.
pub fn[L, M] TypedFamily::size(self : TypedFamily[L, M]) -> Int32 {
  self.children.length()
}

///|
pub impl[L, M : Metric] Metric for TypedFamily[L, M] with fn kind(self) {
  match self.cached_kind {
    Some(k) => k
    None => Kind::Unknown
  }
}

///|
pub impl[L, M : Metric] Metric for TypedFamily[L, M] with fn points(self) {
  let out : Array[Point] = []
  for child in self.children {
    for p in Metric::points(child.metric) {
      out.push({ ..p, labels: child.pairs + p.labels, })
    }
  }
  out
}

///|
pub extend TypedFamily with Metric::{kind, points}
