// Ports of `TestCreateAndExtend`, `MetaSchemaTestsMixin`,
// `ValidatorTestMixin`, `AntiDraft6LeakMixin`, `TestDraft3Validator`,
// `TestValidatorFor`, `TestValidate` and `TestReferencing` from upstream's
// `jsonschema/tests/test_validators.py`.
//
// Not ported: tests of the deprecated `RefResolver` API, subclassing,
// threading, and tests relying on Python-only instances (`Decimal`, tuples,
// `deque`s, namedtuples, non-string type names or dict keys).

///|
/// Upstream's `fail` keyword: yields an error per entry of its value.
fn fail_keyword(
  _validator : @jsonschema.Validator,
  errors : Json,
  _instance : Json,
  _schema : Json,
) -> @jsonschema.Errors {
  @jsonschema.Errors::new(fn(yield_) raise {
    guard errors is Array(errors) else { return true }
    for each in errors {
      let message = match each {
        Object({ "message": String(m), .. }) => m
        _ => "You told me to fail!"
      }
      let validator = match each {
        Object({ "validator": v, .. }) => Some(v)
        _ => None
      }
      if !yield_(@jsonschema.ValidationError::new(message, validator?)) {
        return false
      }
    }
    true
  })
}

///|
fn fail_validator() -> @jsonschema.ValidatorClass {
  @jsonschema.create(
    meta_schema={ "$id": "some://meta/schema" },
    validators=[("fail", fail_keyword)],
    type_checker=@jsonschema.TypeChecker::new(),
  )
}

///|
test "create: attrs / init / iter_errors" {
  let cls = fail_validator()
  debug_inspect(cls.validators.keys().collect(), content="[\"fail\"]")
  json_inspect(cls.meta_schema, content={ "$id": "some://meta/schema" })
  assert_true(cls.type_checker == @jsonschema.TypeChecker::new())
  let schema : Json = { "fail": [] }
  assert_true(cls.new(schema).schema == schema)
  inspect(cls.new(schema).iter_errors("hello").to_array().length(), content="0")
  let schema : Json = { "fail": [{ "message": "Whoops!" }] }
  let errors = cls.new(schema).iter_errors("goodbye").to_array()
  inspect(errors.length(), content="1")
  let e = errors[0]
  inspect(e.message, content="Whoops!")
  json_inspect(e.instance.unwrap(), content="goodbye")
  assert_true(e.schema == Some(schema))
  json_inspect(e.validator.unwrap(), content="fail")
  json_inspect(e.validator_value.unwrap(), content=[{ "message": "Whoops!" }])
  debug_inspect(e.schema_path, content="[Key(\"fail\")]")
  let schema : Json = {
    "fail": [
      { "message": "First" },
      { "message": "Second!", "validator": "asdf" },
      { "message": "Third" },
    ],
  }
  let errors = cls.new(schema).iter_errors("goodbye").to_array()
  inspect(errors.length(), content="3")
  json_inspect(errors[1].validator.unwrap(), content="asdf")
}

///|
test "create: versions are registered and named" {
  let cls = @jsonschema.create(
    meta_schema={ "$id": "something" },
    version="my version",
  )
  inspect(cls.name, content="MyVersionValidator")
  inspect(
    cls.new({}),
    content="MyVersionValidator(schema={}, format_checker=None)",
  )
  let a = Json::array(Array::makei(1000, i => Json::number(i.to_double())))
  inspect(
    cls.new({ "a": a }),
    content="MyVersionValidator(schema={'a': [0, 1, 2, 3, 4, 5, ...]}, format_checker=None)",
  )
  assert_true(
    @jsonschema.registered_validators().get("my version") is Some(c) &&
    physical_equal(c, cls),
  )
  assert_true(
    physical_equal(@jsonschema.validator_for({ "$schema": "something" }), cls),
  )
  inspect(
    @jsonschema.create(meta_schema={}).new({}),
    content="Validator(schema={}, format_checker=None)",
  )
  inspect(
    @jsonschema.create(
      meta_schema={ "$id": "something else" },
      version="foo-bar",
    ).name,
    content="FooBarValidator",
  )
}

///|
test "create: unversioned classes are not registered" {
  let before = @jsonschema.registered_validators().length()
  ignore(@jsonschema.create(meta_schema={ "id": "id" }))
  inspect(
    @jsonschema.registered_validators().length() == before,
    content="true",
  )
}

