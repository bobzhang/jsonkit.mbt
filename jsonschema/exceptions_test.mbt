// Ports of upstream's `jsonschema/tests/test_exceptions.py`.

///|
fn contents(e : @jsonschema.ValidationError) -> String {
  [
    e.message,
    opt_repr(e.validator),
    opt_repr(e.validator_value),
    path_repr(e.path),
    path_repr(e.schema_path),
    opt_repr(e.instance),
    opt_repr(e.schema),
  ].join(" | ")
}

///|
fn best_match_of(instance : Json, schema : Json) -> @jsonschema.ValidationError raise {
  let errors = @jsonschema.latest_version().new(schema).iter_errors(instance).to_array()
  assert_true(errors.length() > 0, msg="No errors found")
  let best = @jsonschema.best_match(errors.iter()).unwrap()
  let reversed = errors.copy()
  reversed.rev_in_place()
  let reversed_best = @jsonschema.best_match(reversed.iter()).unwrap()
  assert_eq(contents(best), contents(reversed_best), msg="No consistent best match!")
  best
}

///|
test "best_match: shallower errors are better matches" {
  let best = best_match_of({ "foo": { "bar": [] } }, {
    "properties": {
      "foo": { "minProperties": 2, "properties": { "bar": { "type": "object" } } },
    },
  })
  inspect(opt_repr(best.validator), content="'minProperties'")
}

///|
test "best_match: earlier sibling errors are better matches" {
  let best = best_match_of([12, 12, 12], { "items": { "const": 37 } })
  inspect(path_repr(best.path), content="[0]")
  let schema : Json = { "anyOf": [{ "items": { "const": 37 } }] }
  let error = @jsonschema.latest_version()
    .new(schema)
    .iter_errors([12, 12, 12])
    .first()
    .unwrap()
  error.context.rev_in_place()
  let best = @jsonschema.best_match([error].iter()).unwrap()
  inspect(path_repr(best.path), content="[0]")
}

///|
test "best_match: hand constructed errors with context" {
  let error = @jsonschema.ValidationError::new("parent", context=[
    @jsonschema.ValidationError::new("child", path=[Key("foo")]),
    @jsonschema.ValidationError::new("grandchild", path=[Key("foo"), Key("bar")]),
  ])
  inspect(@jsonschema.best_match([error].iter()).unwrap().message, content="child")
}

///|
test "best_match: oneOf and anyOf are weak matches" {
  let best = best_match_of({}, {
    "minProperties": 2,
    "anyOf": [{ "type": "string" }, { "type": "number" }],
    "oneOf": [{ "type": "string" }, { "type": "number" }],
  })
  inspect(opt_repr(best.validator), content="'minProperties'")
}

