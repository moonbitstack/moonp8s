// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How the values of one gauge from several processes become one series.
///
/// A gauge has no natural merge — a counter can be added up, a bucket can be
/// added up, but "requests in flight" from three workers is a policy decision.
/// `All` and `LiveAll` keep the processes apart, one series each, labelled
/// `pid`; the other four collapse them: the smallest, the largest, the sum, or
/// the value set most recently.
///
/// The `Live` spellings mean the same thing at a scrape. They decide what
/// happens when a process exits: `mark_dead` removes the files of a live mode,
/// and leaves the others, which is what makes a handful of gauges forget a dead
/// worker instead of keeping its last value forever.
pub(all) enum Mode {
  All
  LiveAll
  Min
  LiveMin
  Max
  LiveMax
  Sum
  LiveSum
  MostRecent
  LiveMostRecent
}

///|
/// The spelling a file name carries: `all`, `liveall`, `min`, `livemin`, `max`,
/// `livemax`, `sum`, `livesum`, `mostrecent`, `livemostrecent`.
pub fn Mode::code(self : Mode) -> String {
  match self {
    Mode::All => "all"
    Mode::LiveAll => "liveall"
    Mode::Min => "min"
    Mode::LiveMin => "livemin"
    Mode::Max => "max"
    Mode::LiveMax => "livemax"
    Mode::Sum => "sum"
    Mode::LiveSum => "livesum"
    Mode::MostRecent => "mostrecent"
    Mode::LiveMostRecent => "livemostrecent"
  }
}

///|
/// The mode a file name spells. An unknown spelling is refused: it would change
/// what the numbers mean, which is worse than a failed scrape.
pub fn Mode::of(code : String) -> Mode raise @metric.Refused {
  match code {
    "all" => Mode::All
    "liveall" => Mode::LiveAll
    "min" => Mode::Min
    "livemin" => Mode::LiveMin
    "max" => Mode::Max
    "livemax" => Mode::LiveMax
    "sum" => Mode::Sum
    "livesum" => Mode::LiveSum
    "mostrecent" => Mode::MostRecent
    "livemostrecent" => Mode::LiveMostRecent
    _ => raise @metric.Refused("unknown gauge multiprocess mode: " + code)
  }
}

///|
/// Whether this mode forgets a process when it exits. `mark_dead` removes the
/// files of these modes only.
pub fn Mode::is_live(self : Mode) -> Bool {
  match self {
    Mode::LiveAll
    | Mode::LiveMin
    | Mode::LiveMax
    | Mode::LiveSum
    | Mode::LiveMostRecent => true
    _ => false
  }
}

///|
/// Whether this mode keeps the processes apart, one series per `pid`.
pub fn Mode::is_separate(self : Mode) -> Bool {
  match self {
    Mode::All | Mode::LiveAll => true
    _ => false
  }
}

///|
/// Whether this mode keeps the value set most recently instead of combining
/// values, which is why a most-recent gauge cannot be stepped with `inc`.
pub fn Mode::is_most_recent(self : Mode) -> Bool {
  match self {
    Mode::MostRecent | Mode::LiveMostRecent => true
    _ => false
  }
}