///|
test "create: validates registers the meta-schema id" {
  let custom = @jsonschema.create(
    meta_schema={ "id": "meta schema id" },
    version="12",
    id_of=s => {
      match s {
        Object({ "id": String(id), .. }) => Some(id)
        _ => Some("")
      }
    },
  )
  assert_true(
    physical_equal(
      @jsonschema.validator_for({ "$schema": "meta schema id" }),
      custom,
    ),
  )
  let custom6 = @jsonschema.create(
    meta_schema={ "$id": "meta schema $id" },
    version="13",
  )
  assert_true(
    physical_equal(
      @jsonschema.validator_for({ "$schema": "meta schema $id" }),
      custom6,
    ),
  )
}

///|
test "create: default types" {
  let cls = @jsonschema.create(meta_schema={})
  let v = cls.new({})
  let checks : Array[(String, Json)] = [
    ("array", []),
    ("boolean", true),
    ("integer", 12),
    ("null", null),
    ("number", Json::number(12.0, repr="12.0")),
    ("object", {}),
    ("string", "foo"),
  ]
  for check in checks {
    assert_true(v.is_type(check.1, check.0))
  }
}

///|
test "create: check_schema with a different meta-schema dialect" {
  let no_empty = @jsonschema.create(meta_schema={
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "not": { "const": {} },
  })
  no_empty.check_schema({ "foo": "bar" })
  let raised = try {
    no_empty.check_schema({})
    false
  } catch {
    @jsonschema.SchemaError(_) => true
    _ => false
  }
  assert_true(raised)
  no_empty.new({ "foo": "bar" }).validate("foo")
  // a meta-schema without $schema defaults to the class itself
  let selfish = @jsonschema.create(
    meta_schema={ "fail": [{ "message": "Meta schema whoops!" }] },
    validators=[("fail", fail_keyword)],
  )
  let raised = try {
    selfish.check_schema({})
    false
  } catch {
    @jsonschema.SchemaError(e) => e.message == "Meta schema whoops!"
    _ => false
  }
  assert_true(raised)
}

///|
test "extend" {
  let cls = fail_validator()
  let extended = cls.extend_with(validators=[("new", fail_keyword)])
  debug_inspect(
    extended.validators.keys().collect(),
    content="[\"fail\", \"new\"]",
  )
  debug_inspect(cls.validators.keys().collect(), content="[\"fail\"]")
  assert_true(extended.meta_schema == cls.meta_schema)
  assert_true(extended.type_checker == cls.type_checker)
  // ids
  let correct_id = "the://correct/id/"
  let original = @jsonschema.create(
    meta_schema={ "$id": "the://wrong/id/", "__test__": correct_id },
    validators=[("fail", fail_keyword)],
    id_of=s => {
      match s {
        Object({ "__test__": String(id), .. }) => Some(id)
        _ => (cls.id_of)(s)
      }
    },
  )
  debug_inspect(
    (original.id_of)(original.meta_schema),
    content="Some(\"the://correct/id/\")",
  )
  let derived = original.extend_with()
  debug_inspect(
    (derived.id_of)(derived.meta_schema),
    content="Some(\"the://correct/id/\")",
  )
  // applicable validators
  let schema : Json = {
    "$defs": { "test": { "type": "number" } },
    "$ref": "#/$defs/test",
    "maximum": 1,
  }
  assert_true(@jsonschema.draft4_validator.new(schema).is_valid(37))
  assert_true(
    @jsonschema.draft4_validator.extend_with().new(schema).is_valid(37),
  )
}

///|
fn all_classes() -> Array[@jsonschema.ValidatorClass] {
  [
    @jsonschema.draft3_validator, @jsonschema.draft4_validator, @jsonschema.draft6_validator,
    @jsonschema.draft7_validator, @jsonschema.draft201909_validator, @jsonschema.draft202012_validator,
  ]
}

///|
fn raises_schema_error(
  cls : @jsonschema.ValidatorClass,
  schema : Json,
  format_checker? : @jsonschema.FormatChecker?,
) -> Bool {
  try {
    match format_checker {
      Some(fc) => cls.check_schema(schema, format_checker=fc)
      None => cls.check_schema(schema)
    }
    false
  } catch {
    @jsonschema.SchemaError(_) => true
    _ => false
  }
}

