// Port of upstream's referencing/tests/test_jsonschema.py.

///|
fn dialects() -> Array[(String, @referencing.Specification)] {
  [
    ("https://json-schema.org/draft/2020-12/schema", @jsonschema.draft202012()),
    ("https://json-schema.org/draft/2019-09/schema", @jsonschema.draft201909()),
    ("http://json-schema.org/draft-07/schema#", @jsonschema.draft7()),
    ("http://json-schema.org/draft-06/schema#", @jsonschema.draft6()),
    ("http://json-schema.org/draft-04/schema#", @jsonschema.draft4()),
    ("http://json-schema.org/draft-03/schema#", @jsonschema.draft3()),
  ]
}

///|
test "schemas with explicit schema keywords are detected" {
  for case in dialects() {
    let (uri, expected) = case
    let contents : Json = { "$schema": uri }
    let resource = @referencing.Resource::from_contents(contents)
    assert_true(
      resource == @referencing.Resource::new(contents, specification=expected),
    )
  }
}

///|
test "unknown dialect" {
  let dialect_id = "http://example.com/unknown-json-schema-dialect-id"
  try @referencing.Resource::from_contents({ "$schema": dialect_id }) catch {
    UnknownDialect(uri~) => assert_eq(uri, dialect_id)
    _ => fail("expected UnknownDialect")
  } noraise {
    _ => fail("expected UnknownDialect")
  }
}

///|
test "id of mapping" {
  let uri = "http://example.com/some-schema"
  let cases = [
    ("$id", @jsonschema.draft202012()),
    ("$id", @jsonschema.draft201909()),
    ("$id", @jsonschema.draft7()),
    ("$id", @jsonschema.draft6()),
    ("id", @jsonschema.draft4()),
    ("id", @jsonschema.draft3()),
  ]
  for case in cases {
    let (id, specification) = case
    let contents = Json::object(Map::from_array([(id, Json::string(uri))]))
    assert_eq(specification.id_of(contents), Some(uri))
  }
}

///|
test "id_of / anchors_in / subresources_of bool" {
  let specifications = [
    @jsonschema.draft202012(),
    @jsonschema.draft201909(),
    @jsonschema.draft7(),
    @jsonschema.draft6(),
  ]
  for specification in specifications {
    for value in [true, false] {
      let value = Json::boolean(value)
      assert_eq(specification.id_of(value), None)
      assert_true(specification.anchors_in(value).is_empty())
      assert_eq(specification.subresources_of(value), [])
    }
  }
}

///|
test "specification_with" {
  for case in dialects() {
    let (uri, expected) = case
    assert_true(physical_equal(@jsonschema.specification_with(uri), expected))
  }
}

///|
test "specification_with no empty fragment" {
  let cases = [
    ("http://json-schema.org/draft-07/schema", @jsonschema.draft7()),
    ("http://json-schema.org/draft-06/schema", @jsonschema.draft6()),
    ("http://json-schema.org/draft-04/schema", @jsonschema.draft4()),
    ("http://json-schema.org/draft-03/schema", @jsonschema.draft3()),
  ]
  for case in cases {
    let (uri, expected) = case
    assert_true(@jsonschema.specification_with(uri) == expected)
  }
}

///|
test "specification_with unknown dialect" {
  let dialect_id = "http://example.com/unknown-json-schema-dialect-id"
  try @jsonschema.specification_with(dialect_id) catch {
    UnknownDialect(uri~) => assert_eq(uri, dialect_id)
    _ => fail("expected UnknownDialect")
  } noraise {
    _ => fail("expected UnknownDialect")
  }
}

///|
test "specification_with default" {
  let dialect_id = "http://example.com/unknown-json-schema-dialect-id"
  let specification = @jsonschema.specification_with(
    dialect_id,
    default=@referencing.opaque_specification,
  )
  assert_true(physical_equal(specification, @referencing.opaque_specification))
}

