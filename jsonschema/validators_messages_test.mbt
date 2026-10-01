// Ports of `TestValidationErrorMessages` from upstream's
// `jsonschema/tests/test_validators.py`.

///|
fn message_for(
  instance : Json,
  schema : Json,
  cls? : @jsonschema.ValidatorClass = @jsonschema.latest_version(),
  format_checker? : @jsonschema.FormatChecker,
) -> String raise {
  cls.check_schema(schema)
  let validator = cls.new(schema, format_checker?)
  let errors = validator.iter_errors(instance).to_array()
  assert_true(errors.length() > 0, msg="No errors were raised")
  assert_eq(errors.length(), 1, msg="Expected exactly one error")
  errors[0].message
}

///|
test "single type failure" {
  inspect(
    message_for(1, { "type": "string" }),
    content="1 is not of type 'string'",
  )
  inspect(
    message_for(1, { "type": ["string"] }),
    content="1 is not of type 'string'",
  )
  inspect(
    message_for(1, { "type": ["string", "object"] }),
    content="1 is not of type 'string', 'object'",
  )
}

///|
test "object with named type failure (draft 3)" {
  inspect(
    message_for(
      1,
      { "type": [{ "name": "Foo", "minimum": 3 }] },
      cls=@jsonschema.draft3_validator,
    ),
    content="1 is not of type 'Foo'",
  )
  inspect(
    message_for(
      1,
      { "type": [{ "type": [{ "minimum": 3 }] }] },
      cls=@jsonschema.draft3_validator,
    ),
    content="1 is not of type {'type': [{'minimum': 3}]}",
  )
}

///|
test "minimum / maximum" {
  inspect(
    message_for(1, { "minimum": 2 }),
    content="1 is less than the minimum of 2",
  )
  inspect(
    message_for(1, { "maximum": 0 }),
    content="1 is greater than the maximum of 0",
  )
}

///|
test "dependencies" {
  inspect(
    message_for(
      { "bar": 2 },
      { "dependencies": { "bar": "foo" } },
      cls=@jsonschema.draft3_validator,
    ),
    content="'foo' is a dependency of 'bar'",
  )
  inspect(
    message_for(
      { "bar": 2 },
      { "dependencies": { "bar": ["foo"] } },
      cls=@jsonschema.draft3_validator,
    ),
    content="'foo' is a dependency of 'bar'",
  )
  inspect(
    message_for(
      { "bar": 2 },
      { "dependencies": { "bar": ["foo"] } },
      cls=@jsonschema.draft7_validator,
    ),
    content="'foo' is a dependency of 'bar'",
  )
}

///|
test "additionalItems" {
  let message = message_for(
    [2],
    { "items": [], "additionalItems": false },
    cls=@jsonschema.draft3_validator,
  )
  assert_true(message.contains("(2 was unexpected)"))
  let message = message_for(
    [1, 2, 3],
    { "items": [], "additionalItems": false },
    cls=@jsonschema.draft3_validator,
  )
  assert_true(message.contains("(1, 2, 3 were unexpected)"))
}

///|
test "additionalProperties" {
  let message = message_for({ "foo": 2 }, { "additionalProperties": false })
  assert_true(message.contains("('foo' was unexpected)"))
  let message = message_for({ "foo": null, "bar": null }, {
    "additionalProperties": false,
  })
  assert_true(message.contains("'foo'"))
  assert_true(message.contains("'bar'"))
  assert_true(message.contains("were unexpected)"))
}

///|
test "const / contains (draft 6)" {
  assert_true(message_for({ "foo": "bar" }, { "const": 12 }).contains("12 was expected"))
  inspect(
    message_for(
      [2, {}, []],
      { "contains": { "const": 12 } },
      cls=@jsonschema.draft6_validator,
    ),
    content="None of [2, {}, []] are valid under the given schema",
  )
}

///|
test "invalid format default message" {
  let checker = @jsonschema.FormatChecker::new(formats=[])
  checker.checks("thing", _ => false)
  let message = message_for("bla", { "format": "thing" }, format_checker=checker)
  assert_true(message.contains("'bla'"))
  assert_true(message.contains("'thing'"))
  assert_true(message.contains("is not a"))
}

///|
test "additionalProperties false with patternProperties" {
  let schema : Json = {
    "type": "object",
    "additionalProperties": false,
    "patternProperties": {
      "^abc$": { "type": "string" },
      "^def$": { "type": "string" },
    },
  }
  inspect(
    message_for({ "zebra": 123 }, schema, cls=@jsonschema.draft4_validator),
    content="'zebra' does not match any of the regexes: '^abc$', '^def$'",
  )
  inspect(
    message_for(
      { "zebra": 123, "fish": 456 },
      schema,
      cls=@jsonschema.draft4_validator,
    ),
    content="'fish', 'zebra' do not match any of the regexes: '^abc$', '^def$'",
  )
}

///|
test "False schema / multipleOf" {
  inspect(
    message_for("something", false),
    content="False schema does not allow 'something'",
  )
  inspect(
    message_for(3, { "multipleOf": 2 }),
    content="3 is not a multiple of 2",
  )
}

///|
test "array and string lengths" {
  inspect(message_for([], { "minItems": 2 }), content="[] is too short")
  inspect(
    message_for([1, 2, 3], { "maxItems": 2 }),
    content="[1, 2, 3] is too long",
  )
  inspect(message_for([], { "minItems": 1 }), content="[] should be non-empty")
  inspect(
    message_for([1, 2, 3], { "maxItems": 0 }),
    content="[1, 2, 3] is expected to be empty",
  )
  inspect(message_for("", { "minLength": 2 }), content="'' is too short")
  inspect(message_for("abc", { "maxLength": 2 }), content="'abc' is too long")
  inspect(
    message_for("", { "minLength": 1 }),
    content="'' should be non-empty",
  )
  inspect(
    message_for("abc", { "maxLength": 0 }),
    content="'abc' is expected to be empty",
  )
}