///|
/// The anyOf / oneOf traversal tests, run for both keywords.
test "best_match: anyOf / oneOf traversal" {
  for kw in ["anyOf", "oneOf"] {
    let k = (subschemas : Json) => Json::object(Map::from_array([(kw, subschemas)]))
    let best = best_match_of({ "foo": { "bar": 12 } }, {
      "properties": {
        "foo": k([
          { "type": "string" },
          { "properties": { "bar": { "type": "array" } } },
        ]),
      },
    })
    inspect(opt_repr(best.validator_value), content="'array'")
    let best = best_match_of({ "foo": { "bar": [] } }, k([
      {
        "properties": {
          "foo": { "minProperties": 2, "properties": { "bar": { "type": "object" } } },
        },
      },
    ]))
    inspect(opt_repr(best.validator), content="'minProperties'")
    let best = best_match_of({ "foo": { "bar": [] } }, k([
      { "type": "string" },
      {
        "properties": {
          "foo": { "minProperties": 2, "properties": { "bar": { "type": "object" } } },
        },
      },
    ]))
    inspect(opt_repr(best.validator), content="'minProperties'")
    // no traversal for equally relevant errors
    let best = best_match_of([], k([
      { "type": "string" },
      { "type": "integer" },
      { "type": "object" },
    ]))
    assert_eq(opt_repr(best.validator), @jsonschema.py_repr(Json::string(kw)))
    let best = best_match_of({ "foo": 1, "bar": 1 }, k([
      { "properties": { "foo": { "type": "string" } } },
      { "properties": { "bar": { "type": "string" } } },
    ]))
    assert_eq(opt_repr(best.validator), @jsonschema.py_repr(Json::string(kw)))
    // prefers subschemas with fewer errors
    let schema = k([
        { "type": "array", "items": { "$ref": "#/$defs/int_array" } },
        { "$ref": "#/$defs/int_array" },
      ])
    guard schema is Object(m)
    m["$defs"] = { "int_array": { "type": "array", "items": { "type": "integer" } } }
    let best = best_match_of(["not an int", 0], schema)
    inspect("\{opt_repr(best.validator)} \{opt_repr(best.instance)}", content="'type' 'not an int'")
    let best = best_match_of([0, "not an int"], schema)
    inspect("\{opt_repr(best.validator)} \{opt_repr(best.instance)}", content="'type' 'not an int'")
    // partially matching subschemas
    let best = best_match_of({ "version": 1, "description": 0 }, k([
      {
        "properties": {
          "version": { "const": 1 },
          "description": { "type": "string" },
        },
      },
      {
        "properties": {
          "version": { "const": 2 },
          "description": { "type": "string" },
        },
      },
    ]))
    inspect("\{opt_repr(best.validator)} \{path_repr(best.path)}", content="'type' ['description']")
    // single equally relevant error
    let best = best_match_of([], k([{ "type": "string" }]))
    inspect(opt_repr(best.validator), content="'type'")
    // single sibling errors: choose first
    let best = best_match_of([12, 13], k([{ "items": { "const": 37 } }]))
    inspect("\{opt_repr(best.validator)} \{opt_repr(best.instance)}", content="'const' 12")
    // non type matching sibling errors
    let best = best_match_of([12, 12], k([
      { "type": "object" },
      { "items": { "const": 37 } },
    ]))
    inspect(opt_repr(best.validator), content="'const'")
  }
}

///|
test "best_match: allOf / nested oneOf" {
  let best = best_match_of({ "foo": { "bar": 12 } }, {
    "properties": {
      "foo": {
        "allOf": [
          { "type": "string" },
          { "properties": { "bar": { "type": "array" } } },
        ],
      },
    },
  })
  inspect(opt_repr(best.validator_value), content="'string'")
  let best = best_match_of({ "foo": { "bar": 12 } }, {
    "properties": {
      "foo": {
        "oneOf": [
          { "type": "string" },
          {
            "oneOf": [
              { "type": "string" },
              { "properties": { "bar": { "type": "array" } } },
            ],
          },
        ],
      },
    },
  })
  inspect(opt_repr(best.validator_value), content="'array'")
}

///|
test "best_match: prioritizes matching types" {
  let any_ofs : Array[Json] = [
    [
      { "type": "array", "minItems": 2 },
      { "type": "string", "minLength": 10 },
    ],
    [
      { "type": "string", "minLength": 10 },
      { "type": "array", "minItems": 2 },
    ],
    [
      { "type": ["array", "object"], "minItems": 2 },
      { "type": ["integer", "string"], "minLength": 10 },
    ],
  ]
  for any_of in any_ofs {
    let best = best_match_of({ "foo": "bar" }, {
      "properties": { "foo": { "anyOf": any_of } },
    })
    inspect(opt_repr(best.validator), content="'minLength'")
  }
}

///|
test "best_match: boolean schemas / one error / no errors" {
  let best = best_match_of({ "foo": "bar" }, { "properties": { "foo": false } })
  inspect(opt_repr(best.validator), content="None")
  let validator = @jsonschema.latest_version().new({ "minProperties": 2 })
  inspect(
    opt_repr(
      @jsonschema.best_match(validator.iter_errors({}).to_array().iter()).unwrap().validator,
    ),
    content="'minProperties'",
  )
  let validator = @jsonschema.latest_version().new({})
  assert_true(
    @jsonschema.best_match(validator.iter_errors({}).to_array().iter()) is None,
  )
}

