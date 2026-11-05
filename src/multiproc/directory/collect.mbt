// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The families the worker files in `dir` add up to, in the order the files name
/// them. Files are read in name order, so a directory that has not changed
/// renders the same bytes twice.
///
/// `at` is the moment of the scrape. As with a registry, a sample that carries
/// no time of its own is stamped with it; a scrape that leaves `at` out writes
/// no timestamps at all, which is what the compatibility format does anyway.
pub async fn collect(
  dir : String,
  at? : Double,
) -> Array[@metric.MetricFamily] raise @metric.Refused {
  let names = @fs.readdir(dir) catch {
    _ => raise @metric.Refused("cannot read the metric directory: " + dir)
  }
  // The order of a directory listing is the file system's business; a scrape's
  // is not. Sorting by name makes two scrapes of an unchanged directory render
  // the same bytes, on every platform.
  names.sort_by(fn(a, b) { String::lexical_compare(a, b) })
  let parts : Array[@multiproc.Part] = []
  for name in names {
    if !name.has_suffix(".db") {
      continue
    }
    let path = dir + "/" + name
    let (_pid, _kind, mode) = @multiproc.Part::name_of(name) catch {
      @metric.Refused(message) =>
        raise @metric.Refused(
          "a file in the metric directory is not a metric file: " +
          name +
          " (" +
          message +
          ")",
        )
    }
    let bytes = @fs.read_file(path).binary() catch {
      _ => {
        // A live gauge file can be removed between the listing and the read,
        // when a supervisor marks its process dead. That is not an error: the
        // process is gone, which is exactly what its absence means. Any other
        // file that disappears is a scrape that would silently lose numbers.
        let live = match mode {
          Some(m) => m.is_live()
          None => false
        }
        if live {
          continue
        }
        raise @metric.Refused("cannot read " + path)
      }
    }
    parts.push(@multiproc.Part::decode(name, bytes))
  }
  let families = @multiproc.merge(parts)
  match at {
    Some(when) =>
      families.map(fn(family) {
        {
          ..family,
          metrics: family.metrics.map(fn(point) {
            match point.timestamp {
              Some(_) => point
              None => { ..point, timestamp: Some(when), }
            }
          }),
        }
      })
    None => families
  }
}
