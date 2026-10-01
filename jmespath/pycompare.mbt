// Python equality / ordering semantics for JSON values.

///|
/// `_is_actual_number`: a number that is not a bool (always true for
/// `Json::Number`, since JSON booleans are a separate case).
fn is_actual_number(x : Json) -> Bool {
  x is Number(_, ..)
}

///|
/// Python's `bool`-as-`int` view used by `==` between bools and numbers.
fn bool_as_number(x : Json) -> Double? {
  match x {
    True => Some(1.0)
    False => Some(0.0)
    Number(d, ..) => Some(d)
    _ => None
  }
}

///|
/// `PyObject_RichCompareBool(x, y, Py_EQ)`: identical objects are equal
/// (this only matters for NaN).  Used for container elements and `in`.
fn py_eq_bool(x : Json, y : Json) -> Bool {
  physical_equal(x, y) || py_eq(x, y)
}

///|
/// Python's `x == y` for JSON values: `1 == 1.0`, and (nested) `True == 1`,
/// `False == 0`; dicts compare regardless of key order.  Container elements
/// are compared with the identity shortcut (`py_eq_bool`), so a list holding
/// the very same NaN object equals itself, while a bare NaN never does.
fn py_eq(x : Json, y : Json) -> Bool {
  match (x, y) {
    (Null, Null) => true
    (True, True) | (False, False) => true
    (True, False) | (False, True) => false
    (True | False | Number(_, ..), True | False | Number(_, ..)) =>
      bool_as_number(x).unwrap() == bool_as_number(y).unwrap()
    (String(a), String(b)) => a == b
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if !py_eq_bool(a[i], b[i]) {
          return false
        }
      }
      true
    }
    (Object(a), Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      for k, v in a {
        match b.get(k) {
          Some(w) => if !py_eq_bool(v, w) { return false }
          None => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// `_is_special_number_case`: comparing 0 or 1 with a bool.
fn is_special_number_case(x : Json, y : Json) -> Bool {
  if is_actual_number(x) &&
    (py_eq(x, Json::number(0.0)) || py_eq(x, Json::number(1.0))) {
    y is (True | False)
  } else if is_actual_number(y) &&
    (py_eq(y, Json::number(0.0)) || py_eq(y, Json::number(1.0))) {
    x is (True | False)
  } else {
    false
  }
}

///|
/// `_equals`: Python `==`, except that 0/1 never equal false/true.
fn jmespath_equals(x : Json, y : Json) -> Bool {
  if is_special_number_case(x, y) {
    false
  } else {
    py_eq(x, y)
  }
}

///|
/// `_is_comparable`: numbers and strings can be ordered.
fn is_comparable(x : Json) -> Bool {
  x is (Number(_, ..) | String(_))
}

///|
/// Compares two strings by code point, like Python (core's `String`
/// comparison orders by length first).
fn py_str_compare(a : String, b : String) -> Int {
  let ia = a.iter()
  let ib = b.iter()
  while true {
    match (ia.next(), ib.next()) {
      (None, None) => return 0
      (None, Some(_)) => return -1
      (Some(_), None) => return 1
      (Some(x), Some(y)) =>
        if x != y {
          return if x.to_int() < y.to_int() { -1 } else { 1 }
        }
    }
  }
  0
}

///|
/// Python's type name of a value, as seen by `type(value).__name__`.
fn py_type_name(x : Json) -> String {
  match x {
    Null => "NoneType"
    True | False => "bool"
    Number(d, repr~) => if number_is_float(d, repr) { "float" } else { "int" }
    String(_) => "str"
    Array(_) => "list"
    Object(_) => "dict"
  }
}

///|
/// Python's ordering operators (`<`, `<=`, `>`, `>=`) between numbers or
/// between strings.  Any other combination raises Python's `TypeError`.
fn py_order(op : String, x : Json, y : Json) -> Bool raise JMESPathError {
  let cmp = match (x, y) {
    (Number(a, ..), Number(b, ..)) =>
      // NaN compares false with everything.
      if a.is_nan() || b.is_nan() {
        return false
      } else if a < b {
        -1
      } else if a > b {
        1
      } else {
        0
      }
    (String(a), String(b)) => py_str_compare(a, b)
    _ =>
      raise TypeError(
        "'\{op}' not supported between instances of '\{py_type_name(x)}' and '\{py_type_name(y)}'",
      )
  }
  match op {
    "<" => cmp < 0
    "<=" => cmp <= 0
    ">" => cmp > 0
    ">=" => cmp >= 0
    _ => abort("unknown operator \{op}")
  }
}

///|
/// `_is_false`: JMESPath falsiness (`''`, `[]`, `{}`, `None`, `False`).
fn is_false(value : Json) -> Bool {
  match value {
    String(s) => s == ""
    Array(a) => a.is_empty()
    Object(m) => m.is_empty()
    Null | False => true
    True | Number(_, ..) => false
  }
}

///|
/// `_is_true`
fn is_true(value : Json) -> Bool {
  !is_false(value)
}

///|
/// The code points of a string.  Python strings are code point sequences;
/// a lone surrogate is a code point of its own and never matches half of a
/// surrogate pair.
fn code_points(s : String) -> Array[Char] {
  s.to_array()
}

///|
fn chars_match_at(hay : Array[Char], needle : Array[Char], at : Int) -> Bool {
  for i, c in needle {
    if hay[at + i] != c {
      return false
    }
  }
  true
}

///|
/// Python's `needle in hay` for strings.
fn py_str_contains(hay : String, needle : String) -> Bool {
  let h = code_points(hay)
  let n = code_points(needle)
  for at in 0..<=(h.length() - n.length()) {
    if chars_match_at(h, n, at) {
      return true
    }
  }
  false
}

///|
/// Python's `s.startswith(prefix)`.
fn py_str_startswith(s : String, prefix : String) -> Bool {
  let h = code_points(s)
  let n = code_points(prefix)
  n.length() <= h.length() && chars_match_at(h, n, 0)
}

///|
/// Python's `s.endswith(suffix)`.
fn py_str_endswith(s : String, suffix : String) -> Bool {
  let h = code_points(s)
  let n = code_points(suffix)
  n.length() <= h.length() && chars_match_at(h, n, h.length() - n.length())
}