///|
fn max_by_relevance(
  errors : Array[@jsonschema.ValidationError],
  key : (@jsonschema.ValidationError) -> @jsonschema.Relevance,
) -> @jsonschema.ValidationError {
  // Python's max(): the first maximal element
  let mut best = errors[0]
  for e in errors[1:] {
    if key(e) > key(best) {
      best = e
    }
  }
  best
}

///|
test "by_relevance" {
  let shallow = @jsonschema.ValidationError::new("Oh no!", path=[Key("baz")])
  let deep = @jsonschema.ValidationError::new("Oh yes!", path=[Key("foo"), Key("bar")])
  assert_true(physical_equal(max_by_relevance([shallow, deep], @jsonschema.relevance), shallow))
  assert_true(physical_equal(max_by_relevance([deep, shallow], @jsonschema.relevance), shallow))
  let shallow = @jsonschema.ValidationError::new("Oh no!", path=[])
  let deep = @jsonschema.ValidationError::new("Oh yes!", path=[Key("foo")])
  for errors in [[shallow, deep], [deep, shallow]] {
    let sorted = errors.copy()
    sorted.sort_by((a, b) => @jsonschema.relevance(a).compare(@jsonschema.relevance(b)))
    inspect(sorted.map(e => path_repr(e.path)).join(" "), content="['foo'] []")
  }
  let weak = @jsonschema.ValidationError::new("Oh no!", path=[], validator="a")
  let normal = @jsonschema.ValidationError::new("Oh yes!", path=[], validator="b")
  let strong = @jsonschema.ValidationError::new("Oh fine!", path=[], validator="c")
  let key = @jsonschema.by_relevance(weak=["a"])
  assert_true(physical_equal(max_by_relevance([weak, normal], key), normal))
  assert_true(physical_equal(max_by_relevance([normal, weak], key), normal))
  let key = @jsonschema.by_relevance(weak=["a"], strong=["c"])
  assert_true(physical_equal(max_by_relevance([weak, normal, strong], key), strong))
  assert_true(physical_equal(max_by_relevance([strong, normal, weak], key), strong))
}

///|
test "ErrorTree" {
  let errors = Array::makei(8, i => @jsonschema.ValidationError::new(
    "Something",
    validator=Json::number(i.to_double()),
  ))
  inspect(@jsonschema.ErrorTree::new(errors~).total_errors(), content="8")
  let tree = @jsonschema.ErrorTree::new(errors=[
    @jsonschema.ValidationError::new("a message", path=[Key("bar")]),
  ])
  assert_true(tree.contains(Key("bar")))
  assert_false(tree.contains(Key("foo")))
  let error = @jsonschema.ValidationError::new("a message", validator="foo")
  let tree = @jsonschema.ErrorTree::new(errors=[error])
  debug_inspect(tree.errors.keys().collect(), content="[\"foo\"]")
  assert_true(physical_equal(tree.errors["foo"], error))
  let tree = @jsonschema.ErrorTree::new(errors=[
    @jsonschema.ValidationError::new("a bar message", path=[Key("bar")]),
    @jsonschema.ValidationError::new("a bar -> 0 message", path=[Key("bar"), Index(0)]),
  ])
  assert_true(tree.at(Key("bar")).contains(Index(0)))
  assert_false(tree.at(Key("bar")).contains(Index(1)))
  let e1 = @jsonschema.ValidationError::new("1", validator="foo", path=[Key("bar"), Index(0)])
  let e2 = @jsonschema.ValidationError::new("2", validator="quux", path=[Key("bar"), Index(0)])
  let tree = @jsonschema.ErrorTree::new(errors=[e1, e2])
  let child = tree.at(Key("bar")).at(Index(0))
  assert_true(physical_equal(child.errors["foo"], e1))
  assert_true(physical_equal(child.errors["quux"], e2))
  // multiple errors with instance / iteration / repr
  let e1 = @jsonschema.ValidationError::new("1", validator="foo", path=[Key("bar"), Key("bar2")], instance="i1")
  let e2 = @jsonschema.ValidationError::new("2", validator="quux", path=[Key("foobar"), Index(2)], instance="i2")
  let tree = @jsonschema.ErrorTree::new(errors=[e1, e2])
  debug_inspect(tree.iter().collect(), content="[Key(\"bar\"), Key(\"foobar\")]")
  inspect(tree, content="<ErrorTree (2 total errors)>")
  inspect(@jsonschema.ErrorTree::new(errors=[e1]), content="<ErrorTree (1 total error)>")
  inspect(@jsonschema.ErrorTree::new(), content="<ErrorTree (0 total errors)>")
}

