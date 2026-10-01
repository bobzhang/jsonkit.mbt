// Port of upstream's TestResolver (referencing/tests/test_core.py).

///|
fn expect_unresolvable(
  resolver : @referencing.Resolver,
  reference : String,
) -> @referencing.ReferencingError raise {
  try resolver.lookup(reference) catch {
    error => {
      assert_true(
        @referencing.is_unresolvable(error),
        msg="\{error} is not Unresolvable",
      )
      @referencing.ReferencingError::from_error(error).unwrap()
    }
  } noraise {
    _ => fail("expected \{reference} to be unresolvable")
  }
}

///|
test "lookup exact uri" {
  let resource = opaque_resource({ "foo": "baz" })
  let resolver = @referencing.Registry::new(resources=[
    ("http://example.com/1", resource),
  ]).resolver()
  let resolved = resolver.lookup("http://example.com/1")
  assert_true(resolved.contents == resource.contents)
}

///|
test "lookup subresource" {
  let root = id_and_children.create_resource({
    "ID": "http://example.com/",
    "children": [{ "ID": "http://example.com/a", "foo": 12 }],
  })
  let registry = @referencing.Registry::new().with_identified_resource(root)
  let resolved = registry.resolver().lookup("http://example.com/a")
  json_inspect(resolved.contents, content={
    "ID": "http://example.com/a",
    "foo": 12,
  })
}

///|
test "lookup anchor with id" {
  let root = id_and_children.create_resource({
    "ID": "http://example.com/",
    "anchors": { "foo": 12 },
  })
  let registry = @referencing.Registry::new().with_identified_resource(root)
  let resolved = registry.resolver().lookup("http://example.com/#foo")
  json_inspect(resolved.contents, content=12)
}

///|
test "lookup anchor without id" {
  let root = id_and_children.create_resource({ "anchors": { "foo": 12 } })
  let resolver = @referencing.Registry::new()
    .with_resource("urn:example", root)
    .resolver()
  let resolved = resolver.lookup("urn:example#foo")
  json_inspect(resolved.contents, content=12)
}

///|
test "lookup unknown reference" {
  let resolver = @referencing.Registry::new().resolver()
  let reference = "http://example.com/does/not/exist"
  let error = expect_unresolvable(resolver, reference)
  assert_true(error == Unresolvable(reference~))
  inspect(error, content="http://example.com/does/not/exist")
}

///|
test "lookup non existent pointer" {
  let resource = opaque_resource({ "foo": {} })
  let resolver = @referencing.Registry::new(resources=[
    ("http://example.com/1", resource),
  ]).resolver()
  let error = expect_unresolvable(resolver, "http://example.com/1#/foo/bar")
  assert_true(error == PointerToNowhere(reference="/foo/bar", resource~))
  inspect(error, content="'/foo/bar' does not exist within {'foo': {}}")
}

///|
test "lookup non existent pointer to array index" {
  let resource = opaque_resource([1, 2, 4, 8])
  let resolver = @referencing.Registry::new(resources=[
    ("http://example.com/1", resource),
  ]).resolver()
  let error = expect_unresolvable(resolver, "http://example.com/1#/10")
  assert_true(error == PointerToNowhere(reference="/10", resource~))
}

///|
test "lookup pointer to empty string" {
  let resolver = @referencing.Registry::new().resolver_with_root(
    opaque_resource({ "": {} }),
  )
  json_inspect(resolver.lookup("#/").contents, content={})
}

///|
test "lookup non existent pointer to empty string" {
  let resource = opaque_resource({ "foo": {} })
  let resolver = @referencing.Registry::new().resolver_with_root(resource)
  let error = expect_unresolvable(resolver, "#/")
  assert_true(error == PointerToNowhere(reference="/", resource~))
  inspect(
    error,
    content="'/' does not exist within {'foo': {}}. The pointer '/' is a valid JSON Pointer but it points to an empty string property ''. If you intended to point to the entire resource, you should use '#'.",
  )
}

///|
test "lookup non existent anchor" {
  let root = id_and_children.create_resource({ "anchors": {} })
  let resolver = @referencing.Registry::new()
    .with_resource("urn:example", root)
    .resolver()
  let resolved = resolver.lookup("urn:example")
  assert_true(resolved.contents == root.contents)
  let error = expect_unresolvable(resolver, "urn:example#noSuchAnchor")
  inspect(error, content="'noSuchAnchor' does not exist within {'anchors': {}}")
  assert_true(
    error ==
    NoSuchAnchor(reference="urn:example", resource=root, anchor="noSuchAnchor"),
  )
}

