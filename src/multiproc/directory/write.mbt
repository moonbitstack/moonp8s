// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What one flush left behind: how many files it wrote, how many series they
/// hold, and the families it could not share between processes.
pub(all) struct Written {
  files : Int32
  entries : Int32
  /// Families of a kind that has no cross-process meaning — an info metric, a
  /// state set, a gauge histogram — left out by name rather than dropped
  /// quietly.
  skipped : Array[String]
}

///|
fn mode_for(
  modes : Array[(String, @multiproc.Mode)],
  name : String,
) -> @multiproc.Mode {
  for pair in modes {
    if pair.0 == name {
      return pair.1
    }
  }
  @multiproc.Mode::All
}

///|
fn check_modes(
  modes : Array[(String, @multiproc.Mode)],
  families : Array[@metric.MetricFamily],
) -> Unit raise @metric.Refused {
  for i = 0; i < modes.length(); i = i + 1 {
    for j = i + 1; j < modes.length(); j = j + 1 {
      if modes[i].0 == modes[j].0 {
        raise @metric.Refused("a gauge mode is given twice for " + modes[i].0)
      }
    }
    let mut found = false
    for family in families {
      if family.name == modes[i].0 {
        found = true
        if !(family.kind is @metric.Kind::Gauge) {
          raise @metric.Refused(
            "a gauge mode is given for " +
            modes[i].0 +
            ", which is a " +
            family.kind.code(),
          )
        }
      }
    }
    if !found {
      raise @metric.Refused(
        "a gauge mode is given for a family that is not here: " + modes[i].0,
      )
    }
  }
}

///|
fn stamp_of(point : @metric.Point) -> Double {
  match point.timestamp {
    Some(t) => t
    None => 0.0
  }
}

///|
fn number_of(
  point : @metric.Point,
  name : String,
) -> Double raise @metric.Refused {
  match point.value {
    @metric.Value::Number(v) => v
    _ =>
      raise @metric.Refused(
        name + " is not a single number, so it has no place in a worker's file",
      )
  }
}

///|
fn bucket_entry(
  family : @metric.MetricFamily,
  point : @metric.Point,
  le : String,
  value : Double,
) -> @multiproc.Entry {
  @multiproc.Entry::new(
    family.name,
    family.name + "_bucket",
    point.labels + [("le", le)],
    family.help,
    value,
    timestamp=stamp_of(point),
  )
}

///|
fn sum_entry(
  family : @metric.MetricFamily,
  point : @metric.Point,
  sum : Double,
) -> @multiproc.Entry {
  @multiproc.Entry::new(
    family.name,
    family.name + "_sum",
    point.labels,
    family.help,
    sum,
    timestamp=stamp_of(point),
  )
}

///|
fn count_entry(
  family : @metric.MetricFamily,
  point : @metric.Point,
  count : Int64,
) -> @multiproc.Entry {
  @multiproc.Entry::new(
    family.name,
    family.name + "_count",
    point.labels,
    family.help,
    count.to_double(),
    timestamp=stamp_of(point),
  )
}

///|
/// One family's values in the shape a worker's file holds them: a counter as its
/// total, a histogram as the count in each bucket rather than the cumulative
/// count (a reader adds them up again, so a process is never counted twice), a
/// summary as count and sum.
fn part_of(
  family : @metric.MetricFamily,
  mode : @multiproc.Mode,
  pid : String,
) -> @multiproc.Part raise @metric.Refused {
  let entries : Array[@multiproc.Entry] = []
  match family.kind {
    @metric.Kind::Counter =>
      for point in family.metrics {
        entries.push(
          @multiproc.Entry::new(
            family.name,
            family.name + "_total",
            point.labels,
            family.help,
            number_of(point, family.name),
            timestamp=stamp_of(point),
          ),
        )
      }
    @metric.Kind::Gauge =>
      for point in family.metrics {
        entries.push(
          @multiproc.Entry::new(
            family.name,
            family.name,
            point.labels,
            family.help,
            number_of(point, family.name),
            timestamp=stamp_of(point),
          ),
        )
      }
    @metric.Kind::Histogram =>
      for point in family.metrics {
        match point.value {
          @metric.Value::Buckets(buckets~, sum~, count~) => {
            let mut previous = 0.0
            for bucket in buckets {
              entries.push(
                bucket_entry(
                  family,
                  point,
                  @expo.format_float(bucket.0),
                  bucket.1.to_double() - previous,
                ),
              )
              previous = bucket.1.to_double()
            }
            entries.push(
              bucket_entry(family, point, "+Inf", count.to_double() - previous),
            )
            entries.push(sum_entry(family, point, sum))
          }
          _ =>
            raise @metric.Refused(
              family.name + " is a histogram without buckets",
            )
        }
      }
    @metric.Kind::Summary =>
      for point in family.metrics {
        match point.value {
          // Quantiles are estimated from one process's samples and cannot be
          // added up, so only the count and the sum travel.
          @metric.Value::Quantiles(quantiles=_, sum~, count~) => {
            entries.push(count_entry(family, point, count))
            entries.push(sum_entry(family, point, sum))
          }
          _ =>
            raise @metric.Refused(family.name + " is a summary without a count")
        }
      }
    @metric.Kind::GaugeHistogram
    | @metric.Kind::Info
    | @metric.Kind::StateSet
    | @metric.Kind::Unknown =>
      raise @metric.Refused("no multiprocess form for " + family.name)
  }
  @multiproc.Part::new(
    pid,
    family.kind,
    if family.kind is @metric.Kind::Gauge {
      Some(mode)
    } else {
      None
    },
    entries,
  )
}

