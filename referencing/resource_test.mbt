// Port of upstream's TestResource (referencing/tests/test_core.py).

///|
test "from_contents from json schema" {
  let schema : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let resource = @referencing.Resource::from_contents(schema)
  assert_true(
    resource ==
    @referencing.Resource::new(schema, specification=@referencing.draft202012()),
  )
}

///|
test "from_contents with no discernible information" {
  try @referencing.Resource::from_contents({ "foo": "bar" }) catch {
    @referencing.CannotDetermineSpecification(contents~) as error => {
      json_inspect(contents, content={ "foo": "bar" })
      inspect(error, content="{'foo': 'bar'}")
    }
    _ => fail("expected CannotDetermineSpecification")
  } noraise {
    _ => fail("expected CannotDetermineSpecification")
  }
}

///|
test "from_contents with no discernible information and default" {
  let resource = @referencing.Resource::from_contents(
    { "foo": "bar" },
    default_specification=@referencing.opaque_specification,
  )
  assert_true(resource == opaque_resource({ "foo": "bar" }))
}

///|
test "from_contents unneeded default" {
  let schema : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let resource = @referencing.Resource::from_contents(
    schema,
    default_specification=@referencing.opaque_specification,
  )
  assert_true(
    resource ==
    @referencing.Resource::new(schema, specification=@referencing.draft202012()),
  )
}

///|
test "non mapping from_contents" {
  let resource = @referencing.Resource::from_contents(
    true,
    default_specification=id_and_children,
  )
  assert_true(
    resource == @referencing.Resource::new(true, specification=id_and_children),
  )
}

///|
test "id delegates to specification" {
  let specification = @referencing.Specification::new(
    name="",
    id_of=_ => Some("urn:fixedID"),
    subresources_of=_ => [],
    anchors_in=(_, _) => [],
    maybe_in_subresource=(_, resolver, _) => resolver,
  )
  let resource = @referencing.Resource::new({ "foo": "baz" }, specification~)
  assert_eq(resource.id(), Some("urn:fixedID"))
}

///|
test "id strips empty fragment" {
  let uri = "http://example.com/"
  let root = id_and_children.create_resource({ "ID": uri + "#" })
  assert_eq(root.id(), Some(uri))
}

///|
test "subresources delegates to specification" {
  let resource = id_and_children.create_resource({ "children": [{}, 12] })
  assert_true(
    resource.subresources() ==
    [id_and_children.create_resource({}), id_and_children.create_resource(12)],
  )
}

///|
test "subresource with different specification" {
  let schema : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let resource = id_and_children.create_resource({ "children": [schema] })
  assert_true(
    resource.subresources() ==
    [@referencing.draft202012().create_resource(schema)],
  )
}

///|
test "anchors delegates to specification" {
  let resource = id_and_children.create_resource({
    "anchors": { "foo": {}, "bar": 1, "baz": "" },
  })
  assert_true(
    resource.anchors() ==
    [
      @referencing.Anchor::new(
        name="foo",
        resource=id_and_children.create_resource({}),
      ),
      @referencing.Anchor::new(
        name="bar",
        resource=id_and_children.create_resource(1),
      ),
      @referencing.Anchor::new(
        name="baz",
        resource=id_and_children.create_resource(""),
      ),
    ],
  )
}

///|
test "pointer to mapping" {
  let resource = opaque_resource({ "foo": "baz" })
  let resolver = @referencing.Registry::new().resolver()
  json_inspect(resource.pointer("/foo", resolver).contents, content="baz")
}

///|
test "pointer to array" {
  let resource = opaque_resource({ "foo": { "bar": [3] } })
  let resolver = @referencing.Registry::new().resolver()
  json_inspect(resource.pointer("/foo/bar/0", resolver).contents, content=3)
}

///|
test "root pointer" {
  let contents : Json = { "foo": "baz" }
  let resource = opaque_resource(contents)
  let resolver = @referencing.Registry::new().resolver()
  assert_true(resource.pointer("", resolver).contents == contents)
}

///|
test "opaque" {
  let contents : Json = { "foo": "bar" }
  assert_true(
    opaque_resource(contents) ==
    @referencing.Resource::new(
      contents,
      specification=@referencing.opaque_specification,
    ),
  )
}

///|
test "repr" {
  inspect(
    opaque_resource({ "foo": [1, 2.5, true, null, "it's"] }),
    content=(
      #|Resource(contents={'foo': [1, 2.5, True, None, "it's"]}, _specification=<Specification name='opaque'>)
    ),
  )
}

// Beyond upstream's tests: the exact pointer semantics mirrored from Python.

///|
test "pointer escapes, percent-decoding and Python-style indices" {
  let resource = opaque_resource({
    "a/b": 1,
    "m~n": 2,
    "~1": 3,
    "%": 4,
    "c d": 5,
    "arr": [10, 20, 30],
    "s": "héllo",
    "": { "": 6 },
  })
  let resolver = @referencing.Registry::new().resolver()
  let at = (p : String) => resource.pointer(p, resolver).contents
  json_inspect(at("/a~1b"), content=1)
  json_inspect(at("/m~0n"), content=2)
  // ~1 is replaced before ~0, so "~01" means "~1"
  json_inspect(at("/~01"), content=3)
  // the pointer is percent-decoded first
  json_inspect(at("/%25"), content=4)
  json_inspect(at("/c%20d"), content=5)
  json_inspect(at("/arr/-1"), content=30)
  json_inspect(at("/arr/+1"), content=20)
  json_inspect(at("/arr/ 2 "), content=30)
  json_inspect(at("/arr/0_1"), content=20)
  json_inspect(at("/s/1"), content="é")
  json_inspect(at("/"), content={ "": 6 })
  json_inspect(at("//"), content=6)
  // "%2F" is decoded *before* splitting (as upstream), so it is a separator
  for
    bad in [
      "/a%2Fb", "/arr/3", "/arr/-4", "/arr/x", "/arr/", "/nope", "/arr/0/0", "/s/9",
    ] {
    try resource.pointer(bad, resolver) catch {
      @referencing.PointerToNowhere(reference~, ..) => assert_eq(reference, bad)
      _ => fail("unexpected error for \{bad}")
    } noraise {
      _ => fail("expected PointerToNowhere for \{bad}")
    }
  }
}
