// Python number semantics on top of core `Json`.
//
// Core `Json::Number(Double, repr~)` has no int/float distinction.  This port
// uses the `repr` field as a marker: a number is a Python *float* when its
// `repr` looks like a float literal (contains `.`, `e`, `E`, `Infinity` or
// `NaN`) or when its value is not integral; otherwise it is a Python *int*.
// `loads` and the builtin functions that produce floats (`avg`,
// `to_number('1.5')`, ...) attach a `repr` equal to Python's `repr(float)`,
// so `to_string`/`json.dumps` output matches upstream.  Numbers coming from
// `@json.parse` carry no repr, so an integral `1.0` there is seen as `1`.

///|
fn repr_is_float(repr : String) -> Bool {
  for c in repr {
    if c is ('.' | 'e' | 'E' | 'I' | 'N') {
      return true
    }
  }
  false
}

///|
/// Whether a number is a Python `float` (see the module comment).
fn number_is_float(d : Double, repr : String?) -> Bool {
  match repr {
    Some(r) if repr_is_float(r) => true
    _ => d.is_nan() || d.is_inf() || d.floor() != d
  }
}

///|
/// A Python float as a `Json` number (with the repr marker).
fn make_float(d : Double) -> Json {
  let repr = if d.is_nan() {
    "NaN"
  } else if d.is_pos_inf() {
    "Infinity"
  } else if d.is_neg_inf() {
    "-Infinity"
  } else {
    py_float_repr(d)
  }
  Json::number(d, repr~)
}

///|
/// A Python int as a `Json` number.
fn make_int(d : Double) -> Json {
  Json::number(d)
}

///|
/// Shortest round-trip decimal digits of a finite, non-zero, positive double
/// and the position of the decimal point (`value = 0.DIGITS * 10^decpt`).
fn shortest_digits(d : Double) -> (String, Int) {
  let s = d.to_string()
  let (mantissa, exp) = match s.find("e") {
    Some(i) => {
      let m = s.view(end_offset=i).to_owned()
      let e = s.view(start_offset=i + 1).to_owned()
      let e = if e.has_prefix("+") {
        e.view(start_offset=1).to_owned()
      } else {
        e
      }
      (m, @string.parse_int(e) catch { _ => 0 })
    }
    None => (s, 0)
  }
  let (int_part, frac_part) = match mantissa.find(".") {
    Some(i) =>
      (
        mantissa.view(end_offset=i).to_owned(),
        mantissa.view(start_offset=i + 1).to_owned(),
      )
    None => (mantissa, "")
  }
  let all = int_part + frac_part
  let mut decpt = int_part.length() + exp
  let chars = all.to_array()
  let mut start = 0
  while start < chars.length() && chars[start] == '0' {
    start += 1
    decpt -= 1
  }
  let mut end = chars.length()
  while end > start && chars[end - 1] == '0' {
    end -= 1
  }
  (String::from_array(chars[start:end]), decpt)
}

///|
/// Python's `repr(float)` (`float_repr_style == 'short'`).
fn py_float_repr(d : Double) -> String {
  if d.is_nan() {
    return "nan"
  }
  if d.is_pos_inf() {
    return "inf"
  }
  if d.is_neg_inf() {
    return "-inf"
  }
  if d == 0.0 {
    return if (1.0 / d).is_neg_inf() { "-0.0" } else { "0.0" }
  }
  let sign = if d < 0.0 { "-" } else { "" }
  let (digits, decpt) = shortest_digits(d.abs())
  let n = digits.length()
  let body = if decpt <= -4 || decpt > 16 {
    // Exponential notation.
    let exp = decpt - 1
    let mant = if n == 1 {
      digits
    } else {
      digits.view(end_offset=1).to_owned() +
      "." +
      digits.view(start_offset=1).to_owned()
    }
    let exp_sign = if exp < 0 { "-" } else { "+" }
    let exp_abs = exp.abs()
    let exp_str = if exp_abs < 10 { "0\{exp_abs}" } else { "\{exp_abs}" }
    "\{mant}e\{exp_sign}\{exp_str}"
  } else if decpt <= 0 {
    "0." + "0".repeat(-decpt) + digits
  } else if decpt >= n {
    digits + "0".repeat(decpt - n) + ".0"
  } else {
    digits.view(end_offset=decpt).to_owned() +
    "." +
    digits.view(start_offset=decpt).to_owned()
  }
  sign + body
}

///|
/// `str(int)` of a Python int stored as a double.
fn py_int_str(d : Double, repr : String?) -> String {
  match repr {
    Some(r) => return r
    None => ()
  }
  if d.abs() < 1.0e18 {
    return d.to_int64().to_string()
  }
  let sign = if d < 0.0 { "-" } else { "" }
  let (digits, decpt) = shortest_digits(d.abs())
  sign + digits + "0".repeat(decpt - digits.length())
}

///|
/// `str()` / `repr()` of a number (`inf`, `nan` for non-finite floats).
fn py_number_str(d : Double, repr : String?) -> String {
  if number_is_float(d, repr) {
    py_float_repr(d)
  } else {
    py_int_str(d, repr)
  }
}

