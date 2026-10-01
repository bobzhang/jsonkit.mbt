///|
fn truncate_middle(s : String, max : Int) -> String {
  let cps = @unicodedata.code_points(s)
  if cps.length() <= max {
    return s
  }
  let i = @cmp.maximum(0, (max - 3) / 2)
  let j = @cmp.maximum(0, max - 3 - i)
  @unicodedata.from_code_points(cps[:i]) +
  "..." +
  @unicodedata.from_code_points(cps[cps.length() - j:])
}

///|
/// Python's `reprlib.repr(x)` (the default `reprlib.Repr` limits: depth 6,
/// 6 list items, 4 dict entries (sorted keys), 30-character strings, 40-digit
/// ints, 30 characters for other objects).
pub fn short_repr(j : Json) -> String {
  short_repr_level(j, 6)
}

///|
fn short_repr_level(j : Json, level : Int) -> String {
  match j {
    String(s) => {
      let cps = @unicodedata.code_points(s)
      let head = @unicodedata.from_code_points(cps[:@cmp.minimum(cps.length(), 30)])
      let rep = repr_string(head)
      let rcps = @unicodedata.code_points(rep)
      if rcps.length() > 30 {
        let i = @cmp.maximum(0, (30 - 3) / 2)
        let j = @cmp.maximum(0, 30 - 3 - i)
        let shortened = repr_string(
          @unicodedata.from_code_points(cps[:i]) +
          @unicodedata.from_code_points(cps[cps.length() - j:]),
        )
        let scps = @unicodedata.code_points(shortened)
        @unicodedata.from_code_points(scps[:i]) +
        "..." +
        @unicodedata.from_code_points(scps[scps.length() - j:])
      } else {
        rep
      }
    }
    Number(_) =>
      if is_int(j) {
        truncate_middle(repr(j), 40)
      } else {
        truncate_middle(repr(j), 30)
      }
    Null | True | False => repr(j)
    Array(xs) =>
      if xs.length() == 0 {
        "[]"
      } else if level <= 0 {
        "[...]"
      } else {
        let pieces = xs[:@cmp.minimum(xs.length(), 6)]
          .iter()
          .map(x => short_repr_level(x, level - 1))
          .collect()
        if xs.length() > 6 {
          pieces.push("...")
        }
        "[" + pieces.join(", ") + "]"
      }
    Object(m) =>
      if m.length() == 0 {
        "{}"
      } else if level <= 0 {
        "{...}"
      } else {
        let keys = m.keys().collect()
        keys.sort_by((a, b) => {
          let x = @unicodedata.code_points(a)
          let y = @unicodedata.code_points(b)
          for i in 0..<@cmp.minimum(x.length(), y.length()) {
            if x[i] != y[i] {
              return x[i].compare(y[i])
            }
          }
          x.length().compare(y.length())
        })
        let pieces = keys[:@cmp.minimum(keys.length(), 4)]
          .iter()
          .map(k => short_repr_level(Json::string(k), level - 1) +
            ": " +
            short_repr_level(m[k], level - 1))
          .collect()
        if m.length() > 4 {
          pieces.push("...")
        }
        "{" + pieces.join(", ") + "}"
      }
  }
}
