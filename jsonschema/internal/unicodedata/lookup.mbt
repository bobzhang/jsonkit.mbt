///|
/// Binary search over a flattened array of inclusive `[start, end]` pairs.
fn in_ranges(ranges : FixedArray[Int], cp : Int) -> Bool {
  let n = ranges.length() / 2
  for lo = 0, hi = n; lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < ranges[2 * mid] {
      continue lo, mid
    } else if cp > ranges[2 * mid + 1] {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
/// Index of the run containing `cp` in a sorted array of run starts.
fn run_index(starts : FixedArray[Int], cp : Int) -> Int {
  // largest i such that starts[i] <= cp
  for lo = 0, hi = starts.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if starts[mid] <= cp {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo - 1
  }
}

///|
/// `chr(cp).isdecimal()`.
pub fn is_decimal(cp : Int) -> Bool {
  in_ranges(decimal_ranges, cp)
}

///|
/// `chr(cp).isalnum()`.
pub fn is_alnum(cp : Int) -> Bool {
  in_ranges(alnum_ranges, cp)
}

///|
/// `chr(cp).isalpha()`.
pub fn is_alpha(cp : Int) -> Bool {
  in_ranges(alpha_ranges, cp)
}

///|
/// `chr(cp).isspace()`.
pub fn is_space(cp : Int) -> Bool {
  in_ranges(space_ranges, cp)
}

///|
/// `chr(cp).isprintable()`.
pub fn is_printable(cp : Int) -> Bool {
  in_ranges(printable_ranges, cp)
}

///|
/// `unicodedata.category(chr(cp)).startswith("M")`.
pub fn is_mark(cp : Int) -> Bool {
  in_ranges(mark_ranges, cp)
}

///|
/// Whether `unicodedata.name(chr(cp))` succeeds.
pub fn has_name(cp : Int) -> Bool {
  !in_ranges(unnamed_ranges, cp)
}

///|
/// `unicodedata.combining(chr(cp))`.
pub fn combining(cp : Int) -> Int {
  let i = run_index(ccc_starts, cp)
  if i < 0 {
    0
  } else {
    ccc_values[i]
  }
}

///|
/// `unicodedata.bidirectional(chr(cp))` (`""` when unknown).
pub fn bidirectional(cp : Int) -> String {
  let i = run_index(bidi_starts, cp)
  if i < 0 {
    ""
  } else {
    bidi_names[bidi_values[i]]
  }
}

///|
/// The code points of a MoonBit (UTF-16) string as Python sees them: valid
/// surrogate pairs combine, lone surrogates are kept as-is.
pub fn code_points(s : StringView) -> Array[Int] {
  let out = []
  let n = s.length()
  for i = 0; i < n; {
    let c = s.code_unit_at(i).to_int()
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < n {
      let d = s.code_unit_at(i + 1).to_int()
      if d >= 0xDC00 && d <= 0xDFFF {
        out.push(0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00))
        continue i + 2
      }
    }
    out.push(c)
    continue i + 1
  }
  out
}

///|
/// Inverse of `code_points`.
pub fn from_code_points(cps : ArrayView[Int]) -> String {
  let sb = StringBuilder()
  for cp in cps {
    write_code_point(sb, cp)
  }
  sb.to_string()
}

///|
/// Append a code point (possibly a lone surrogate) to a builder.
pub fn write_code_point(sb : StringBuilder, cp : Int) -> Unit {
  if cp >= 0x10000 {
    let v = cp - 0x10000
    sb.write_char(Int::unsafe_to_char(0xD800 + (v >> 10)))
    sb.write_char(Int::unsafe_to_char(0xDC00 + (v & 0x3FF)))
  } else {
    sb.write_char(Int::unsafe_to_char(cp))
  }
}

///|
/// `len(s)` in Python: the number of code points.
pub fn py_len(s : StringView) -> Int {
  let n = s.length()
  let mut count = 0
  for i = 0; i < n; {
    let c = s.code_unit_at(i).to_int()
    count += 1
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < n {
      let d = s.code_unit_at(i + 1).to_int()
      if d >= 0xDC00 && d <= 0xDFFF {
        continue i + 2
      }
    }
    continue i + 1
  }
  count
}

///|
fn pairs(ranges : FixedArray[Int]) -> Array[(Int, Int)] {
  Array::makei(ranges.length() / 2, i => (ranges[2 * i], ranges[2 * i + 1]))
}

///|
/// Inclusive ranges of `str.isdecimal()` code points.
pub fn decimal_set() -> Array[(Int, Int)] {
  pairs(decimal_ranges)
}

///|
/// Inclusive ranges of `str.isalnum()` code points.
pub fn alnum_set() -> Array[(Int, Int)] {
  pairs(alnum_ranges)
}

///|
/// Inclusive ranges of `str.isspace()` code points.
pub fn space_set() -> Array[(Int, Int)] {
  pairs(space_ranges)
}