///|
test "ErrorTree indexing follows the instance" {
  let error = @jsonschema.ValidationError::new("123", validator="foo", instance=[])
  let tree = @jsonschema.ErrorTree::new(errors=[error])
  try tree.at(Index(0)) catch {
    @jsonschema.IndexError(_) => ()
    _ => fail("expected IndexError")
  } noraise {
    _ => fail("expected IndexError")
  }
  let error = @jsonschema.ValidationError::new("a message", validator="foo", instance={}, path=[Key("foo")])
  ignore(@jsonschema.ErrorTree::new(errors=[error]).at(Key("foo")))
  // accessing an error-free index does not add it to the tree
  let error = @jsonschema.ValidationError::new("a message", validator="foo", instance=["spam", "eggs"], path=[Index(0)])
  let tree = @jsonschema.ErrorTree::new(errors=[error])
  let subtree = tree.at(Index(1))
  inspect(subtree.total_errors(), content="0")
  assert_false(tree.contains(Index(1)))
  debug_inspect(tree.iter().collect(), content="[Index(0)]")
  inspect(tree.total_errors(), content="1")
  // error-free subtrees still know their instance
  let error = @jsonschema.ValidationError::new("a message", validator="foo", instance={ "bar": [] }, path=[Key("foo")])
  let tree = @jsonschema.ErrorTree::new(errors=[error])
  let subtree = tree.at(Key("foo")).at(Key("bar"))
  inspect(subtree.total_errors(), content="0")
  try subtree.at(Index(0)) catch {
    @jsonschema.IndexError(_) => ()
    _ => fail("expected IndexError")
  } noraise {
    _ => fail("expected IndexError")
  }
  // it can be given the instance it corresponds to
  let tree = @jsonschema.ErrorTree::new(instance={ "foo": [] })
  try tree.at(Key("bar")) catch {
    @jsonschema.KeyError(_) => ()
    _ => fail("expected KeyError")
  } noraise {
    _ => fail("expected KeyError")
  }
  try tree.at(Key("foo")).at(Index(0)) catch {
    @jsonschema.IndexError(_) => ()
    _ => fail("expected IndexError")
  } noraise {
    _ => fail("expected IndexError")
  }
}

///|
fn make_error(
  path? : Array[@jsonschema.PathItem] = [],
  schema_path? : Array[@jsonschema.PathItem] = [],
  validator? : Json = "type",
  instance? : Json = 5,
  schema? : Json = { "type": "string" },
) -> @jsonschema.ValidationError {
  @jsonschema.ValidationError::new(
    "hello",
    validator~,
    validator_value="string",
    instance~,
    schema~,
    path~,
    schema_path~,
  )
}

///|
/// Everything after the message line of `str(error)`.
fn shows(error : @jsonschema.ValidationError) -> String {
  let s = error.to_string()
  match s.find("\n") {
    Some(i) => {
      assert_eq(s.unsafe_substring(start=0, end=i), error.message) catch { _ => () }
      s.unsafe_substring(start=i + 1, end=s.length())
    }
    None => ""
  }
}

