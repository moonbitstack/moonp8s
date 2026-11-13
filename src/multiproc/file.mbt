// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One value in one worker's file: the family it belongs to, the name the sample
/// is written under, its labels, the family's help text, the value, and the time
/// the value was recorded (zero when it was not recorded with one).
///
/// The pair of `metric` and `sample` is what lets a counter be filed under
/// `orders` and written as `orders_total`, and a histogram bucket under
/// `orders_seconds` and `orders_seconds_bucket`.
pub(all) struct Entry {
  metric : String
  sample : String
  labels : Array[(String, String)]
  help : String
  value : Double
  timestamp : Double
}

///|
/// One value for a worker's file.
pub fn Entry::new(
  metric : String,
  sample : String,
  labels : Array[(String, String)],
  help : String,
  value : Double,
  timestamp~ : Double = 0.0,
) -> Entry {
  { metric, sample, labels, help, value, timestamp, }
}

///|
/// One worker's file, decoded: whose it is, what kind of metric it holds, the
/// gauge mode it was written for, and its values.
pub(all) struct Part {
  /// The process the file belongs to, as the `pid` label carries it.
  pid : String
  kind : @metric.Kind
  /// The gauge mode, for a file of gauges; `None` for every other kind.
  mode : Mode?
  entries : Array[Entry]
}

///|
/// One worker's file.
pub fn Part::new(
  pid : String,
  kind : @metric.Kind,
  mode : Mode?,
  entries : Array[Entry],
) -> Part {
  { pid, kind, mode, entries, }
}

///|
/// The name this part is stored under: `<kind>_<pid>.db`, or
/// `gauge_<mode>_<pid>.db` for gauges, which is the layout the official clients
/// read and write.
pub fn Part::file_name(self : Part) -> String {
  match self.mode {
    Some(mode) => "gauge_" + mode.code() + "_" + self.pid + ".db"
    None => self.kind.code() + "_" + self.pid + ".db"
  }
}

///|
fn kind_of_file(word : String) -> @metric.Kind raise @metric.Refused {
  match word {
    "counter" => @metric.Kind::Counter
    "gauge" => @metric.Kind::Gauge
    "histogram" => @metric.Kind::Histogram
    "summary" => @metric.Kind::Summary
    _ => raise @metric.Refused("unknown metric file type: " + word)
  }
}

///|
/// The part a file name announces. A gauge file carries its mode in the name
/// because the mode is a property of how the worker wrote the value, and the
/// scrape has no other way to learn it.
pub fn Part::name_of(
  file_name : String,
) -> (String, @metric.Kind, Mode?) raise @metric.Refused {
  let stem = match file_name.strip_suffix(".db") {
    Some(s) => s.to_owned()
    None => raise @metric.Refused("not a metric file: " + file_name)
  }
  let pieces = stem.split("_").collect()
  let kind = kind_of_file(pieces[0].to_owned())
  if kind is @metric.Kind::Gauge {
    if pieces.length() != 3 {
      raise @metric.Refused(
        "a gauge file name is gauge_<mode>_<pid>.db: " + file_name,
      )
    }
    (pieces[2].to_owned(), kind, Some(Mode::of(pieces[1].to_owned())))
  } else {
    if pieces.length() != 2 {
      raise @metric.Refused(
        "a metric file name is <kind>_<pid>.db: " + file_name,
      )
    }
    (pieces[1].to_owned(), kind, None)
  }
}

///|
fn key_of(entry : Entry) -> String {
  let labels : Map[String, Json] = Map([])
  for pair in entry.labels {
    labels[pair.0] = Json::string(pair.1)
  }
  @moonjson.dumps(
    Json::array([
      Json::string(entry.metric),
      Json::string(entry.sample),
      Json::object(labels),
      Json::string(entry.help),
    ]),
  )
}

///|
fn entry_of_key(key : String) -> Entry raise @metric.Refused {
  let parsed = @moonjson.loads(key, @moonjson.strict) catch {
    _ => raise @metric.Refused("a key in the file is not JSON: " + key)
  }
  let fields = match parsed {
    Array(a) => a
    _ => raise @metric.Refused("a key in the file is not an array: " + key)
  }
  if fields.length() != 4 {
    raise @metric.Refused(
      "a key in the file has four fields, not " + fields.length().to_string(),
    )
  }
  let metric = match fields[0] {
    String(s) => s
    _ => raise @metric.Refused("a key's family name is not a string: " + key)
  }
  let sample = match fields[1] {
    String(s) => s
    _ => raise @metric.Refused("a key's sample name is not a string: " + key)
  }
  let labels : Array[(String, String)] = []
  match fields[2] {
    Object(map) =>
      for name, value in map {
        match value {
          String(v) => labels.push((name, v))
          _ => raise @metric.Refused("a label value is not a string: " + key)
        }
      }
    _ => raise @metric.Refused("a key's labels are not an object: " + key)
  }
  let help = match fields[3] {
    String(s) => s
    _ => raise @metric.Refused("a key's help text is not a string: " + key)
  }
  { metric, sample, labels, help, value: 0.0, timestamp: 0.0, }
}

