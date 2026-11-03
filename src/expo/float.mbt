// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn slice(chars : Array[Char], start : Int32, stop : Int32) -> Array[Char] {
  let out : Array[Char] = []
  for i = start; i < stop; i = i + 1 {
    out.push(chars[i])
  }
  out
}

///|
fn chars_to_string(chars : Array[Char]) -> String {
  let sb = StringBuilder()
  for c in chars {
    sb.write_char(c)
  }
  sb.to_string()
}

///|
fn pad_two(n : Int32) -> String {
  let a = if n < 0 { -n } else { n }
  if a < 10 {
    "0" + a.to_string()
  } else {
    a.to_string()
  }
}

///|
/// Format a float the way the official clients do: `+Inf`, `-Inf`, and `NaN` by
/// name; otherwise the shortest decimal that round-trips, with a `.0` on
/// integers and Go's switch to a two-digit exponent once the integer part is
/// longer than six digits (so `1000000.0` is `1e+06`, matching what a
/// Prometheus scrape expects to read).
pub fn format_float(d : Double) -> String {
  let inf = 1.0 / 0.0
  if d != d {
    return "NaN"
  }
  if d == inf {
    return "+Inf"
  }
  if d == 0.0 - inf {
    return "-Inf"
  }
  if d == 0.0 {
    if 1.0 / d < 0.0 {
      return "-0.0"
    }
    return "0.0"
  }
  let s = d.to_string()
  let chars = s.to_array()
  let mut start = 0
  let mut neg = false
  if chars.length() > 0 && chars[0] == '-' {
    neg = true
    start = 1
  }
  let mut epos = -1
  for i = start; i < chars.length(); i = i + 1 {
    if chars[i] == 'e' || chars[i] == 'E' {
      epos = i
      break
    }
  }
  let mut exp10 = 0
  let mant : Array[Char] = if epos >= 0 {
    let mut esign = 1
    let mut j = epos + 1
    if j < chars.length() && (chars[j] == '+' || chars[j] == '-') {
      if chars[j] == '-' {
        esign = -1
      }
      j = j + 1
    }
    let mut ev = 0
    while j < chars.length() {
      ev = ev * 10 + (chars[j].to_int() - '0'.to_int())
      j = j + 1
    }
    exp10 = esign * ev
    slice(chars, start, epos)
  } else {
    slice(chars, start, chars.length())
  }
  let mut dot = -1
  for i = 0; i < mant.length(); i = i + 1 {
    if mant[i] == '.' {
      dot = i
      break
    }
  }
  let int_part : Array[Char] = if dot >= 0 { slice(mant, 0, dot) } else { mant }
  let frac_part : Array[Char] = if dot >= 0 {
    slice(mant, dot + 1, mant.length())
  } else {
    []
  }
  let all : Array[Char] = int_part + frac_part
  let mut firstnz = -1
  for i = 0; i < all.length(); i = i + 1 {
    if all[i] != '0' {
      firstnz = i
      break
    }
  }
  if firstnz < 0 {
    return "0.0"
  }
  let int_len = int_part.length()
  let mut e = 0
  if firstnz < int_len {
    e = int_len - 1 - firstnz
  } else {
    e = -(firstnz - int_len + 1)
  }
  let mut digits = slice(all, firstnz, all.length())
  let mut dend = digits.length()
  while dend > 1 && digits[dend - 1] == '0' {
    dend = dend - 1
  }
  digits = slice(digits, 0, dend)
  e = e + exp10
  let mut out = ""
  if e >= -4 && e <= 15 {
    if e >= 0 {
      let int_digits_n = e + 1
      let mut ip = ""
      for i = 0; i < int_digits_n; i = i + 1 {
        if i < digits.length() {
          ip = ip + digits[i].to_string()
        } else {
          ip = ip + "0"
        }
      }
      let mut fp = ""
      for i = int_digits_n; i < digits.length(); i = i + 1 {
        fp = fp + digits[i].to_string()
      }
      if fp == "" {
        fp = "0"
      }
      out = ip + "." + fp
    } else {
      let mut z = ""
      for i = 0; i < -e - 1; i = i + 1 {
        z = z + "0"
      }
      out = "0." + z + chars_to_string(digits)
    }
  } else {
    let mut m = digits[0].to_string()
    if digits.length() > 1 {
      m = m + "." + chars_to_string(slice(digits, 1, digits.length()))
    }
    let esign = if e >= 0 { "+" } else { "-" }
    out = m + "e" + esign + pad_two(e)
  }
  if !neg {
    let mut dp = -1
    for i = 0; i < out.length(); i = i + 1 {
      if out[i] == '.' {
        dp = i
        break
      }
    }
    if dp > 6 {
      let oc = out.to_array()
      let nodot : Array[Char] = slice(oc, 0, dp) +
        slice(oc, dp + 1, oc.length())
      let mut m2 = nodot[0].to_string() +
        "." +
        chars_to_string(slice(nodot, 1, nodot.length()))
      while m2.length() > 0 && m2[m2.length() - 1] == '0' {
        m2 = m2[0:m2.length() - 1].to_owned()
      }
      if m2.length() > 0 && m2[m2.length() - 1] == '.' {
        m2 = m2[0:m2.length() - 1].to_owned()
      }
      out = m2 + "e+" + pad_two(dp - 1)
    }
  }
  if neg {
    "-" + out
  } else {
    out
  }
}
