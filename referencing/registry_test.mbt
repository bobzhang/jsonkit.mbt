// Port of upstream's TestRegistry (referencing/tests/test_core.py).

///|
test "with_resource" {
  let resource = opaque_resource({ "foo": "bar" })
  let uri = "urn:example"
  let registry = @referencing.Registry::new().with_resource(uri, resource)
  assert_true(physical_equal(registry.at(uri), resource))
}

///|
test "with_resources" {
  let one = opaque_resource({})
  let two = @referencing.Resource::new(
    { "foo": "bar" },
    specification=id_and_children,
  )
  let registry = @referencing.Registry::new().with_resources([
    ("http://example.com/1", one),
    ("http://example.com/foo/bar", two),
  ])
  assert_true(
    registry ==
    @referencing.Registry::new()
    .with_resource("http://example.com/1", one)
    .with_resource("http://example.com/foo/bar", two),
  )
}

///|
test "matmul resource" {
  let uri = "urn:example:resource"
  let resource = id_and_children.create_resource({ "ID": uri, "foo": 12 })
  let registry = @referencing.Registry::new().with_identified_resource(resource)
  assert_true(
    registry == @referencing.Registry::new().with_resource(uri, resource),
  )
}

///|
test "matmul many resources" {
  let one_uri = "urn:example:one"
  let one = id_and_children.create_resource({ "ID": one_uri, "foo": 12 })
  let two_uri = "urn:example:two"
  let two = id_and_children.create_resource({ "ID": two_uri, "foo": 12 })
  let registry = @referencing.Registry::new().with_identified_resources([
    one, two,
  ])
  assert_true(
    registry ==
    @referencing.Registry::new().with_resources([(one_uri, one), (two_uri, two)]),
  )
}

///|
test "matmul resource without id" {
  let resource = opaque_resource({ "foo": "bar" })
  try @referencing.Registry::new().with_identified_resource(resource) catch {
    error => assert_true(error == NoInternalID(resource~))
  } noraise {
    _ => fail("expected NoInternalID")
  }
}

///|
test "with_contents from json schema" {
  let uri = "urn:example"
  let schema : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let registry = @referencing.Registry::new().with_contents([(uri, schema)])
  let expected = @referencing.Resource::new(
    schema,
    specification=@referencing.draft202012(),
  )
  assert_true(registry.at(uri) == expected)
}

///|
test "with_contents and default specification" {
  let uri = "urn:example"
  let registry = @referencing.Registry::new().with_contents(
    [(uri, { "foo": "bar" })],
    default_specification=@referencing.opaque_specification,
  )
  assert_true(registry.at(uri) == opaque_resource({ "foo": "bar" }))
}

///|
fn numbered_registry(total : Int) -> @referencing.Registry raise {
  @referencing.Registry::new().with_contents(
    Array::makei(total, i => (i.to_string(), ({ "foo": "bar" } : Json))),
    default_specification=@referencing.opaque_specification,
  )
}

///|
test "len / bool / iter" {
  inspect(numbered_registry(5).length(), content="5")
  assert_true(@referencing.Registry::new().is_empty())
  assert_false(numbered_registry(3).is_empty())
  let keys = numbered_registry(8).iter().to_array()
  keys.sort()
  debug_inspect(
    keys,
    content=(
      #|["0", "1", "2", "3", "4", "5", "6", "7"]
    ),
  )
}

///|
test "crawl still has top level resource" {
  let resource = opaque_resource({ "foo": "bar" })
  let uri = "urn:example"
  let registry = @referencing.Registry::new(resources=[(uri, resource)]).crawl()
  assert_true(physical_equal(registry.at(uri), resource))
}

///|
test "crawl finds a subresource" {
  let child_id = "urn:child"
  let root = id_and_children.create_resource({
    "ID": "urn:root",
    "children": [{ "ID": child_id, "foo": 12 }],
  })
  let registry = @referencing.Registry::new().with_identified_resource(root)
  try registry.at(child_id) catch {
    NoSuchResource(..) => ()
    _ => fail("expected NoSuchResource")
  } noraise {
    _ => fail("expected a lookup error")
  }
  let expected = id_and_children.create_resource({ "ID": child_id, "foo": 12 })
  assert_true(registry.crawl().at(child_id) == expected)
}

///|
test "crawl finds anchors with id" {
  let resource = id_and_children.create_resource({
    "ID": "urn:bar",
    "anchors": { "foo": 12 },
  })
  let registry = @referencing.Registry::new().with_identified_resource(resource)
  assert_true(
    registry.crawl().anchor(resource.id().unwrap(), "foo").value ==
    @referencing.Anchor::new(
      name="foo",
      resource=id_and_children.create_resource(12),
    ),
  )
}