///|
/// `json.dumps` of a number.
fn py_number_dumps(d : Double, repr : String?) -> String {
  if d.is_nan() {
    "NaN"
  } else if d.is_pos_inf() {
    "Infinity"
  } else if d.is_neg_inf() {
    "-Infinity"
  } else {
    py_number_str(d, repr)
  }
}

///|
/// Python's `str.isspace()` for a single character.
fn py_isspace(c : Char) -> Bool {
  match c.to_int() {
    0x09..=0x0d | 0x1c..=0x20 | 0x85 | 0xa0 | 0x1680 => true
    0x2000..=0x200a | 0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 => true
    _ => false
  }
}

///|
/// Python's `str.strip()`.
fn py_strip(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  while start < chars.length() && py_isspace(chars[start]) {
    start += 1
  }
  let mut end = chars.length()
  while end > start && py_isspace(chars[end - 1]) {
    end -= 1
  }
  String::from_array(chars[start:end])
}

///|
/// Python's `str.lstrip()`.
fn py_lstrip(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  while start < chars.length() && py_isspace(chars[start]) {
    start += 1
  }
  String::from_array(chars[start:])
}

///|
/// Checks `digit (_? digit)*` starting at `i`; returns the end index, or
/// `None` if there is no valid digit group at `i`.
fn scan_py_digits(chars : Array[Char], i : Int) -> Int? {
  if i >= chars.length() || !(chars[i] is '0'..='9') {
    return None
  }
  let mut j = i + 1
  while j < chars.length() {
    if chars[j] is '0'..='9' {
      j += 1
    } else if chars[j] == '_' &&
      j + 1 < chars.length() &&
      chars[j + 1] is '0'..='9' {
      j += 2
    } else {
      break
    }
  }
  Some(j)
}

///|
/// Python's `int(s)` for strings (base 10).  Returns `None` on `ValueError`.
fn py_int_parse(s : String) -> Json? {
  let chars = py_strip(s).to_array()
  let mut i = 0
  let mut negative = false
  if i < chars.length() && chars[i] is ('+' | '-') {
    negative = chars[i] == '-'
    i += 1
  }
  guard scan_py_digits(chars, i) is Some(end) && end == chars.length() else {
    return None
  }
  let digits = StringBuilder()
  for c in chars[i:end] {
    if c != '_' {
      digits.write_char(c)
    }
  }
  // Normalize leading zeros like Python's int().
  let mut text = digits.to_string()
  while text.length() > 1 && text.has_prefix("0") {
    text = text.view(start_offset=1).to_owned()
  }
  let d = @string.parse_double(text) catch { _ => @double.infinity }
  let d = if negative { -d } else { d }
  let text = if negative && text != "0" { "-" + text } else { text }
  // Keep the exact digits for ints that a double cannot represent exactly.
  if text.length() > 15 {
    Some(Json::number(d, repr=text))
  } else {
    Some(make_int(d))
  }
}

///|
/// Python's `float(s)` for strings.  Returns `None` on `ValueError`.
fn py_float_parse(s : String) -> Json? {
  let stripped = py_strip(s)
  let chars = stripped.to_array()
  let mut i = 0
  let mut negative = false
  if i < chars.length() && chars[i] is ('+' | '-') {
    negative = chars[i] == '-'
    i += 1
  }
  let rest = String::from_array(chars[i:]).to_lower()
  if rest is ("inf" | "infinity") {
    return Some(make_float(if negative { @double.neg_infinity } else { @double.infinity }))
  }
  if rest == "nan" {
    return Some(make_float(@double.not_a_number))
  }
  // [digits] [. [digits]] [e [sign] digits], at least one mantissa digit.
  let buf = StringBuilder()
  let mut has_digits = false
  let mut j = i
  match scan_py_digits(chars, j) {
    Some(end) => {
      has_digits = true
      for c in chars[j:end] {
        if c != '_' {
          buf.write_char(c)
        }
      }
      j = end
    }
    None => buf.write_char('0')
  }
  if j < chars.length() && chars[j] == '.' {
    j += 1
    buf.write_char('.')
    match scan_py_digits(chars, j) {
      Some(end) => {
        has_digits = true
        for c in chars[j:end] {
          if c != '_' {
            buf.write_char(c)
          }
        }
        j = end
      }
      None => buf.write_char('0')
    }
  }
  if !has_digits {
    return None
  }
  let mut exp_positive = true
  if j < chars.length() && chars[j] is ('e' | 'E') {
    buf.write_char('e')
    j += 1
    if j < chars.length() && chars[j] is ('+' | '-') {
      exp_positive = chars[j] == '+'
      buf.write_char(chars[j])
      j += 1
    }
    match scan_py_digits(chars, j) {
      Some(end) => {
        for c in chars[j:end] {
          if c != '_' {
            buf.write_char(c)
          }
        }
        j = end
      }
      None => return None
    }
  }
  if j != chars.length() {
    return None
  }
  let d = @string.parse_double(buf.to_string()) catch {
    // Only overflow/underflow can fail after the syntax check above.
    _ => if exp_positive { @double.infinity } else { 0.0 }
  }
  Some(make_float(if negative { -d } else { d }))
}