///|
test "property counts" {
  inspect(
    message_for({}, { "minProperties": 2 }),
    content="{} does not have enough properties",
  )
  inspect(
    message_for({ "a": {}, "b": {}, "c": {} }, { "maxProperties": 2 }),
    content="{'a': {}, 'b': {}, 'c': {}} has too many properties",
  )
  inspect(
    message_for({}, { "minProperties": 1 }),
    content="{} should be non-empty",
  )
  // upstream uses the (non-JSON) instance {1: 2}
  inspect(
    message_for({ "1": 2 }, { "maxProperties": 0 }),
    content="{'1': 2} is expected to be empty",
  )
}

///|
test "prefixItems with items" {
  inspect(
    message_for([1, 2, "foo"], { "items": false, "prefixItems": [{}, {}] }),
    content="Expected at most 2 items but found 1 extra: 'foo'",
  )
  inspect(
    message_for([1, 2, "foo", 5], { "items": false, "prefixItems": [{}, {}] }),
    content="Expected at most 2 items but found 2 extra: ['foo', 5]",
  )
  inspect(
    message_for(["foo", "bar", "baz"], { "prefixItems": [{}], "items": false }),
    content="Expected at most 1 item but found 2 extra: ['bar', 'baz']",
  )
  inspect(
    message_for(["foo", "bar", 37], { "prefixItems": [{}], "items": false }),
    content="Expected at most 1 item but found 2 extra: ['bar', 37]",
  )
}

///|
test "pattern" {
  inspect(
    message_for("bbb", { "pattern": "^a*$" }),
    content="'bbb' does not match '^a*$'",
  )
}

///|
test "contains" {
  inspect(
    message_for([], { "contains": { "type": "string" } }),
    content="[] does not contain items matching the given schema",
  )
  inspect(
    message_for(["foo", 1], { "contains": { "type": "string" }, "minContains": 2 }),
    content="Too few items match the given schema (expected at least 2 but only 1 matched)",
  )
  inspect(
    message_for(["foo", 1], {
      "contains": { "type": "string" },
      "minContains": 2,
      "maxContains": 4,
    }),
    content="Too few items match the given schema (expected at least 2 but only 1 matched)",
  )
  inspect(
    message_for(["foo", "bar", "baz"], {
      "contains": { "type": "string" },
      "maxContains": 2,
    }),
    content="Too many items match the given schema (expected at most 2)",
  )
  inspect(
    message_for(["foo", "foo", "foo", "foo", "foo"], {
      "contains": { "type": "string" },
      "minContains": 2,
      "maxContains": 4,
    }),
    content="Too many items match the given schema (expected at most 4)",
  )
}

///|
test "exclusive bounds" {
  inspect(
    message_for(3, { "exclusiveMinimum": 5 }),
    content="3 is less than or equal to the minimum of 5",
  )
  inspect(
    message_for(3, { "exclusiveMaximum": 2 }),
    content="3 is greater than or equal to the maximum of 2",
  )
}

///|
test "required / dependentRequired" {
  inspect(
    message_for({}, { "required": ["foo"] }),
    content="'foo' is a required property",
  )
  inspect(
    message_for({ "foo": {} }, { "dependentRequired": { "foo": ["bar"] } }),
    content="'bar' is a dependency of 'foo'",
  )
}

///|
test "oneOf" {
  inspect(
    message_for({}, { "oneOf": [false] }),
    content="{} is not valid under any of the given schemas",
  )
  inspect(
    message_for({}, { "oneOf": [true, true] }),
    content="{} is valid under each of True, True",
  )
}

///|
test "unevaluated" {
  inspect(
    message_for(["foo", "bar"], { "type": "array", "unevaluatedItems": false }),
    content="Unevaluated items are not allowed ('foo', 'bar' were unexpected)",
  )
  inspect(
    message_for("foo", { "type": "array", "unevaluatedItems": false }),
    content="'foo' is not of type 'array'",
  )
  inspect(
    message_for({ "foo": "foo", "bar": "bar", "baz": 12 }, {
      "properties": { "foo": { "type": "string" } },
      "unevaluatedProperties": { "const": 12 },
    }),
    content="Unevaluated properties are not valid under the given schema ('bar' was unevaluated and invalid)",
  )
  inspect(
    message_for({ "foo": "foo", "bar": "bar" }, {
      "type": "object",
      "unevaluatedProperties": false,
    }),
    content="Unevaluated properties are not allowed ('bar', 'foo' were unexpected)",
  )
  inspect(
    message_for("foo", { "type": "object", "unevaluatedProperties": false }),
    content="'foo' is not of type 'object'",
  )
  inspect(
    message_for(["foo", "bar", 37], {
      "prefixItems": [{}],
      "unevaluatedItems": false,
    }),
    content="Unevaluated items are not allowed ('bar', 37 were unexpected)",
  )
}

///|
test "heterogeneous additionalItems with items" {
  inspect(
    message_for(
      ["foo", "bar", 37],
      { "items": [{}], "additionalItems": false },
      cls=@jsonschema.draft7_validator,
    ),
    content="Additional items are not allowed ('bar', 37 were unexpected)",
  )
}
