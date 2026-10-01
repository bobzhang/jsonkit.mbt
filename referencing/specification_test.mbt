// Port of upstream's TestSpecification and TestOpaqueSpecification
// (referencing/tests/test_core.py).

///|
test "create resource" {
  let specification = @referencing.Specification::new(
    name="",
    id_of=_ => Some("urn:fixedID"),
    subresources_of=_ => [],
    anchors_in=(_, _) => [],
    maybe_in_subresource=(_, resolver, _) => resolver,
  )
  let resource = specification.create_resource({ "foo": "baz" })
  assert_true(
    resource == @referencing.Resource::new({ "foo": "baz" }, specification~),
  )
  assert_eq(resource.id(), Some("urn:fixedID"))
}

///|
test "detect from json schema" {
  let schema : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let specification = @referencing.Specification::detect(schema)
  assert_true(specification == @referencing.draft202012())
}

///|
fn expect_cannot_determine(contents : Json) -> Unit raise {
  try @referencing.Specification::detect(contents) catch {
    CannotDetermineSpecification(contents=c) => assert_true(c == contents)
    _ => fail("expected CannotDetermineSpecification")
  } noraise {
    _ => fail("expected CannotDetermineSpecification")
  }
}

///|
test "detect with no discernible information" {
  expect_cannot_determine({ "foo": "bar" })
}

///|
test "detect with non URI schema" {
  expect_cannot_determine({ "$schema": 37 })
}

///|
test "detect with no discernible information and default" {
  let specification = @referencing.Specification::detect(
    { "foo": "bar" },
    default=@referencing.opaque_specification,
  )
  assert_true(physical_equal(specification, @referencing.opaque_specification))
}

///|
test "detect unneeded default" {
  let schema : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let specification = @referencing.Specification::detect(
    schema,
    default=@referencing.opaque_specification,
  )
  assert_true(specification == @referencing.draft202012())
}

///|
test "non mapping detect" {
  expect_cannot_determine(true)
}

///|
test "non mapping detect with default" {
  let specification = @referencing.Specification::detect(
    true,
    default=id_and_children,
  )
  assert_true(physical_equal(specification, id_and_children))
}

///|
test "detect unknown dialect" {
  let dialect_id = "http://example.com/unknown-json-schema-dialect-id"
  try @referencing.Specification::detect({ "$schema": dialect_id }) catch {
    UnknownDialect(uri~) as error => {
      assert_eq(uri, dialect_id)
      inspect(error, content=dialect_id)
    }
    _ => fail("expected UnknownDialect")
  } noraise {
    _ => fail("expected UnknownDialect")
  }
  // ... but falls back to the default when there is one
  let specification = @referencing.Specification::detect(
    { "$schema": dialect_id },
    default=id_and_children,
  )
  assert_true(physical_equal(specification, id_and_children))
}

///|
test "repr" {
  inspect(id_and_children, content="<Specification name='id-and-children'>")
}

///|
test "opaque: no id, no subresources, no anchors" {
  let things : Array[Json] = [{ "foo": "bar" }, true, 37, "foo"]
  for thing in things {
    assert_eq(@referencing.opaque_specification.id_of(thing), None)
    assert_eq(@referencing.opaque_specification.subresources_of(thing), [])
    assert_true(@referencing.opaque_specification.anchors_in(thing).is_empty())
  }
}

///|
test "anchor equality includes the resolve callback identity (Codex review)" {
  let resource = opaque_resource({ "a": 1 })
  let resolve_a : (@referencing.Anchor, @referencing.Resolver) -> @referencing.Resolved raise = (
    _,
    resolver,
  ) => { contents: "a", resolver, }
  let resolve_b : (@referencing.Anchor, @referencing.Resolver) -> @referencing.Resolved raise = (
    _,
    resolver,
  ) => { contents: "b", resolver, }
  let a1 = @referencing.Anchor::custom(
    name="x",
    resource~,
    kind="Custom",
    resolve=resolve_a,
  )
  let a2 = @referencing.Anchor::custom(
    name="x",
    resource~,
    kind="Custom",
    resolve=resolve_a,
  )
  let b = @referencing.Anchor::custom(
    name="x",
    resource~,
    kind="Custom",
    resolve=resolve_b,
  )
  assert_true(a1 == a2)
  assert_true(a1 != b)
  // plain anchors never equal custom ones, even of the same kind name
  let plain = @referencing.Anchor::new(name="x", resource~)
  let fake = @referencing.Anchor::custom(
    name="x",
    resource~,
    kind="Anchor",
    resolve=resolve_a,
  )
  assert_true(plain == @referencing.Anchor::new(name="x", resource~))
  assert_true(plain != fake)
  // independently created dynamic anchors still compare equal
  assert_true(
    @referencing.dynamic_anchor(name="x", resource~) ==
    @referencing.dynamic_anchor(name="x", resource~),
  )
}
