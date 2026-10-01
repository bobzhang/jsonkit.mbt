// Port of upstream tests/test_functions.py.
//
// test_can_max_datetimes is skipped: it relies on Python `datetime` objects
// in the input data, which cannot be represented as JSON.

///|
fn search_error(expression : String, data : Json) -> @jmespath.JMESPathError {
  try @jmespath.search(expression, data) catch {
    e => e
  } noraise {
    v => abort("expected an error, got \{@jmespath.dumps(v)}")
  }
}

///|
test "functions: type error messages" {
  let exception = search_error("length(@)", 2)
  guard exception is JMESPathTypeError(..) else {
    fail("expected JMESPathTypeError")
  }
  let message = exception.to_string()
  // 1. Function name should be in error message
  assert_true(message.contains("length()"))
  // 2. Mention it's an invalid type
  assert_true(message.contains("invalid type for value: 2"))
  // 3. Mention the valid types:
  assert_true(message.contains("expected one of: ['string', 'array', 'object']"))
  // 4. Mention the actual type.
  assert_true(message.contains("received: \"number\""))
}

///|
test "functions: singular in error message" {
  let exception = search_error("length(@, @)", [0, 1])
  guard exception is ArityError(..) else { fail("expected ArityError") }
  assert_eq(
    exception.to_string(),
    "Expected 1 argument for function length(), received 2",
  )
}

///|
test "functions: error message is pluralized" {
  let exception = search_error("sort_by(@)", [0, 1])
  guard exception is ArityError(..) else { fail("expected ArityError") }
  assert_eq(
    exception.to_string(),
    "Expected 2 arguments for function sort_by(), received 1",
  )
}

///|
test "functions: variadic is pluralized" {
  let exception = search_error("not_null()", "foo")
  guard exception is VariadictArityError(..) else {
    fail("expected VariadictArityError")
  }
  assert_eq(
    exception.to_string(),
    "Expected at least 1 argument for function not_null(), received 0",
  )
}