///|
test "meta-schema checks (every draft)" {
  for cls in all_classes() {
    let old = physical_equal(cls, @jsonschema.draft3_validator) ||
      physical_equal(cls, @jsonschema.draft4_validator)
    assert_true(raises_schema_error(cls, { "properties": 12 }), msg=cls.name)
    assert_true(raises_schema_error(cls, { "minItems": "1" }), msg=cls.name)
    assert_eq(raises_schema_error(cls, { "enum": [] }), old, msg=cls.name)
    assert_eq(raises_schema_error(cls, { "enum": [12, 12] }), old, msg=cls.name)
    assert_true(
      raises_schema_error(cls, { "pattern": "*notaregex" }),
      msg=cls.name,
    )
    assert_false(
      raises_schema_error(cls, { "pattern": "*notaregex" }, format_checker=None),
      msg=cls.name,
    )
  }
}

///|
test "validator basics (every draft)" {
  for cls in all_classes() {
    assert_true(cls.new({}).is_valid({}))
    assert_false(cls.new({ "type": "integer" }).is_valid("foo"))
    cls.new({ "notAKeyword": [1, 2] }).validate("anything")
    assert_true(cls.new({}).is_type("foo", "string"))
    assert_false(cls.new({}).is_type("foo", "array"))
    assert_false(cls.new({}).is_type(true, "integer"))
    assert_false(cls.new({}).is_type(true, "number"))
    // unknown formats pass; formats are not validated by default
    cls
    .new(
      { "format": "carrot" },
      format_checker=@jsonschema.FormatChecker::new(),
    )
    .validate("bugs")
    assert_true(cls.new({}).format_checker is None)
  }
}

///|
test "evolve (every draft)" {
  for cls in all_classes() {
    let original = cls.new(
      { "type": "integer" },
      format_checker=@jsonschema.FormatChecker::new(),
    )
    let new = original.evolve(
      schema={ "type": "string" },
      format_checker=Some(cls.format_checker),
    )
    assert_true(physical_equal(new.cls, cls))
    json_inspect(new.schema, content={ "type": "string" })
    assert_true(
      new.format_checker is Some(fc) && physical_equal(fc, cls.format_checker),
    )
    json_inspect(original.schema, content={ "type": "integer" })
  }
}

///|
suberror Bad {
  Bad
}

///|
test "formats are validated with a checker (every draft)" {
  for cls in all_classes() {
    let checker = @jsonschema.FormatChecker::new()
    checker.checks(
      "foo",
      value => {
        match value {
          String("good") => true
          String("bad") => raise Bad
          _ => fail("What is \{@jsonschema.py_repr(value)}?")
        }
      },
      raises=e => e is Bad,
    )
    let validator = cls.new({ "format": "foo" }, format_checker=checker)
    validator.validate("good")
    try validator.validate("bad") catch {
      @jsonschema.ValidationError(e) => assert_true(e.cause is Some(Bad))
      _ => fail("unexpected error")
    } noraise {
      _ => fail("expected a ValidationError")
    }
  }
}

///|
test "draft 6 functionality does not leak into drafts 3 and 4" {
  for cls in [@jsonschema.draft3_validator, @jsonschema.draft4_validator] {
    let schemas : Array[Json] = [true, false]
    for schema in schemas {
      try cls.check_schema(schema) catch {
        @jsonschema.SchemaError(e) =>
          assert_true(
            e
            .to_string()
            .contains("\{@jsonschema.py_repr(schema)} is not of type"),
          )
        _ => fail("expected a SchemaError")
      } noraise {
        _ => fail("expected a SchemaError")
      }
      // not a ValidationError, even if you forget to check
      let raised = try {
        cls.new(schema).validate(12)
        "nothing"
      } catch {
        @jsonschema.ValidationError(_) => "ValidationError"
        _ => "other"
      }
      inspect(raised, content="other")
    }
  }
}

///|
test "draft 3: type any" {
  let cls = @jsonschema.draft3_validator
  cls.new({ "type": "any" }).validate({ "anything": [] })
  let crazy = cls.extend_with(
    type_checker=cls.type_checker.redefine("any", (_, thing) => {
      @jsonschema.loads("1") == thing || thing is Number(_)
    }),
  )
  let v = crazy.new({ "type": "any" })
  v.validate(12)
  assert_false(v.is_valid("foo"))
  assert_true(cls.new({ "type": "any" }).is_valid({}))
  assert_true(cls.new({}).is_type(true, "boolean"))
  assert_true(cls.new({ "type": "any" }).is_valid(true))
}

