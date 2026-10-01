// Port of upstream tests/test_search.py.

///|
test "search: can provide dict cls" {
  // Upstream passes Options(dict_cls=OrderedDict); `Map` is always ordered.
  let result = @jmespath.search("{a: a, b: b, c: c}.*", {
    "c": "c",
    "b": "b",
    "a": "a",
    "d": "d",
  })
  json_inspect(result, content=["a", "b", "c"])
}

///|
test "search: can provide custom functions" {
  let custom_functions = @jmespath.Functions::new()
  custom_functions.register_function(
    "custom_add",
    [@jmespath.ArgSpec::new(["number"]), @jmespath.ArgSpec::new(["number"])],
    args => {
      guard args is [Data(Number(x, ..)), Data(Number(y, ..))] else {
        Json::null()
      }
      Json::number(x + y)
    },
  )
  custom_functions.register_function(
    "my_subtract",
    [@jmespath.ArgSpec::new(["number"]), @jmespath.ArgSpec::new(["number"])],
    args => {
      guard args is [Data(Number(x, ..)), Data(Number(y, ..))] else {
        Json::null()
      }
      Json::number(x - y)
    },
  )
  let options = @jmespath.Options::new(custom_functions~)
  json_inspect(
    @jmespath.search("custom_add(`1`, `2`)", {}, options~),
    content=3,
  )
  json_inspect(
    @jmespath.search("my_subtract(`10`, `3`)", {}, options~),
    content=7,
  )
  // Should still be able to use the original functions without any
  // interference from the custom functions.
  json_inspect(@jmespath.search("length(`[1, 2]`)", {}), content=2)
  // ... and the default table is not affected.
  try @jmespath.search("custom_add(`1`, `2`)", {}) catch {
    UnknownFunctionError(msg) => assert_eq(msg, "Unknown function: custom_add()")
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected UnknownFunctionError")
  }
}

// TestPythonSpecificCases

///|
test "search: can compare strings" {
  // This is python specific behavior that's not in the official spec yet.
  json_inspect(
    @jmespath.search("a < b", { "a": "2016", "b": "2017" }),
    content=true,
  )
}

// test_can_handle_long_ints (Python 2 `long`) and
// test_can_handle_decimals_as_numeric_type (`decimal.Decimal` values) are
// skipped: JSON values here are always `Json`.  Large integers are covered
// below instead.

///|
test "search: can handle large ints" {
  let data = @jmespath.loads("[{\"a\": 123456789012345678901234567890}]")
  let result = @jmespath.search("[?a >= `1`].a", data)
  inspect(@jmespath.dumps(result), content="[123456789012345678901234567890]")
}