///|
test "crawl finds anchors no id" {
  let resource = id_and_children.create_resource({ "anchors": { "foo": 12 } })
  let registry = @referencing.Registry::new().with_resource(
    "urn:root", resource,
  )
  assert_true(
    registry.crawl().anchor("urn:root", "foo").value ==
    @referencing.Anchor::new(
      name="foo",
      resource=id_and_children.create_resource(12),
    ),
  )
}

///|
test "contents" {
  let resource = opaque_resource({ "foo": "bar" })
  let uri = "urn:example"
  let registry = @referencing.Registry::new().with_resource(uri, resource)
  json_inspect(registry.contents(uri), content={ "foo": "bar" })
}

///|
test "getitem / contents strip empty fragments" {
  let uri = "http://example.com/"
  let resource = id_and_children.create_resource({ "ID": uri + "#" })
  let registry = @referencing.Registry::new().with_identified_resource(resource)
  assert_true(registry.at(uri) == registry.at(uri + "#"))
  assert_true(registry.at(uri) == resource)
  assert_true(registry.contents(uri) == registry.contents(uri + "#"))
  json_inspect(registry.contents(uri), content={ "ID": "http://example.com/#" })
}

///|
test "contents nonexistent resource" {
  try @referencing.Registry::new().contents("urn:example") catch {
    error => {
      assert_true(error == NoSuchResource(reference="urn:example"))
      inspect(error, content="'urn:example'")
    }
  } noraise {
    _ => fail("expected NoSuchResource")
  }
}

///|
test "crawled anchor" {
  let resource = id_and_children.create_resource({ "anchors": { "foo": "bar" } })
  let registry = @referencing.Registry::new().with_resource(
    "urn:example", resource,
  )
  let retrieved = registry.anchor("urn:example", "foo")
  assert_true(
    retrieved.value ==
    @referencing.Anchor::new(
      name="foo",
      resource=id_and_children.create_resource("bar"),
    ),
  )
  assert_true(retrieved.registry == registry.crawl())
}

///|
test "anchor in nonexistent resource" {
  try @referencing.Registry::new().anchor("urn:example", "foo") catch {
    @referencing.NoSuchResource(reference~) =>
      assert_eq(reference, "urn:example")
    _ => fail("expected NoSuchResource")
  } noraise {
    _ => fail("expected NoSuchResource")
  }
}

///|
test "init" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(resources=[
    ("http://example.com/1", one),
    ("http://example.com/foo/bar", two),
  ])
  assert_true(
    registry ==
    @referencing.Registry::new()
    .with_resources([
      ("http://example.com/1", one),
      ("http://example.com/foo/bar", two),
    ])
    .crawl(),
  )
}

///|
test "dict conversion" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(resources=[
    ("http://example.com/1", one),
  ]).with_resource("http://example.com/foo/bar", two)
  assert_true(
    registry.crawl() ==
    @referencing.Registry::new()
    .with_resources([
      ("http://example.com/1", one),
      ("http://example.com/foo/bar", two),
    ])
    .crawl(),
  )
}

///|
test "no such resource" {
  try @referencing.Registry::new().at("urn:bigboom") catch {
    error => assert_true(error == NoSuchResource(reference="urn:bigboom"))
  } noraise {
    _ => fail("expected NoSuchResource")
  }
}

///|
test "combine" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let three = id_and_children.create_resource({ "baz": "quux" })
  let four = id_and_children.create_resource({ "anchors": { "foo": 12 } })
  let first = @referencing.Registry::new(resources=[
    ("http://example.com/1", one),
  ])
  let second = @referencing.Registry::new().with_resource(
    "http://example.com/foo/bar", two,
  )
  let third = @referencing.Registry::new(resources=[
    ("http://example.com/1", one),
    ("http://example.com/baz", three),
  ])
  let fourth = @referencing.Registry::new()
    .with_resource("http://example.com/foo/quux", four)
    .crawl()
  let expected = @referencing.Registry::new(
    resources=[
      ("http://example.com/1", one),
      ("http://example.com/baz", three),
      ("http://example.com/foo/quux", four),
    ],
    anchors=[
      (
        ("http://example.com/foo/quux", "foo"),
        @referencing.Anchor::new(
          name="foo",
          resource=id_and_children.create_resource(12),
        ),
      ),
    ],
  ).with_resource("http://example.com/foo/bar", two)
  assert_true(first.combine([second, third, fourth]) == expected)
}