///|
test "validator_for" {
  let cases : Array[(String, @jsonschema.ValidatorClass)] = [
    ("http://json-schema.org/draft-03/schema", @jsonschema.draft3_validator),
    ("http://json-schema.org/draft-03/schema#", @jsonschema.draft3_validator),
    ("http://json-schema.org/draft-04/schema", @jsonschema.draft4_validator),
    ("http://json-schema.org/draft-04/schema#", @jsonschema.draft4_validator),
    ("http://json-schema.org/draft-06/schema", @jsonschema.draft6_validator),
    ("http://json-schema.org/draft-06/schema#", @jsonschema.draft6_validator),
    ("http://json-schema.org/draft-07/schema", @jsonschema.draft7_validator),
    ("http://json-schema.org/draft-07/schema#", @jsonschema.draft7_validator),
    (
      "https://json-schema.org/draft/2019-09/schema", @jsonschema.draft201909_validator,
    ),
    (
      "https://json-schema.org/draft/2019-09/schema#", @jsonschema.draft201909_validator,
    ),
    (
      "https://json-schema.org/draft/2020-12/schema", @jsonschema.draft202012_validator,
    ),
    (
      "https://json-schema.org/draft/2020-12/schema#", @jsonschema.draft202012_validator,
    ),
  ]
  for case in cases {
    assert_true(
      physical_equal(
        @jsonschema.validator_for({ "$schema": Json::string(case.0) }),
        case.1,
      ),
      msg=case.0,
    )
  }
  let latest = @jsonschema.latest_version()
  assert_true(physical_equal(@jsonschema.validator_for(true), latest))
  assert_true(physical_equal(@jsonschema.validator_for(false), latest))
  assert_true(physical_equal(@jsonschema.validator_for({}), latest))
  // unknown $schema: the latest draft (upstream also warns)
  assert_true(
    physical_equal(
      @jsonschema.validator_for({ "$schema": "unknownSchema" }),
      latest,
    ),
  )
  let default = @jsonschema.draft4_validator
  assert_true(
    physical_equal(
      @jsonschema.validator_for(
        { "$schema": "mailto:foo@example.com" },
        default~,
      ),
      default,
    ),
  )
}

///|
test "validate" {
  // the schema is checked with the class selected by $schema
  let dialects = [
    "http://json-schema.org/draft-03/schema#", "http://json-schema.org/draft-03/schema",
    "http://json-schema.org/draft-04/schema#", "http://json-schema.org/draft-04/schema",
    "http://json-schema.org/draft-06/schema#", "http://json-schema.org/draft-06/schema",
    "http://json-schema.org/draft-07/schema#", "http://json-schema.org/draft-07/schema",
    "https://json-schema.org/draft/2020-12/schema#", "https://json-schema.org/draft/2020-12/schema",
  ]
  for dialect in dialects {
    @jsonschema.validate({}, { "$schema": Json::string(dialect) })
  }
  try @jsonschema.validate(12, { "type": "string" }) catch {
    @jsonschema.ValidationError(e) => {
      let s = e.to_string()
      assert_true(s.contains("Failed validating 'type' in schema"))
      assert_true(s.contains("On instance"))
    }
    _ => fail("expected a ValidationError")
  } noraise {
    _ => fail("expected a ValidationError")
  }
  try @jsonschema.validate(12, { "type": 12 }) catch {
    @jsonschema.SchemaError(e) => {
      let s = e.to_string()
      assert_true(s.contains("in metaschema"))
      assert_true(s.contains("On schema"))
    }
    _ => fail("expected a SchemaError")
  } noraise {
    _ => fail("expected a SchemaError")
  }
  // best_match is used
  try
    @jsonschema.validate(12, {
      "oneOf": [{ "type": "number", "minimum": 20 }, { "type": "array" }],
    })
  catch {
    @jsonschema.ValidationError(e) =>
      assert_true(e.to_string().contains("12 is less than the minimum of 20"))
    _ => fail("expected a ValidationError")
  } noraise {
    _ => fail("expected a ValidationError")
  }
  @jsonschema.validate(37, true)
}

///|
test "referencing" {
  let registry = @referencing.Registry::new(retrieve=_ => {
    @referencing.draft202012().create_resource({ "type": "integer" })
  })
  let validator = @jsonschema.draft202012_validator.new(
    { "$ref": "https://example.com/" },
    registry~,
  )
  debug_inspect(
    (validator.is_valid(12), validator.is_valid("foo")),
    content="(true, false)",
  )
  // custom registries do not retrieve remote resources
  let validator = @jsonschema.draft202012_validator.new(
    { "$ref": "https://example.com/" },
    registry=@referencing.Registry::new(),
  )
  try validator.validate(12) catch {
    e => assert_true(@referencing.is_unresolvable(e))
  } noraise {
    _ => fail("expected Unresolvable")
  }
}
