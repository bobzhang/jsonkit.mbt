// A port of the parts of Python's `json` module that jmespath.py relies on:
// `json.loads` (used by the lexer for literals and quoted identifiers) and
// `json.dumps(..., separators=(',', ':'))` (used by `to_string`).

///|
priv struct JsonScanner {
  s : String
  len : Int
}

///|
fn JsonScanner::error(
  self : JsonScanner,
  msg : String,
  idx : Int,
) -> JSONDecodeError {
  // Python positions count code points, ours are UTF-16 offsets.
  let pos = self.s.char_length(end_offset=idx.clamp(min=0, max=self.len))
  JSONDecodeError(msg~, doc=self.s, pos~)
}

///|
fn JsonScanner::char_at(self : JsonScanner, idx : Int) -> Int {
  self.s.code_unit_at(idx).to_int()
}

///|
fn JsonScanner::skip_ws(self : JsonScanner, idx : Int) -> Int {
  let mut i = idx
  while i < self.len && self.char_at(i) is (0x20 | 0x09 | 0x0a | 0x0d) {
    i += 1
  }
  i
}

///|
fn JsonScanner::starts_with_at(
  self : JsonScanner,
  idx : Int,
  word : String,
) -> Bool {
  idx + word.length() <= self.len &&
  self.s.view(start_offset=idx, end_offset=idx + word.length()) == word
}

///|
fn hex_value(c : Int) -> Int {
  match c {
    0x30..=0x39 => c - 0x30
    0x61..=0x66 => c - 0x61 + 10
    0x41..=0x46 => c - 0x41 + 10
    _ => -1
  }
}

///|
/// `scanstring`: `begin` is the index just after the opening quote.
fn JsonScanner::scanstring(
  self : JsonScanner,
  begin : Int,
) -> (String, Int) raise JSONDecodeError {
  let buf = StringBuilder()
  let mut next = begin
  while true {
    // Find the end of the chunk.
    let mut end = next
    while end < self.len {
      let c = self.char_at(end)
      if c == '"' || c == '\\' {
        break
      }
      if c <= 0x1f {
        raise self.error("Invalid control character at", end)
      }
      end += 1
    }
    if end >= self.len {
      raise self.error("Unterminated string starting at", begin - 1)
    }
    buf.write_view(self.s.view(start_offset=next, end_offset=end))
    if self.char_at(end) == '"' {
      return (buf.to_string(), end + 1)
    }
    // Backslash escape.
    next = end + 1
    if next >= self.len {
      raise self.error("Unterminated string starting at", begin - 1)
    }
    let c = self.char_at(next)
    if c != 'u' {
      let decoded : Int = match c {
        '"' => '"'
        '\\' => '\\'
        '/' => '/'
        'b' => 0x08
        'f' => 0x0c
        'n' => 0x0a
        'r' => 0x0d
        't' => 0x09
        _ => raise self.error("Invalid \\escape", next - 1)
      }
      buf.write_char(Int::unsafe_to_char(decoded))
      next += 1
    } else {
      next += 1
      let end4 = next + 4
      if end4 >= self.len {
        raise self.error("Invalid \\uXXXX escape", next - 1)
      }
      let mut code = 0
      for i in next..<end4 {
        let h = hex_value(self.char_at(i))
        if h < 0 {
          raise self.error("Invalid \\uXXXX escape", end4 - 5)
        }
        code = code * 16 + h
      }
      // Strings are UTF-16 here, so surrogate pairs written unit by unit
      // join up exactly like Python's surrogate-pair handling.
      buf.write_char(Int::unsafe_to_char(code))
      next = end4
    }
  }
  panic()
}

///|
/// Python's json module maps every `NaN` to one shared float object
/// (`json.decoder.NaN`); identity matters for container equality and `in`,
/// so `loads` returns this single value for every `NaN`.
let json_nan_constant : Json = make_float(@double.not_a_number)

///|
/// `_match_number_unicode`.  Returns `None` when there is no number here
/// (`StopIteration` upstream).
fn JsonScanner::match_number(self : JsonScanner, start : Int) -> (Json, Int)? {
  let end_idx = self.len - 1
  let mut idx = start
  let is_digit = (i : Int) => i <= end_idx && self.char_at(i) is (0x30..=0x39)
  if self.char_at(idx) == '-' {
    idx += 1
    if idx > end_idx {
      return None
    }
  }
  let c = self.char_at(idx)
  if c is (0x31..=0x39) {
    idx += 1
    while is_digit(idx) {
      idx += 1
    }
  } else if c == '0' {
    idx += 1
  } else {
    return None
  }
  let mut is_float = false
  if idx < end_idx && self.char_at(idx) == '.' && is_digit(idx + 1) {
    is_float = true
    idx += 2
    while is_digit(idx) {
      idx += 1
    }
  }
  if idx < end_idx && self.char_at(idx) is ('e' | 'E') {
    let e_start = idx
    idx += 1
    if idx < end_idx && self.char_at(idx) is ('-' | '+') {
      idx += 1
    }
    while is_digit(idx) {
      idx += 1
    }
    if is_digit(idx - 1) {
      is_float = true
    } else {
      idx = e_start
    }
  }
  let text = self.s.view(start_offset=start, end_offset=idx).to_owned()
  let value = if is_float {
    match py_float_parse(text) {
      Some(v) => v
      None => make_float(@double.not_a_number)
    }
  } else {
    match py_int_parse(text) {
      Some(v) => v
      None => make_int(0.0)
    }
  }
  Some((value, idx))
}