///|
test "combine self" {
  let registry = @referencing.Registry::new(resources=[
    ("urn:foo", opaque_resource("bar")),
  ])
  assert_true(physical_equal(registry.combine([registry]), registry))
}

///|
test "combine with uncrawled resources" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let three = id_and_children.create_resource({ "baz": "quux" })
  let first = @referencing.Registry::new().with_resource(
    "http://example.com/1", one,
  )
  let second = @referencing.Registry::new().with_resource(
    "http://example.com/foo/bar", two,
  )
  let third = @referencing.Registry::new(resources=[
    ("http://example.com/1", one),
    ("http://example.com/baz", three),
  ])
  let expected = @referencing.Registry::new(resources=[
    ("http://example.com/1", one),
    ("http://example.com/foo/bar", two),
    ("http://example.com/baz", three),
  ])
  let combined = first.combine([second, third])
  assert_true(combined != expected)
  assert_true(combined.crawl() == expected)
}

///|
test "combine with single retrieve" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let three = id_and_children.create_resource({ "baz": "quux" })
  let retrieve : (String) -> @referencing.Resource raise = _ => {
    opaque_resource(null)
  }
  let first = @referencing.Registry::new().with_resource(
    "http://example.com/1", one,
  )
  let second = @referencing.Registry::new(retrieve~).with_resource(
    "http://example.com/2", two,
  )
  let third = @referencing.Registry::new().with_resource(
    "http://example.com/3", three,
  )
  let expected = @referencing.Registry::new(retrieve~).with_resources([
    ("http://example.com/1", one),
    ("http://example.com/2", two),
    ("http://example.com/3", three),
  ])
  assert_true(first.combine([second, third]) == expected)
  assert_true(second.combine([first, third]) == expected)
}

///|
test "combine with common retrieve" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let three = id_and_children.create_resource({ "baz": "quux" })
  let retrieve : (String) -> @referencing.Resource raise = _ => {
    opaque_resource(null)
  }
  let first = @referencing.Registry::new(retrieve~).with_resource(
    "http://example.com/1", one,
  )
  let second = @referencing.Registry::new(retrieve~).with_resource(
    "http://example.com/2", two,
  )
  let third = @referencing.Registry::new(retrieve~).with_resource(
    "http://example.com/3", three,
  )
  let expected = @referencing.Registry::new(retrieve~).with_resources([
    ("http://example.com/1", one),
    ("http://example.com/2", two),
    ("http://example.com/3", three),
  ])
  assert_true(first.combine([second, third]) == expected)
  assert_true(second.combine([first, third]) == expected)
}

///|
test "combine conflicting retrieve" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let three = id_and_children.create_resource({ "baz": "quux" })
  let foo_retrieve : (String) -> @referencing.Resource raise = _ => {
    opaque_resource(null)
  }
  let bar_retrieve : (String) -> @referencing.Resource raise = _ => {
    opaque_resource(true)
  }
  let first = @referencing.Registry::new(retrieve=foo_retrieve).with_resource(
    "http://example.com/1", one,
  )
  let second = @referencing.Registry::new().with_resource(
    "http://example.com/2", two,
  )
  let third = @referencing.Registry::new(retrieve=bar_retrieve).with_resource(
    "http://example.com/3", three,
  )
  try first.combine([second, third]) catch {
    error =>
      inspect(
        error,
        content="Cannot combine registries with conflicting retrieval functions.",
      )
  } noraise {
    _ => fail("expected a conflict")
  }
}

///|
test "remove" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(resources=[
    ("urn:foo", one),
    ("urn:bar", two),
  ])
  assert_true(
    registry.remove("urn:foo") ==
    @referencing.Registry::new(resources=[("urn:bar", two)]),
  )
}

///|
test "remove uncrawled" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new().with_resources([
    ("urn:foo", one),
    ("urn:bar", two),
  ])
  assert_true(
    registry.remove("urn:foo") ==
    @referencing.Registry::new().with_resource("urn:bar", two),
  )
}

///|
test "remove with anchors" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "anchors": { "foo": "bar" } })
  let registry = @referencing.Registry::new()
    .with_resources([("urn:foo", one), ("urn:bar", two)])
    .crawl()
  assert_true(
    registry.remove("urn:bar") ==
    @referencing.Registry::new().with_resource("urn:foo", one).crawl(),
  )
}

