// Python semantics needed by the keyword implementations.

///|
/// Raised where upstream would crash with a Python-level error (e.g. a
/// `TypeError` from `len(True)` on a malformed schema).
pub suberror PythonError {
  PythonError(String)
} derive(Debug)

///|
pub impl Show for PythonError with output(self, logger) {
  let PythonError(msg) = self
  logger.write_string(msg)
}

///|
/// Python truthiness of the value a JSON document stands for.
fn truthy(j : Json) -> Bool {
  match j {
    Null | False => false
    True => true
    Number(d, ..) => d != 0.0
    String(s) => s.length() > 0
    Array(xs) => xs.length() > 0
    Object(m) => m.length() > 0
  }
}

///|
/// `len(x)`.
fn py_len(j : Json) -> Int raise PythonError {
  match j {
    String(s) => @unicodedata.py_len(s)
    Array(xs) => xs.length()
    Object(m) => m.length()
    _ =>
      raise PythonError(
        "TypeError: object of type \{type_name(j)} has no len()",
      )
  }
}

///|
/// Python's type name for the value a JSON document stands for.
fn type_name(j : Json) -> String {
  match j {
    Null => "NoneType"
    True | False => "bool"
    String(_) => "str"
    Array(_) => "list"
    Object(_) => "dict"
    Number(_) => if @pycompat.is_int(j) { "int" } else { "float" }
  }
}

///|
/// A Python `int` as JSON.
fn int_json(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
/// Python's numeric comparison `a OP b` (`None` when either side is not a
/// number; comparisons involving NaN are false).
fn num_cmp(a : Json, b : Json) -> Int? raise PythonError {
  match (a, b) {
    (Number(_), Number(_)) => @pycompat.compare_numbers(a, b)
    (True | False, _) | (_, True | False) => {
      // bool is an int in Python
      let to_num = (j : Json) => match j {
        True => int_json(1)
        False => int_json(0)
        _ => j
      }
      num_cmp(to_num(a), to_num(b))
    }
    _ =>
      raise PythonError(
        "TypeError: '<' not supported between instances of '\{type_name(a)}' and '\{type_name(b)}'",
      )
  }
}

///|
fn py_lt(a : Json, b : Json) -> Bool raise PythonError {
  num_cmp(a, b) is Some(c) && c < 0
}

///|
fn py_le(a : Json, b : Json) -> Bool raise PythonError {
  num_cmp(a, b) is Some(c) && c <= 0
}

///|
fn py_gt(a : Json, b : Json) -> Bool raise PythonError {
  num_cmp(a, b) is Some(c) && c > 0
}

///|
fn py_ge(a : Json, b : Json) -> Bool raise PythonError {
  num_cmp(a, b) is Some(c) && c >= 0
}

///|
/// Python `str(x)` for a number (same as `repr`).
fn py_str(j : Json) -> String {
  match j {
    String(s) => s
    _ => @pycompat.repr(j)
  }
}

///|
/// Python's ordering of `str`s (by code point).
fn py_str_compare(a : String, b : String) -> Int {
  let x = @unicodedata.code_points(a)
  let y = @unicodedata.code_points(b)
  for i in 0..<@cmp.minimum(x.length(), y.length()) {
    if x[i] != y[i] {
      return x[i].compare(y[i])
    }
  }
  x.length().compare(y.length())
}

///|
/// `sorted(strings)`.
fn py_sorted(strings : Array[String]) -> Array[String] {
  let out = strings.copy()
  out.sort_by(py_str_compare)
  out
}

///|
/// `schema.get(key)` for object schemas.
fn get_key(schema : Json, key : String) -> Json? {
  match schema {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
/// `key in schema`.
fn has_key(schema : Json, key : String) -> Bool {
  match schema {
    Object(m) => m.contains(key)
    Array(xs) => xs.contains(Json::string(key))
    _ => false
  }
}

///|
/// Iterating a container the way Python's `for x in container` does (dict
/// keys, list items).
fn py_iter(j : Json) -> Array[Json] raise PythonError {
  match j {
    Array(xs) => xs
    Object(m) => m.keys().map(k => Json::string(k)).collect()
    String(s) =>
      @unicodedata.code_points(s).map(c => Json::string(
        @unicodedata.from_code_points([c]),
      ))
    _ =>
      raise PythonError("TypeError: '\{type_name(j)}' object is not iterable")
  }
}