///|
fn put_u32(out : Array[Byte], v : Int32) -> Unit {
  out.push((v & 0xFF).to_byte())
  out.push(((v >> 8) & 0xFF).to_byte())
  out.push(((v >> 16) & 0xFF).to_byte())
  out.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn put_f64(out : Array[Byte], d : Double) -> Unit {
  let bits = d.reinterpret_as_int64()
  for i = 0; i < 8; i = i + 1 {
    out.push(((bits >> (i * 8)) & 0xFFL).to_int().to_byte())
  }
}

///|
fn pad_for(key_len : Int32) -> Int32 {
  key_len + (8 - (key_len + 4) % 8)
}

///|
fn entry_bytes(entry : Entry, out : Array[Byte]) -> Unit {
  let key = @utf8.encode(key_of(entry))
  let key_len = key.length()
  put_u32(out, key_len)
  for i = 0; i < key_len; i = i + 1 {
    out.push(key[i])
  }
  let pad = pad_for(key_len)
  for i = key_len; i < pad; i = i + 1 {
    out.push(b' ')
  }
  put_f64(out, entry.value)
  put_f64(out, entry.timestamp)
}

///|
/// The bytes of this part: a four-byte used count, four bytes of padding, then
/// one record per entry — a key length, the key, padding to an eight-byte
/// boundary, the value, and the timestamp, each value a little-endian double.
///
/// This is the layout the official clients' multiprocess mode uses, which is
/// the point: a directory of these files is readable by them and by this
/// library alike.
pub fn Part::encode(self : Part) -> Bytes {
  let body : Array[Byte] = []
  for entry in self.entries {
    entry_bytes(entry, body)
  }
  let out : Array[Byte] = []
  put_u32(out, body.length() + 8)
  put_u32(out, 0)
  for b in body {
    out.push(b)
  }
  Bytes::from_array(out[:])
}

///|
fn read_u32(bytes : Array[Byte], at : Int32) -> Int32 {
  bytes[at].to_int() |
  (bytes[at + 1].to_int() << 8) |
  (bytes[at + 2].to_int() << 16) |
  (bytes[at + 3].to_int() << 24)
}

///|
fn read_f64(bytes : Array[Byte], at : Int32) -> Double {
  let mut bits = 0L
  for i = 0; i < 8; i = i + 1 {
    bits = bits | (bytes[at + i].to_int().to_int64() << (i * 8))
  }
  bits.reinterpret_as_double()
}

///|
/// Decode one worker's file. A file shorter than its header claims is refused
/// rather than half-read: a torn file means a writer that does not write whole
/// files, and guessing at the remainder would report numbers nobody wrote.
pub fn Part::decode(
  file_name : String,
  bytes : Bytes,
) -> Part raise @metric.Refused {
  let (pid, kind, mode) = Part::name_of(file_name)
  let raw = bytes.to_array()
  let entries : Array[Entry] = []
  if raw.length() < 8 {
    if raw.length() == 0 {
      return { pid, kind, mode, entries, }
    }
    raise @metric.Refused(
      "a metric file is shorter than its header: " + file_name,
    )
  }
  let used = read_u32(raw, 0)
  if used < 8 || used > raw.length() {
    raise @metric.Refused(
      "a metric file says it uses " +
      used.to_string() +
      " bytes of " +
      raw.length().to_string() +
      ": " +
      file_name,
    )
  }
  let mut pos = 8
  while pos < used {
    if pos + 4 > used {
      raise @metric.Refused(
        "a metric file ends inside a key length, at " +
        pos.to_string() +
        ": " +
        file_name,
      )
    }
    let key_len = read_u32(raw, pos)
    pos = pos + 4
    if key_len <= 0 || pos + pad_for(key_len) + 16 > used {
      raise @metric.Refused(
        "a metric file ends inside a record, at " +
        pos.to_string() +
        ": " +
        file_name,
      )
    }
    let key = @utf8.decode(Bytes::from_array(raw[pos:pos + key_len])) catch {
      _ =>
        raise @metric.Refused(
          "a key in " + file_name + " is not UTF-8, at " + pos.to_string(),
        )
    }
    pos = pos + pad_for(key_len)
    let value = read_f64(raw, pos)
    pos = pos + 8
    let timestamp = read_f64(raw, pos)
    pos = pos + 8
    let entry = entry_of_key(key)
    entries.push({ ..entry, value, timestamp, })
  }
  { pid, kind, mode, entries, }
}