///|
fn shared(kind : @metric.Kind) -> Bool {
  match kind {
    @metric.Kind::Counter
    | @metric.Kind::Gauge
    | @metric.Kind::Histogram
    | @metric.Kind::Summary => true
    _ => false
  }
}

///|
fn is_worker_file(name : String, pid : String) -> Bool {
  if !name.has_suffix("_" + pid + ".db") {
    return false
  }
  let pieces = name.split("_").collect()
  if pieces.length() == 0 {
    return false
  }
  match pieces[0].to_owned() {
    "counter" | "gauge" | "histogram" | "summary" => true
    _ => false
  }
}

///|
/// Write `families` as this process's contribution to `dir`, one file per kind
/// (and one per gauge mode), replacing whatever this process wrote last time.
///
/// A flush is idempotent: the files hold the totals since the process started,
/// not a delta, so writing twice is writing once. Each file is written beside
/// its final name and renamed into place, so a scrape reading at the same
/// moment sees a whole file or the previous one, never half of either.
///
/// `modes` says how each gauge combines with the other processes'; a gauge
/// without one is `@multiproc.Mode::All`, which keeps the processes apart.
pub async fn write(
  dir : String,
  pid : Int32,
  families : Array[@metric.MetricFamily],
  modes? : Array[(String, @multiproc.Mode)],
) -> Written raise @metric.Refused {
  let modes = modes.unwrap_or([])
  check_modes(modes, families)
  let pid_text = pid.to_string()
  // One file per kind, and one per gauge mode: two counters are two families in
  // one file, not two files that would overwrite each other.
  let parts : Array[@multiproc.Part] = []
  let index : Map[String, Int32] = Map([])
  let skipped : Array[String] = []
  for family in families {
    if !shared(family.kind) {
      skipped.push(family.name)
      continue
    }
    let part = part_of(family, mode_for(modes, family.name), pid_text)
    match index.get(part.file_name()) {
      Some(i) =>
        for entry in part.entries {
          parts[i].entries.push(entry)
        }
      None => {
        index[part.file_name()] = parts.length()
        parts.push(part)
      }
    }
  }
  @fs.mkdir(dir, recursive=true, allow_exist=true) catch {
    _ => raise @metric.Refused("cannot create the metric directory: " + dir)
  }
  let written : Array[String] = []
  let mut entries = 0
  for part in parts {
    let name = part.file_name()
    let path = dir + "/" + name
    let temporary = path + ".tmp"
    @fs.write_file(temporary, part.encode()) catch {
      _ => raise @metric.Refused("cannot write " + temporary)
    }
    @fs.rename(temporary, path, replace=true) catch {
      _ => raise @metric.Refused("cannot rename " + temporary + " to " + path)
    }
    written.push(name)
    entries = entries + part.entries.length()
  }
  // A process that used to write a gauge under another mode, or a family that
  // is gone, leaves a file behind that would be merged on the next scrape.
  let existing = @fs.readdir(dir) catch {
    _ => raise @metric.Refused("cannot read the metric directory: " + dir)
  }
  for name in existing {
    if !is_worker_file(name, pid_text) {
      continue
    }
    let mut keep = false
    for mine in written {
      if mine == name {
        keep = true
      }
    }
    if !keep {
      @fs.remove(dir + "/" + name) catch {
        _ => ()
      }
    }
  }
  { files: written.length(), entries, skipped, }
}

///|
/// Drop the files of a process that has exited — the live gauge modes only.
/// A counter's file is cumulative, so its last value is the value the process
/// contributed, and it must stay; a `live` gauge describes a process that is
/// running now, so its file goes with it.
///
/// Call this from the supervisor, not from the worker: a process cannot report
/// its own death.
pub async fn mark_dead(
  dir : String,
  pid : Int32,
) -> Int32 raise @metric.Refused {
  let pid_text = pid.to_string()
  let existing = @fs.readdir(dir) catch {
    _ => raise @metric.Refused("cannot read the metric directory: " + dir)
  }
  let mut removed = 0
  for name in existing {
    if !name.has_suffix("_" + pid_text + ".db") {
      continue
    }
    let pieces = name.split("_").collect()
    if pieces.length() != 3 || pieces[0].to_owned() != "gauge" {
      continue
    }
    let mode = @multiproc.Mode::of(pieces[1].to_owned()) catch { _ => continue }
    if mode.is_live() {
      @fs.remove(dir + "/" + name) catch {
        _ => raise @metric.Refused("cannot remove " + name)
      }
      removed = removed + 1
    }
  }
  removed
}