///|
fn JsonScanner::scan_once(
  self : JsonScanner,
  idx : Int,
) -> (Json, Int) raise JSONDecodeError {
  if idx >= self.len {
    raise self.error("Expecting value", idx)
  }
  match self.char_at(idx) {
    '"' => {
      let (s, end) = self.scanstring(idx + 1)
      (Json::string(s), end)
    }
    '{' => self.parse_object(idx + 1)
    '[' => self.parse_array(idx + 1)
    'n' if self.starts_with_at(idx, "null") => (Json::null(), idx + 4)
    't' if self.starts_with_at(idx, "true") => (Json::boolean(true), idx + 4)
    'f' if self.starts_with_at(idx, "false") => (Json::boolean(false), idx + 5)
    'N' if self.starts_with_at(idx, "NaN") => (json_nan_constant, idx + 3)
    'I' if self.starts_with_at(idx, "Infinity") =>
      (make_float(@double.infinity), idx + 8)
    '-' if self.starts_with_at(idx, "-Infinity") =>
      (make_float(@double.neg_infinity), idx + 9)
    _ =>
      match self.match_number(idx) {
        Some(r) => r
        None => raise self.error("Expecting value", idx)
      }
  }
}

///|
fn JsonScanner::parse_object(
  self : JsonScanner,
  start : Int,
) -> (Json, Int) raise JSONDecodeError {
  let end_idx = self.len - 1
  let map : Map[String, Json] = Map([])
  let mut idx = self.skip_ws(start)
  if idx > end_idx || self.char_at(idx) != '}' {
    while true {
      if idx > end_idx || self.char_at(idx) != '"' {
        raise self.error(
          "Expecting property name enclosed in double quotes", idx,
        )
      }
      let (key, after_key) = self.scanstring(idx + 1)
      idx = self.skip_ws(after_key)
      if idx > end_idx || self.char_at(idx) != ':' {
        raise self.error("Expecting ':' delimiter", idx)
      }
      idx = self.skip_ws(idx + 1)
      let (value, after_value) = self.scan_once(idx)
      map[key] = value
      idx = self.skip_ws(after_value)
      if idx <= end_idx && self.char_at(idx) == '}' {
        break
      }
      if idx > end_idx || self.char_at(idx) != ',' {
        raise self.error("Expecting ',' delimiter", idx)
      }
      let comma_idx = idx
      idx = self.skip_ws(idx + 1)
      if idx <= end_idx && self.char_at(idx) == '}' {
        raise self.error(
          "Illegal trailing comma before end of object", comma_idx,
        )
      }
    }
  }
  (Json::object(map), idx + 1)
}

///|
fn JsonScanner::parse_array(
  self : JsonScanner,
  start : Int,
) -> (Json, Int) raise JSONDecodeError {
  let end_idx = self.len - 1
  let items : Array[Json] = []
  let mut idx = self.skip_ws(start)
  if idx > end_idx || self.char_at(idx) != ']' {
    while true {
      let (value, after_value) = self.scan_once(idx)
      items.push(value)
      idx = self.skip_ws(after_value)
      if idx <= end_idx && self.char_at(idx) == ']' {
        break
      }
      if idx > end_idx || self.char_at(idx) != ',' {
        raise self.error("Expecting ',' delimiter", idx)
      }
      let comma_idx = idx
      idx = self.skip_ws(idx + 1)
      if idx <= end_idx && self.char_at(idx) == ']' {
        raise self.error(
          "Illegal trailing comma before end of array", comma_idx,
        )
      }
    }
  }
  (Json::array(items), idx + 1)
}

///|
/// Python's `json.loads(s)`.
///
/// Differences from `@json.parse`: accepts `NaN`, `Infinity` and `-Infinity`,
/// reports Python's error messages, and marks floats (`1.0`, `1e3`) so that
/// they keep behaving as Python floats (see `dumps`).
///
/// ```mbt check
/// test {
///   let v = @jmespath.loads("[1, 1.0, 1e3, \"\\u2713\"]")
///   inspect(@jmespath.dumps(v), content="[1,1.0,1000.0,\"\\u2713\"]")
/// }
/// ```
pub fn loads(s : String) -> Json raise JSONDecodeError {
  let scanner = JsonScanner::{ s, len: s.length(), }
  if s.has_prefix("\u{feff}") {
    raise scanner.error("Unexpected UTF-8 BOM (decode using utf-8-sig)", 0)
  }
  let (value, end) = scanner.scan_once(scanner.skip_ws(0))
  let end = scanner.skip_ws(end)
  if end != scanner.len {
    raise scanner.error("Extra data", end)
  }
  value
}