///|
test "lookup trivial dynamic ref" {
  let one = @jsonschema.draft202012().create_resource({
    "$dynamicAnchor": "foo",
  })
  let resolver = @referencing.Registry::new()
    .with_resource("http://example.com", one)
    .resolver()
  let resolved = resolver.lookup("http://example.com#foo")
  assert_true(resolved.contents == one.contents)
}

///|
fn dynamic_root() -> Json {
  {
    "$id": "http://example.com",
    "$dynamicAnchor": "fooAnchor",
    "$defs": {
      "foo": {
        "$id": "foo",
        "$dynamicAnchor": "fooAnchor",
        "$defs": { "bar": true, "baz": { "$dynamicAnchor": "fooAnchor" } },
      },
    },
  }
}

///|
test "multiple lookup trivial dynamic ref" {
  let true_ = @jsonschema.draft202012().create_resource(true)
  let root = @jsonschema.draft202012().create_resource(dynamic_root())
  let resolver = @referencing.Registry::new()
    .with_resources([
      ("http://example.com", root),
      ("http://example.com/foo/", true_),
      ("http://example.com/foo/bar", root),
    ])
    .resolver()
  let first = resolver.lookup("http://example.com")
  let second = first.resolver.lookup("foo/")
  let resolver = second.resolver.lookup("bar").resolver
  let fourth = resolver.lookup("#fooAnchor")
  assert_true(fourth.contents == root.contents)
}

///|
test "multiple lookup dynamic ref to nondynamic ref" {
  let one = @jsonschema.draft202012().create_resource({ "$anchor": "fooAnchor" })
  let two = @jsonschema.draft202012().create_resource(dynamic_root())
  let resolver = @referencing.Registry::new()
    .with_resources([
      ("http://example.com", two),
      ("http://example.com/foo/", one),
      ("http://example.com/foo/bar", two),
    ])
    .resolver()
  let first = resolver.lookup("http://example.com")
  let second = first.resolver.lookup("foo/")
  let resolver = second.resolver.lookup("bar").resolver
  let fourth = resolver.lookup("#fooAnchor")
  assert_true(fourth.contents == two.contents)
}

///|
test "lookup trivial recursive ref" {
  let one = @jsonschema.draft201909().create_resource({
    "$recursiveAnchor": true,
  })
  let resolver = @referencing.Registry::new()
    .with_resource("http://example.com", one)
    .resolver()
  let first = resolver.lookup("http://example.com")
  let resolved = @jsonschema.lookup_recursive_ref(first.resolver)
  assert_true(resolved.contents == one.contents)
}

///|
test "lookup recursive ref to bool" {
  let true_ = @jsonschema.draft201909().create_resource(true)
  let registry = @referencing.Registry::new(resources=[
    ("http://example.com", true_),
  ])
  let resolved = @jsonschema.lookup_recursive_ref(
    registry.resolver(base_uri="http://example.com"),
  )
  assert_true(resolved.contents == true_.contents)
}

///|
fn recursive_root() -> Json {
  {
    "$id": "http://example.com",
    "$recursiveAnchor": true,
    "$defs": {
      "foo": {
        "$id": "foo",
        "$recursiveAnchor": true,
        "$defs": {
          "bar": true,
          "baz": { "$recursiveAnchor": true, "$anchor": "fooAnchor" },
        },
      },
    },
  }
}

///|
test "multiple lookup recursive ref to bool" {
  let true_ = @jsonschema.draft201909().create_resource(true)
  let root = @jsonschema.draft201909().create_resource(recursive_root())
  let resolver = @referencing.Registry::new()
    .with_resources([
      ("http://example.com", root),
      ("http://example.com/foo/", true_),
      ("http://example.com/foo/bar", root),
    ])
    .resolver()
  let first = resolver.lookup("http://example.com")
  let second = first.resolver.lookup("foo/")
  let resolver = second.resolver.lookup("bar").resolver
  let fourth = @jsonschema.lookup_recursive_ref(resolver)
  assert_true(fourth.contents == root.contents)
}