///|
test "remove nonexistent uri" {
  try @referencing.Registry::new().remove("urn:doesNotExist") catch {
    error => assert_true(error == NoSuchResource(reference="urn:doesNotExist"))
  } noraise {
    _ => fail("expected NoSuchResource")
  }
}

///|
test "retrieve" {
  let foo = opaque_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(retrieve=_ => foo)
  assert_true(registry.get_or_retrieve("urn:example").value == foo)
}

///|
suberror OhNo {
  OhNo(String)
}

///|
test "retrieve arbitrary exception" {
  let foo = opaque_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(retrieve=uri => {
    if uri == "urn:succeed" {
      return foo
    }
    raise OhNo("Oh no!")
  })
  assert_true(registry.get_or_retrieve("urn:succeed").value == foo)
  try registry.get_or_retrieve("urn:uhoh") catch {
    @referencing.Unretrievable(reference~, cause~) => {
      assert_eq(reference, "urn:uhoh")
      assert_true(cause is Some(OhNo(_)))
    }
    _ => fail("expected Unretrievable")
  } noraise {
    _ => fail("expected Unretrievable")
  }
}

///|
test "retrieve no such resource" {
  let foo = opaque_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(retrieve=uri => {
    if uri == "urn:succeed" {
      return foo
    }
    raise @referencing.NoSuchResource(reference=uri)
  })
  assert_true(registry.get_or_retrieve("urn:succeed").value == foo)
  try registry.get_or_retrieve("urn:uhoh") catch {
    @referencing.NoSuchResource(..) => ()
    _ => fail("expected NoSuchResource")
  } noraise {
    _ => fail("expected NoSuchResource")
  }
}

///|
test "retrieve cannot determine specification" {
  let registry = @referencing.Registry::new(retrieve=_ => {
    @referencing.Resource::from_contents({})
  })
  try registry.get_or_retrieve("urn:uhoh") catch {
    @referencing.CannotDetermineSpecification(..) => ()
    _ => fail("expected CannotDetermineSpecification")
  } noraise {
    _ => fail("expected CannotDetermineSpecification")
  }
}

///|
test "retrieve already available resource" {
  let foo = opaque_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(
    resources=[("urn:example", foo)],
    retrieve=blow_up,
  )
  assert_true(registry.at("urn:example") == foo)
  assert_true(registry.get_or_retrieve("urn:example").value == foo)
}

///|
test "retrieve first checks crawlable resource" {
  let child = id_and_children.create_resource({ "ID": "urn:child", "foo": 12 })
  let root = id_and_children.create_resource({ "children": [child.contents] })
  let registry = @referencing.Registry::new(retrieve=blow_up).with_resource(
    "urn:root", root,
  )
  assert_true(registry.crawl().at("urn:child") == child)
}

///|
test "resolver" {
  let one = opaque_resource({})
  let registry = @referencing.Registry::new(resources=[
    ("http://example.com", one),
  ])
  let resolver = registry.resolver(base_uri="http://example.com")
  json_inspect(resolver.lookup("#").contents, content={})
}

///|
test "resolver with root identified" {
  let root = id_and_children.create_resource({ "ID": "http://example.com" })
  let resolver = @referencing.Registry::new().resolver_with_root(root)
  assert_true(resolver.lookup("http://example.com").contents == root.contents)
  assert_true(resolver.lookup("#").contents == root.contents)
}

///|
test "resolver with root unidentified" {
  let root = opaque_resource({})
  let resolver = @referencing.Registry::new().resolver_with_root(root)
  assert_true(resolver.lookup("#").contents == root.contents)
}

///|
test "repr" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new().with_resources([
    ("http://example.com/1", one),
    ("http://example.com/foo/bar", two),
  ])
  inspect(registry, content="<Registry (2 uncrawled resources)>")
  inspect(registry.crawl(), content="<Registry (2 resources)>")
}

///|
test "repr mixed crawled" {
  let one = opaque_resource({})
  let two = id_and_children.create_resource({ "foo": "bar" })
  let registry = @referencing.Registry::new(resources=[
      ("http://example.com/1", one),
    ])
    .crawl()
    .with_resource("http://example.com/foo/bar", two)
  inspect(registry, content="<Registry (2 resources, 1 uncrawled)>")
}

///|
test "repr one resource" {
  let registry = @referencing.Registry::new().with_resource(
    "http://example.com/1",
    opaque_resource({}),
  )
  inspect(registry, content="<Registry (1 uncrawled resource)>")
}

///|
test "repr empty" {
  inspect(@referencing.Registry::new(), content="<Registry (0 resources)>")
}