///|
fn dumps_string(buf : StringBuilder, s : String) -> Unit {
  buf.write_char('"')
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).to_int()
    match c {
      0x22 => buf.write_string("\\\"")
      0x5c => buf.write_string("\\\\")
      0x0a => buf.write_string("\\n")
      0x0d => buf.write_string("\\r")
      0x09 => buf.write_string("\\t")
      0x08 => buf.write_string("\\b")
      0x0c => buf.write_string("\\f")
      0x20..=0x7e => buf.write_char(Int::unsafe_to_char(c))
      _ => {
        buf.write_string("\\u")
        let hex = "0123456789abcdef"
        for shift in [12, 8, 4, 0] {
          buf.write_char(
            Int::unsafe_to_char(hex.code_unit_at((c >> shift) & 0xf).to_int()),
          )
        }
      }
    }
  }
  buf.write_char('"')
}

///|
fn dumps_to(buf : StringBuilder, value : Json) -> Unit {
  match value {
    Null => buf.write_string("null")
    True => buf.write_string("true")
    False => buf.write_string("false")
    Number(d, repr~) => buf.write_string(py_number_dumps(d, repr))
    String(s) => dumps_string(buf, s)
    Array(items) => {
      buf.write_char('[')
      for i, item in items {
        if i > 0 {
          buf.write_char(',')
        }
        dumps_to(buf, item)
      }
      buf.write_char(']')
    }
    Object(map) => {
      buf.write_char('{')
      let mut first = true
      for k, v in map {
        if !first {
          buf.write_char(',')
        }
        first = false
        dumps_string(buf, k)
        buf.write_char(':')
        dumps_to(buf, v)
      }
      buf.write_char('}')
    }
  }
}

///|
/// Python's `json.dumps(value, separators=(',', ':'))` (with the default
/// `ensure_ascii=True`): non-ASCII characters are written as `\uXXXX`
/// escapes and Python floats keep their `.0`.
pub fn dumps(value : Json) -> String {
  let buf = StringBuilder()
  dumps_to(buf, value)
  buf.to_string()
}

///|
/// Python's `repr(str)`.  Printability is approximated: C0/C1 controls,
/// DEL, NBSP, soft hyphen and lone surrogates are escaped.
fn py_repr_string(buf : StringBuilder, s : String) -> Unit {
  let quote = if s.contains("'") && !s.contains("\"") { '"' } else { '\'' }
  buf.write_char(quote)
  for c in s {
    let code = c.to_int()
    if c == quote || c == '\\' {
      buf.write_char('\\')
      buf.write_char(c)
    } else if c == '\n' {
      buf.write_string("\\n")
    } else if c == '\r' {
      buf.write_string("\\r")
    } else if c == '\t' {
      buf.write_string("\\t")
    } else if code < 0x20 || (code >= 0x7f && code <= 0xa0) || code == 0xad {
      let hex = "0123456789abcdef"
      buf.write_string("\\x")
      buf.write_char(Int::unsafe_to_char(hex.code_unit_at(code >> 4).to_int()))
      buf.write_char(Int::unsafe_to_char(hex.code_unit_at(code & 0xf).to_int()))
    } else if code >= 0xd800 && code <= 0xdfff {
      let hex = "0123456789abcdef"
      buf.write_string("\\u")
      for shift in [12, 8, 4, 0] {
        buf.write_char(
          Int::unsafe_to_char(hex.code_unit_at((code >> shift) & 0xf).to_int()),
        )
      }
    } else {
      buf.write_char(c)
    }
  }
  buf.write_char(quote)
}

///|
fn py_repr_to(buf : StringBuilder, value : Json) -> Unit {
  match value {
    Null => buf.write_string("None")
    True => buf.write_string("True")
    False => buf.write_string("False")
    Number(d, repr~) => buf.write_string(py_number_str(d, repr))
    String(s) => py_repr_string(buf, s)
    Array(items) => {
      buf.write_char('[')
      for i, item in items {
        if i > 0 {
          buf.write_string(", ")
        }
        py_repr_to(buf, item)
      }
      buf.write_char(']')
    }
    Object(map) => {
      buf.write_char('{')
      let mut first = true
      for k, v in map {
        if !first {
          buf.write_string(", ")
        }
        first = false
        py_repr_string(buf, k)
        buf.write_string(": ")
        py_repr_to(buf, v)
      }
      buf.write_char('}')
    }
  }
}

///|
/// Python's `repr()` of a JSON value (`None`, `True`, `{'a': [1, 2.5]}`).
fn py_repr(value : Json) -> String {
  let buf = StringBuilder()
  py_repr_to(buf, value)
  buf.to_string()
}

///|
/// Python's `str()` (`'%s' % value`): like `repr` except that a top-level
/// string is written as is.
fn py_str(value : Json) -> String {
  match value {
    String(s) => s
    _ => py_repr(value)
  }
}

///|
/// `repr()` of a Python list of strings, e.g. `['string', 'array']`.
fn py_repr_str_list(items : Array[String]) -> String {
  py_repr(Json::array(items.map(Json::string)))
}