///|
test "multiple lookup recursive ref with nonrecursive ref" {
  let one = @jsonschema.draft201909().create_resource({
    "$recursiveAnchor": true,
  })
  let two = @jsonschema.draft201909().create_resource(recursive_root())
  let three = @jsonschema.draft201909().create_resource({
    "$recursiveAnchor": false,
  })
  let resolver = @referencing.Registry::new()
    .with_resources([
      ("http://example.com", three),
      ("http://example.com/foo/", two),
      ("http://example.com/foo/bar", one),
    ])
    .resolver()
  let first = resolver.lookup("http://example.com")
  let second = first.resolver.lookup("foo/")
  let resolver = second.resolver.lookup("bar").resolver
  let fourth = @jsonschema.lookup_recursive_ref(resolver)
  assert_true(fourth.contents == two.contents)
}

///|
test "empty registry" {
  assert_true(@jsonschema.empty_registry == @referencing.Registry::new())
}

// Beyond upstream's tests: draft-specific rules mirrored from upstream.

///|
test "legacy ids ignore $ref siblings and treat #fragments as anchors" {
  let with_ref : Json = { "$ref": "#/x", "$id": "http://example.com/a" }
  assert_eq(@jsonschema.draft7().id_of(with_ref), None)
  assert_eq(@jsonschema.draft202012().id_of(with_ref), Some("http://example.com/a"))
  assert_eq(@jsonschema.draft4().id_of({ "$ref": "#/x", "id": "a" }), None)
  assert_eq(@jsonschema.draft6().id_of({ "$id": "#foo" }), None)
  let anchors = @jsonschema.draft6().anchors_in({ "$id": "#foo" })
  assert_eq(anchors.length(), 1)
  inspect(
    anchors[0],
    content=(
      #|Anchor(name='foo', resource=Resource(contents={'$id': '#foo'}, _specification=<Specification name='draft-06'>))
    ),
  )
  let anchors = @jsonschema.draft202012().anchors_in({
    "$anchor": "a",
    "$dynamicAnchor": "d",
  })
  assert_eq(anchors.map(a => (a.kind(), a.name)), [
    ("Anchor", "a"),
    ("DynamicAnchor", "d"),
  ])
  assert_true(anchors[1].is_dynamic())
  // 2019-09 has no $dynamicAnchor
  assert_eq(
    @jsonschema.draft201909().anchors_in({ "$dynamicAnchor": "d" }).length(),
    0,
  )
}

///|
test "subresources of older drafts" {
  let schema : Json = {
    "items": [{ "a": 1 }, { "b": 2 }],
    "dependencies": { "x": { "c": 3 }, "y": ["d"] },
    "additionalProperties": { "e": 4 },
    "additionalItems": false,
    "properties": { "p": { "f": 5 } },
    "allOf": [{ "g": 6 }],
    "not": { "h": 7 },
  }
  json_inspect(@jsonschema.draft4().subresources_of(schema), content=[
    { "h": 7 },
    { "g": 6 },
    { "f": 5 },
    { "a": 1 },
    { "b": 2 },
    { "c": 3 },
    ["d"],
    { "e": 4 },
  ])
  json_inspect(@jsonschema.draft7().subresources_of(schema), content=[
    false,
    { "e": 4 },
    { "h": 7 },
    { "g": 6 },
    { "f": 5 },
    { "a": 1 },
    { "b": 2 },
    { "c": 3 },
    ["d"],
  ])
  // dependencies are only subresources if the first one is a schema
  json_inspect(
    @jsonschema.draft7().subresources_of({ "dependencies": { "y": ["d"], "x": {} } }),
    content=[],
  )
  json_inspect(
    @jsonschema.draft202012().subresources_of({ "items": { "a": 1 } }),
    content=[{ "a": 1 }],
  )
  json_inspect(
    @jsonschema.draft202012().subresources_of({ "items": [{ "a": 1 }] }),
    content=[[{ "a": 1 }]],
  )
}
