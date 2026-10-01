///|
/// Substring by UTF-16 code-unit offsets (Python-style slicing with clamping).
fn substr(s : String, start : Int, end? : Int) -> String {
  let len = s.length()
  let end = match end {
    Some(e) => if e < 0 { 0 } else if e > len { len } else { e }
    None => len
  }
  let start = if start < 0 { 0 } else if start > end { end } else { start }
  s.view(start_offset=start, end_offset=end).to_owned()
}

///|
/// Python's `str.partition(sep)`.
fn partition(s : String, sep : String) -> (String, Bool, String) {
  match s.find(sep) {
    Some(i) => (substr(s, 0, end=i), true, substr(s, i + sep.length()))
    None => (s, false, "")
  }
}

///|
/// Python's `str.rpartition(sep)`.
fn rpartition(s : String, sep : String) -> (String, Bool, String) {
  match s.rev_find(sep) {
    Some(i) => (substr(s, 0, end=i), true, substr(s, i + sep.length()))
    None => ("", false, s)
  }
}

///|
/// Python's `str.split(sep)` (all occurrences, keeping empty pieces).
fn split_all(s : String, sep : String) -> Array[String] {
  s.split(sep).map(v => v.to_owned()).to_array()
}

///|
fn is_ascii_alpha(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_ascii_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ascii_hex(c : UInt16) -> Bool {
  is_ascii_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn ascii_lower(s : String) -> String {
  let sb = StringBuilder()
  for i in 0..<s.length() {
    let c = s[i]
    if c >= 'A' && c <= 'Z' {
      sb.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      sb.write_char(c.to_int().unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
/// Python's `repr()` of a `str` (used in error messages).
fn py_str_repr(s : String) -> String {
  let quote = if s.contains("'") && !s.contains("\"") { '"' } else { '\'' }
  let sb = StringBuilder()
  sb.write_char(quote)
  for c in s {
    if c == quote || c == '\\' {
      sb.write_char('\\')
      sb.write_char(c)
    } else if c == '\n' {
      sb.write_string("\\n")
    } else if c == '\r' {
      sb.write_string("\\r")
    } else if c == '\t' {
      sb.write_string("\\t")
    } else if c.to_int() < 0x20 || (c.to_int() >= 0x7f && c.to_int() < 0xa0) {
      let hex = c.to_int().to_string(radix=16)
      sb.write_string(if hex.length() < 2 { "\\x0" + hex } else { "\\x" + hex })
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char(quote)
  sb.to_string()
}
