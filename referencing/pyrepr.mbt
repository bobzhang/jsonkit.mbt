///|
/// Python's `repr()` of a `str`.
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

///|
fn py_number_repr(d : Double, repr : String?) -> String {
  if repr is Some(r) &&
    !r.contains(".") &&
    !r.contains("e") &&
    !r.contains("E") {
    return r
  }
  if d == d.floor() && d.abs() < 1.0e16 {
    d.to_int64().to_string()
  } else {
    d.to_string()
  }
}

///|
/// Python's `repr()` of the deserialized JSON value (`json.loads` output),
/// e.g. `{'foo': [1, True, None]}`.
fn py_repr(j : Json) -> String {
  let sb = StringBuilder()
  write_py_repr(sb, j)
  sb.to_string()
}

///|
fn write_py_repr(sb : StringBuilder, j : Json) -> Unit {
  match j {
    Null => sb.write_string("None")
    True => sb.write_string("True")
    False => sb.write_string("False")
    Number(d, repr~) => sb.write_string(py_number_repr(d, repr))
    String(s) => sb.write_string(py_str_repr(s))
    Array(xs) => {
      sb.write_char('[')
      for i, x in xs {
        if i > 0 {
          sb.write_string(", ")
        }
        write_py_repr(sb, x)
      }
      sb.write_char(']')
    }
    Object(m) => {
      sb.write_char('{')
      let mut first = true
      for k, v in m {
        if !first {
          sb.write_string(", ")
        }
        first = false
        sb.write_string(py_str_repr(k))
        sb.write_string(": ")
        write_py_repr(sb, v)
      }
      sb.write_char('}')
    }
  }
}

///|
/// Python's `str()` of a deserialized JSON value (strings are not quoted).
fn py_str(j : Json) -> String {
  match j {
    String(s) => s
    _ => py_repr(j)
  }
}

///|
/// Python truthiness of a deserialized JSON value.
fn py_truthy(j : Json) -> Bool {
  match j {
    Null | False => false
    True => true
    Number(d, ..) => d != 0.0
    String(s) => s != ""
    Array(xs) => !xs.is_empty()
    Object(m) => !m.is_empty()
  }
}
