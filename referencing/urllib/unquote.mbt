///|
fn hex_value(c : UInt16) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else {
    c.to_int() - 'A'.to_int() + 10
  }
}

///|
/// Python's `_unquote_impl` on an ASCII-only run, then decoded as UTF-8 with
/// `errors='replace'`.
fn unquote_ascii_run(run : StringView) -> String {
  let bytes = Buffer()
  let n = run.length()
  let mut i = 0
  while i < n {
    let c = run[i]
    if c == '%' && i + 2 < n && is_ascii_hex(run[i + 1]) && is_ascii_hex(run[i + 2]) {
      bytes.write_byte(
        (hex_value(run[i + 1]) * 16 + hex_value(run[i + 2])).to_byte(),
      )
      i += 3
    } else {
      bytes.write_byte(c.to_byte())
      i += 1
    }
  }
  @utf8.decode_lossy(bytes.to_bytes())
}

///|
/// Replace `%xx` escapes by their single-character equivalent, exactly like
/// Python's `urllib.parse.unquote(string)` (UTF-8, `errors='replace'`).
///
/// Percent-encoded sequences are decoded as UTF-8, with invalid sequences
/// replaced by U+FFFD. Only maximal runs of ASCII characters are decoded;
/// non-ASCII characters pass through untouched.
///
/// ```mbt check
/// test {
///   inspect(@urllib.unquote("abc%20def"), content="abc def")
///   inspect(@urllib.unquote("%E2%82%AC%zz"), content="€%zz")
/// }
/// ```
pub fn unquote(s : String) -> String {
  if !s.contains("%") {
    return s
  }
  let out = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let start = i
    if s[i] < 0x80 {
      while i < n && s[i] < 0x80 {
        i += 1
      }
      out.write_string(unquote_ascii_run(s.view(start_offset=start, end_offset=i)))
    } else {
      while i < n && s[i] >= 0x80 {
        i += 1
      }
      out.write_view(s.view(start_offset=start, end_offset=i))
    }
  }
  out.to_string()
}
