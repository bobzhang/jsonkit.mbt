///|
/// An element of an error's (instance or schema) path: an object key or an
/// array index, like the `str | int` items of upstream's path deques.
pub(all) enum PathItem {
  Key(String)
  Index(Int)
} derive(Eq, Compare, Hash, Debug)

///|
/// `repr(item)`: `'key'` or `3`.
pub fn PathItem::repr(self : PathItem) -> String {
  match self {
    Key(k) => @pycompat.repr_string(k)
    Index(i) => i.to_string()
  }
}

///|
/// The item as a JSON value (`"key"` or `3`).
pub fn PathItem::to_json(self : PathItem) -> Json {
  match self {
    Key(k) => Json::string(k)
    Index(i) => Json::number(i.to_double())
  }
}

///|
pub impl Show for PathItem with output(self, logger) {
  match self {
    Key(k) => logger.write_string(k)
    Index(i) => logger.write_string(i.to_string())
  }
}

///|
/// Python's `repr(x)` of the value a JSON document stands for, e.g.
/// `{'a': [1, 2.5, None, True]}`.
pub fn py_repr(value : Json) -> String {
  @pycompat.repr(value)
}

///|
/// Construct a single string containing indexing operations for the indices.
///
/// For example for a container `bar`, `[1, 2, "foo"]` gives `bar[1][2]['foo']`.
fn format_as_index(container : String, indices : ArrayView[PathItem]) -> String {
  if indices.length() == 0 {
    return container
  }
  container + "[" + indices.iter().map(i => i.repr()).join("][") + "]"
}

///|
/// Return the additional properties of `instance` (assumed to be an object):
/// those neither in `properties` nor matched by `patternProperties`.
fn find_additional_properties(
  instance : Map[String, Json],
  schema : Json,
) -> Array[String] raise {
  let properties = match schema {
    Object({ "properties": Object(p), .. }) => Some(p)
    _ => None
  }
  let patterns = match schema {
    Object({ "patternProperties": Object(pp), .. }) => pp.keys().join("|")
    _ => ""
  }
  let out = []
  for property, _ in instance {
    if properties is Some(p) && p.contains(property) {
      continue
    }
    if patterns != "" && @regex.search(patterns, property) {
      continue
    }
    out.push(property)
  }
  out
}

///|
/// Create an error message for extra items or properties.
fn extras_msg(extras : ArrayView[Json]) -> (String, String) {
  let verb = if extras.length() == 1 { "was" } else { "were" }
  (extras.iter().map(e => @pycompat.repr(e)).join(", "), verb)
}

///|
/// Wrap `thing` in a list if it's a single string; otherwise return its
/// items.
fn ensure_list(thing : Json) -> Array[Json] {
  match thing {
    String(_) => [thing]
    Array(xs) => xs
    _ => [thing]
  }
}

///|
/// Check if two JSON values are equal with Python semantics: `bool` is not
/// a number (`True != 1`), ints and floats compare numerically (`1 == 1.0`),
/// arrays compare element-wise and objects compare irrespective of order.
pub fn equal(one : Json, two : Json) -> Bool {
  match (one, two) {
    (String(a), String(b)) => a == b
    (String(_), _) | (_, String(_)) => false
    (Array(xs), Array(ys)) => {
      if xs.length() != ys.length() {
        return false
      }
      for i, x in xs {
        if !equal(x, ys[i]) {
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
          Some(w) if equal(v, w) => ()
          _ => return false
        }
      }
      true
    }
    (True, True) | (False, False) | (Null, Null) => true
    (Number(x, ..), Number(y, ..)) =>
      if x.is_nan() && y.is_nan() {
        // `json.loads` hands out a single shared `NaN` object, so NaNs from
        // the same source compare identical (`one is two`); distinct NaN bit
        // patterns stand for distinct objects.
        x.reinterpret_as_uint64() == y.reinterpret_as_uint64()
      } else {
        @pycompat.numbers_equal(one, two)
      }
    _ => false
  }
}

///|
/// A canonical key compatible with `equal` (`None` when the value contains a
/// NaN, which needs the brute-force comparison).
fn uniq_key(value : Json, sb : StringBuilder) -> Bool {
  match value {
    Null => sb.write_char('z')
    True => sb.write_char('t')
    False => sb.write_char('f')
    String(s) => {
      sb.write_char('s')
      sb.write_string(s.length().to_string())
      sb.write_char(':')
      sb.write_string(s)
    }
    Number(d, ..) => {
      if d.is_nan() {
        return false
      }
      sb.write_char('n')
      if d.is_inf() {
        sb.write_string(if d > 0.0 { "inf" } else { "-inf" })
      } else if @pycompat.is_int(value) {
        sb.write_string(@pycompat.int_value(value).to_string())
      } else if @pycompat.is_whole(d) {
        sb.write_string(@pycompat.bigint_of_whole_double(d).to_string())
      } else {
        sb.write_string(@pycompat.repr_float(d))
      }
      sb.write_char(';')
    }
    Array(xs) => {
      sb.write_char('[')
      for x in xs {
        if !uniq_key(x, sb) {
          return false
        }
        sb.write_char(',')
      }
      sb.write_char(']')
    }
    Object(m) => {
      let keys = m.keys().collect()
      keys.sort()
      sb.write_char('{')
      for k in keys {
        sb.write_string(k.length().to_string())
        sb.write_char(':')
        sb.write_string(k)
        if !uniq_key(m[k], sb) {
          return false
        }
        sb.write_char(',')
      }
      sb.write_char('}')
    }
  }
  true
}

///|
/// Check if all of a container's elements are unique (under `equal`).
///
/// Uses a structural key compatible with `equal`, falling back to brute
/// force for values containing NaN.
fn uniq(container : ArrayView[Json]) -> Bool {
  let seen : Set[String] = Set([])
  let unsupported : Array[Json] = []
  for element in container {
    let sb = StringBuilder()
    if uniq_key(element, sb) {
      let key = sb.to_string()
      if seen.contains(key) {
        return false
      }
      seen.add(key)
    } else {
      for previous in unsupported {
        if equal(previous, element) {
          return false
        }
      }
      unsupported.push(element)
    }
  }
  true
}

///|
/// Parse a JSON document exactly like Python's `json.loads`, keeping the
/// `int` / `float` distinction: float-like tokens (`1.0`, `1e3`, `NaN`,
/// `Infinity`) and integers too large for a double keep their spelling in
/// `Json::Number`'s `repr~`. Use this to load schemas and instances when
/// the draft 3 / 4 notion of `integer`, or Python-exact error messages,
/// matter.
pub fn loads(s : String) -> Json raise @pycompat.JSONDecodeError {
  @pycompat.loads(s)
}
