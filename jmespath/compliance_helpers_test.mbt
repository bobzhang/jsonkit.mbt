// Shared driver for the generated compliance tests (compliance_*_test.mbt),
// a port of upstream's tests/test_compliance.py.

///|
/// Python's `==` on JSON values (1 == 1.0, True == 1 when nested, dict
/// equality ignores key order), used like upstream's `actual == expected`.
fn compliance_py_eq(x : Json, y : Json) -> Bool {
  let as_number = (v : Json) => {
    match v {
      True => Some(1.0)
      False => Some(0.0)
      Number(d, ..) => Some(d)
      _ => None
    }
  }
  match (x, y) {
    (Null, Null) | (True, True) | (False, False) => true
    (True, False) | (False, True) => false
    (True | False | Number(_, ..), True | False | Number(_, ..)) =>
      as_number(x) == as_number(y)
    (String(a), String(b)) => a == b
    (Array(a), Array(b)) =>
      a.length() == b.length() &&
      a.iter().zip(b.iter()).all(pair => compliance_py_eq(pair.0, pair.1))
    (Object(a), Object(b)) =>
      a.length() == b.length() &&
      a.iter().all(kv => b.get(kv.0) is Some(w) && compliance_py_eq(kv.1, w))
    _ => false
  }
}

///|
/// Whether `err` matches the compliance error category.  Upstream only
/// checks that a `ValueError` is raised; this also checks the exception
/// class that corresponds to the category.
fn compliance_error_matches(
  err : @jmespath.JMESPathError,
  kind : String,
) -> Bool {
  err.is_value_error() &&
  (match kind {
    "syntax" =>
      err
      is (ParseError(..)
      | IncompleteExpressionError(..)
      | LexerError(..)
      | EmptyExpressionError)
    "invalid-arity" => err.is_arity_error()
    "invalid-type" => err is JMESPathTypeError(..)
    "unknown-function" => err is UnknownFunctionError(_)
    "invalid-value" => err is ValueError(_)
    _ => false
  })
}

///|
fn run_compliance_case(
  suite : Json,
  group : Int,
  case_index : Int,
) -> Unit raise {
  guard suite is Array(groups) &&
    groups[group] is { "given": given, "cases": Array(cases), .. } &&
    cases[case_index] is Object(case_) &&
    case_.get("expression") is Some(String(expression)) else {
    fail("malformed compliance case")
  }
  if case_.get("result") is Some(expected) {
    let parsed = @jmespath.compile(expression) catch {
      e =>
        fail(
          "jmespath expression failed to compile: \"\{expression}\", error: \{e}",
        )
    }
    let actual = parsed.search(given)
    if !compliance_py_eq(actual, expected) {
      fail(
        "The expression '\{expression}' was suppose to give:\n\{@jmespath.dumps(expected)}\nInstead it matched:\n\{@jmespath.dumps(actual)}",
      )
    }
  } else if case_.get("error") is Some(String(kind)) {
    let outcome = @jmespath.compile(expression).search(given) catch {
      err => {
        if !compliance_error_matches(err, kind) {
          fail(
            "The expression '\{expression}' was suppose to be a \{kind} error, but it raised: \{err}",
          )
        }
        return
      }
    }
    fail(
      "The expression '\{expression}' was suppose to be a \{kind} error, but it returned: \{@jmespath.dumps(outcome)}",
    )
  } else {
    // Benchmark-only case ("bench": "parse"): it must compile.
    @jmespath.compile(expression) |> ignore
  }
}