///|
test "error repr / str" {
  inspect(
    @jsonschema.ValidationError::new("Hello!").repr(),
    content="<ValidationError: 'Hello!'>",
  )
  inspect(@jsonschema.ValidationError::new("message"), content="message")
  // just the message if any detail is unset
  let full : Array[(String, Json)] = [
    ("validator", "type"),
    ("validator_value", "string"),
    ("instance", 5),
    ("schema", { "type": "string" }),
  ]
  for omit in 0..<4 {
    let get = (i : Int) => if i == omit { None } else { Some(full[i].1) }
    let error = @jsonschema.ValidationError::new(
      "message",
      validator?=get(0),
      validator_value?=get(1),
      instance?=get(2),
      schema?=get(3),
    )
    inspect(error, content="message")
  }
  inspect(
    shows(make_error()),
    content=(
      #|
      #|Failed validating 'type' in schema:
      #|    {'type': 'string'}
      #|
      #|On instance:
      #|    5
    ),
  )
  inspect(
    shows(make_error(path=[Index(0)], schema_path=[Key("items")])),
    content=(
      #|
      #|Failed validating 'type' in schema:
      #|    {'type': 'string'}
      #|
      #|On instance[0]:
      #|    5
    ),
  )
  inspect(
    shows(
      make_error(path=[Index(0), Key("a")], schema_path=[
        Key("items"),
        Index(0),
        Index(1),
      ]),
    ),
    content=(
      #|
      #|Failed validating 'type' in schema['items'][0]:
      #|    {'type': 'string'}
      #|
      #|On instance[0]['a']:
      #|    5
    ),
  )
}

///|
test "error str uses pprint" {
  // upstream uses int keys, which JSON cannot have
  let schema = Json::object(
    Map::from_array(Array::makei(20, i => (i.to_string(), Json::number(i.to_double())))),
  )
  let instance = Json::array(Array::makei(25, i => Json::number(i.to_double())))
  inspect(
    shows(make_error(validator="maxLength", instance~, schema~)),
    content=(
      #|
      #|Failed validating 'maxLength' in schema:
      #|    {'0': 0,
      #|     '1': 1,
      #|     '2': 2,
      #|     '3': 3,
      #|     '4': 4,
      #|     '5': 5,
      #|     '6': 6,
      #|     '7': 7,
      #|     '8': 8,
      #|     '9': 9,
      #|     '10': 10,
      #|     '11': 11,
      #|     '12': 12,
      #|     '13': 13,
      #|     '14': 14,
      #|     '15': 15,
      #|     '16': 16,
      #|     '17': 17,
      #|     '18': 18,
      #|     '19': 19}
      #|
      #|On instance:
      #|    [0,
      #|     1,
      #|     2,
      #|     3,
      #|     4,
      #|     5,
      #|     6,
      #|     7,
      #|     8,
      #|     9,
      #|     10,
      #|     11,
      #|     12,
      #|     13,
      #|     14,
      #|     15,
      #|     16,
      #|     17,
      #|     18,
      #|     19,
      #|     20,
      #|     21,
      #|     22,
      #|     23,
      #|     24]
    ),
  )
  inspect(
    shows(
      make_error(
        schema={ "do": 3, "not": 7, "sort": 37, "me": 73 },
        instance={ "here": 73, "too": 37, "no": 7, "sorting": 3 },
      ),
    ),
    content=(
      #|
      #|Failed validating 'type' in schema:
      #|    {'do': 3, 'not': 7, 'sort': 37, 'me': 73}
      #|
      #|On instance:
      #|    {'here': 73, 'too': 37, 'no': 7, 'sorting': 3}
    ),
  )
}

///|
test "json_path rendering" {
  let cases : Array[(String, String)] = [
    ("x", "$.x"),
    ("", "$['']"),
    ("1", "$['1']"),
    (".", "$['.']"),
    ("'", "$['\\'']"),
    (" ", "$[' ']"),
    ("\\", "$['\\\\']"),
    ("\\'", "$['\\\\\\'']"),
    ("_", "$['_']"),
    ("\"", "$['\"']"),
    ("-", "$['-']"),
    ("a[0]", "$['a[0]']"),
    ("[", "$['[']"),
  ]
  for case in cases {
    let error = @jsonschema.ValidationError::new(
      "1",
      path=[Key(case.0)],
      validator="foo",
      instance="i1",
    )
    assert_eq(error.json_path(), case.1)
  }
}
