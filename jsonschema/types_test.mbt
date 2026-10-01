// Ports of upstream's `jsonschema/tests/test_types.py`.

///|
fn equals_2(_ : @jsonschema.TypeChecker, instance : Json) -> Bool raise {
  instance == Json::number(2.0)
}

///|
fn is_str(_ : @jsonschema.TypeChecker, instance : Json) -> Bool raise {
  instance is String(_)
}

///|
fn is_number_(_ : @jsonschema.TypeChecker, instance : Json) -> Bool raise {
  instance is Number(_)
}

///|
test "TypeChecker" {
  let checker = @jsonschema.TypeChecker::new(type_checkers=[("two", equals_2)])
  debug_inspect(
    (checker.is_type(2, "two"), checker.is_type("bar", "two")),
    content="(true, false)",
  )
  // unknown types
  try @jsonschema.TypeChecker::new().is_type(4, "foobar") catch {
    @jsonschema.UndefinedTypeCheck(_) as e =>
      assert_true(e.to_string().contains("'foobar' is unknown to this type checker"))
    _ => fail("expected UndefinedTypeCheck")
  } noraise {
    _ => fail("expected UndefinedTypeCheck")
  }
  // checks can be added at init
  assert_true(checker == @jsonschema.TypeChecker::new().redefine("two", equals_2))
  // redefine an existing type
  assert_true(
    @jsonschema.TypeChecker::new().redefine("two", is_str).redefine("two", equals_2) ==
    @jsonschema.TypeChecker::new().redefine("two", equals_2),
  )
  // remove
  assert_true(checker.remove(["two"]) == @jsonschema.TypeChecker::new())
  try @jsonschema.TypeChecker::new().remove(["foobar"]) catch {
    e => assert_true(e.to_string().contains("foobar"))
  } noraise {
    _ => fail("expected UndefinedTypeCheck")
  }
  // redefine many / remove multiple
  assert_true(
    @jsonschema.TypeChecker::new().redefine_many([("foo", is_number_), ("bar", is_str)]) ==
    @jsonschema.TypeChecker::new().redefine("foo", is_number_).redefine("bar", is_str),
  )
  assert_true(
    @jsonschema.TypeChecker::new(type_checkers=[("foo", is_number_), ("bar", is_str)]).remove([
      "foo", "bar",
    ]) ==
    @jsonschema.TypeChecker::new(),
  )
  inspect(
    @jsonschema.TypeChecker::new(type_checkers=[("foo", is_str), ("bar", is_str)]),
    content="<TypeChecker types={'bar', 'foo'}>",
  )
}

///|
suberror KeyErrorLike {
  KeyErrorLike(String)
}

///|
test "a type check can raise a KeyError" {
  let checker = @jsonschema.TypeChecker::new(type_checkers=[
    ("foo", (_, _) => raise KeyErrorLike("Stuff")),
  ])
  try checker.is_type(4, "foo") catch {
    KeyErrorLike(s) => inspect(s, content="Stuff")
    _ => fail("expected the checker's own error")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "custom types: simple types can be extended" {
  let int_or_str_int = fn(_ : @jsonschema.TypeChecker, instance : Json) -> Bool raise {
    match instance {
      Number(_) => @jsonschema.draft202012_type_checker.is_type(instance, "integer")
      String(s) => (try? @string.parse_int(s)) is Ok(_)
      _ => false
    }
  }
  let custom = @jsonschema.extend(
    @jsonschema.draft202012_validator,
    type_checker=@jsonschema.draft202012_validator.type_checker.redefine(
      "integer", int_or_str_int,
    ),
  )
  let validator = custom.new({ "type": "integer" })
  validator.validate(4)
  validator.validate("4")
  assert_false(validator.is_valid(4.4))
  assert_false(validator.is_valid("foo"))
}

///|
test "custom types: unknown types" {
  try @jsonschema.draft202012_validator.new({}).is_type(12, "some unknown type") catch {
    @jsonschema.UnknownType(_) as e =>
      assert_true(e.to_string().contains("'some unknown type'"))
    _ => fail("expected UnknownType")
  } noraise {
    _ => fail("expected UnknownType")
  }
}

///|
test "draft 3 / 4 integers are Python ints" {
  let one_point_zero = @jsonschema.loads("1.0")
  assert_false(@jsonschema.draft3_type_checker.is_type(one_point_zero, "integer"))
  assert_false(@jsonschema.draft4_type_checker.is_type(one_point_zero, "integer"))
  assert_true(@jsonschema.draft6_type_checker.is_type(one_point_zero, "integer"))
  assert_true(@jsonschema.draft4_type_checker.is_type(@jsonschema.loads("1"), "integer"))
  assert_false(@jsonschema.draft6_type_checker.is_type(true, "integer"))
  assert_false(@jsonschema.draft6_type_checker.is_type(false, "number"))
  assert_true(@jsonschema.draft3_type_checker.is_type(null, "any"))
  try @jsonschema.draft4_type_checker.is_type(null, "any") catch {
    @jsonschema.UndefinedTypeCheck(_) => ()
    _ => fail("expected UndefinedTypeCheck")
  } noraise {
    _ => fail("expected UndefinedTypeCheck")
  }
}