///|
test "lookup invalid JSON pointerish anchor" {
  let resolver = @referencing.Registry::new().resolver_with_root(
    id_and_children.create_resource({
      "ID": "http://example.com/",
      "foo": { "bar": 12 },
    }),
  )
  let valid = resolver.lookup("#/foo/bar")
  json_inspect(valid.contents, content=12)
  let error = expect_unresolvable(resolver, "#foo/bar")
  assert_true(error is InvalidAnchor(..))
  inspect(
    error,
    content="'#foo/bar' is not a valid anchor, neither as a plain name anchor nor as a JSON Pointer. You may have intended to use '#/foo/bar', as the slash is required *before each segment* of a JSON pointer.",
  )
}

///|
test "lookup retrieved resource" {
  let resource = opaque_resource({ "foo": "baz" })
  let resolver = @referencing.Registry::new(retrieve=_ => resource).resolver()
  let resolved = resolver.lookup("http://example.com/")
  assert_true(resolved.contents == resource.contents)
}

///|
test "lookup failed retrieved resource" {
  let uri = "http://example.com/"
  let registry = @referencing.Registry::new(retrieve=blow_up)
  try registry.get_or_retrieve(uri) catch {
    @referencing.Unretrievable(..) => ()
    _ => fail("expected Unretrievable")
  } noraise {
    _ => fail("expected Unretrievable")
  }
  let error = expect_unresolvable(registry.resolver(), uri)
  assert_true(error is Unresolvable(..))
}

///|
test "repeated lookup from retrieved resource" {
  let resource = opaque_resource({ "foo": "baz" })
  let once = [resource]
  let resolver = @referencing.Registry::new(retrieve=_ => once.pop().unwrap()).resolver()
  let resolved = resolver.lookup("http://example.com/")
  assert_true(resolved.contents == resource.contents)
  let resolved = resolved.resolver.lookup("http://example.com/")
  assert_true(resolved.contents == resource.contents)
}

///|
test "repeated anchor lookup from retrieved resource" {
  let resource = opaque_resource({ "foo": "baz" })
  let once = [resource]
  let resolver = @referencing.Registry::new(retrieve=_ => once.pop().unwrap()).resolver()
  let resolved = resolver.lookup("http://example.com/")
  assert_true(resolved.contents == resource.contents)
  let resolved = resolved.resolver.lookup("#")
  assert_true(resolved.contents == resource.contents)
}

///|
fn nested_root() -> @referencing.Resource {
  id_and_children.create_resource({
    "ID": "http://example.com/",
    "children": [{ "ID": "child/", "children": [{ "ID": "grandchild" }] }],
  })
}

///|
test "in subresource" {
  let root = nested_root()
  let registry = @referencing.Registry::new().with_identified_resource(root)
  let resolver = registry.resolver()
  let first = resolver.lookup("http://example.com/")
  assert_true(first.contents == root.contents)
  ignore(expect_unresolvable(first.resolver, "grandchild"))
  guard first.contents is { "children": [child, ..], .. } else { fail("") }
  let sub = first.resolver.in_subresource(
    id_and_children.create_resource(child),
  )
  let second = sub.lookup("grandchild")
  json_inspect(second.contents, content={ "ID": "grandchild" })
}

///|
test "in pointer subresource" {
  let root = nested_root()
  let registry = @referencing.Registry::new().with_identified_resource(root)
  let resolver = registry.resolver()
  let first = resolver.lookup("http://example.com/")
  assert_true(first.contents == root.contents)
  ignore(expect_unresolvable(first.resolver, "grandchild"))
  let second = first.resolver.lookup("#/children/0")
  let third = second.resolver.lookup("grandchild")
  json_inspect(third.contents, content={ "ID": "grandchild" })
}

///|
test "dynamic scope" {
  let one = nested_root()
  let two = id_and_children.create_resource({
    "ID": "http://example.com/two",
    "children": [{ "ID": "two-child/" }],
  })
  let registry = @referencing.Registry::new().with_identified_resources([
    one, two,
  ])
  let resolver = registry.resolver()
  let first = resolver.lookup("http://example.com/")
  let second = first.resolver.lookup("#/children/0")
  let third = second.resolver.lookup("grandchild")
  let fourth = third.resolver.lookup("http://example.com/two")
  let scope = (r : @referencing.Resolver) => {
    for pair in r.dynamic_scope() {
      assert_true(physical_equal(pair.1, r.registry()))
    }
    r.dynamic_scope().map(pair => pair.0).to_array()
  }
  debug_inspect(
    scope(fourth.resolver),
    content=(
      #|[
      #|  "http://example.com/child/grandchild",
      #|  "http://example.com/child/",
      #|  "http://example.com/",
      #|]
    ),
  )
  debug_inspect(
    scope(third.resolver),
    content=(
      #|["http://example.com/child/", "http://example.com/"]
    ),
  )
  debug_inspect(
    scope(second.resolver),
    content=(
      #|["http://example.com/"]
    ),
  )
  debug_inspect(scope(first.resolver), content="[]")
}
