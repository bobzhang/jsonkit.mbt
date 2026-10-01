// Port of upstream tests/test_custom_functions.py.

///|
/// `class CustomFunctions(functions.Functions)` with `_func_length0`.
fn custom_functions() -> @jmespath.Functions {
  let functions = @jmespath.Functions::new()
  functions.register_function(
    "length0",
    [@jmespath.ArgSpec::new(["string", "array", "object", "null"])],
    args => {
      match args[0] {
        Data(Null) => Json::number(0.0)
        Data(String(s)) => Json::number(s.char_length().to_double())
        Data(Array(items)) => Json::number(items.length().to_double())
        Data(Object(map)) => Json::number(map.length().to_double())
        _ => Json::null()
      }
    },
  )
  functions
}

///|
test "custom functions: null to nonetype" {
  let options = @jmespath.Options::new(custom_functions=custom_functions())
  let data : Json = { "a": { "b": [1, 2, 3] } }
  json_inspect(@jmespath.search("length0(a.b)", data, options~), content=3)
  json_inspect(@jmespath.search("length0(a.c)", data, options~), content=0)
}

///|
test "custom functions: signature is enforced" {
  let options = @jmespath.Options::new(custom_functions=custom_functions())
  try @jmespath.search("length0(`1`)", {}, options~) catch {
    e =>
      inspect(
        e,
        content="In function length0(), invalid type for value: 1, expected one of: ['string', 'array', 'object', 'null'], received: \"number\"",
      )
  } noraise {
    _ => fail("expected a type error")
  }
  try @jmespath.search("length0()", {}, options~) catch {
    e =>
      inspect(
        e,
        content="Expected 1 argument for function length0(), received 0",
      )
  } noraise {
    _ => fail("expected an arity error")
  }
}

///|
test "custom functions: builtins can be overridden and use exprefs" {
  let functions = custom_functions()
  // A custom function taking an expression reference, like map().
  functions.register_function(
    "count_if",
    [@jmespath.ArgSpec::new(["expref"]), @jmespath.ArgSpec::new(["array"])],
    args => {
      guard args is [Expref(expref), Data(Array(items))] else { Json::null() }
      let mut n = 0
      for item in items {
        if expref.visit(item) is True {
          n += 1
        }
      }
      Json::number(n.to_double())
    },
  )
  // Override a builtin.
  functions.register_function("abs", [@jmespath.ArgSpec::new([])], _ => {
    Json::string("overridden")
  })
  let options = @jmespath.Options::new(custom_functions=functions)
  json_inspect(
    @jmespath.search("count_if(&(@ > `1`), @)", [1, 2, 3], options~),
    content=2,
  )
  json_inspect(@jmespath.search("abs('x')", {}, options~), content="overridden")
  assert_true(functions.names().contains("length0"))
  assert_true(functions.get("sort_by") is Some(_))
}
