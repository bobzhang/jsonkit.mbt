// Port of upstream's referencing/tests/test_retrieval.py.

///|
test "it caches retrieved resources" {
  let contents : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let stack = [contents.stringify()]
  let retrieve = @referencing.to_cached_resource(_ => stack.pop().unwrap())
  let registry = @referencing.Registry::new(retrieve~)
  let expected = @referencing.Resource::from_contents(contents)
  let got = registry.get_or_retrieve("urn:example:schema")
  assert_true(got.value == expected)
  // And a second time we get the same value.
  let again = registry.get_or_retrieve("urn:example:schema")
  assert_true(physical_equal(again.value, got.value))
}

///|
test "custom loader" {
  let contents : Json = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
  }
  let stack = [contents.stringify().rev()]
  let retrieve = @referencing.to_cached_resource(_ => stack.pop().unwrap(), loads=s => {
    @json.parse(s.rev())
  })
  let registry = @referencing.Registry::new(retrieve~)
  let expected = @referencing.Resource::from_contents(contents)
  let got = registry.get_or_retrieve("urn:example:schema")
  assert_true(got.value == expected)
  let again = registry.get_or_retrieve("urn:example:schema")
  assert_true(physical_equal(again.value, got.value))
}

///|
test "custom from_contents" {
  let contents = Json::empty_object()
  let stack = [contents.stringify()]
  let retrieve = @referencing.to_cached_resource(_ => stack.pop().unwrap(), from_contents=c => {
    @referencing.draft202012().create_resource(c)
  })
  let registry = @referencing.Registry::new(retrieve~)
  let expected = @referencing.draft202012().create_resource(contents)
  let got = registry.get_or_retrieve("urn:example:schema")
  assert_true(got.value == expected)
  let again = registry.get_or_retrieve("urn:example:schema")
  assert_true(physical_equal(again.value, got.value))
}

///|
test "custom cache" {
  let schema = "\"$schema\": \"https://json-schema.org/draft/2020-12/schema\""
  let mapping : Map[String, String] = {
    "urn:example:1": "{\{schema}, \"foo\": 1}",
    "urn:example:2": "{\{schema}, \"foo\": 2}",
    "urn:example:3": "{\{schema}, \"foo\": 3}",
  }
  let resources : Map[String, @referencing.Resource] = Map([])
  for uri, text in mapping {
    resources[uri] = @referencing.Resource::from_contents(@json.parse(text))
  }
  let retrieve = @referencing.to_cached_resource(
    uri => {
      guard mapping.get(uri) is Some(text) else { fail("no \{uri}") }
      mapping.remove(uri)
      text
    },
    cache=@referencing.lru_cache(maxsize=2),
  )
  let registry = @referencing.Registry::new(retrieve~)
  for uri in ["urn:example:1", "urn:example:2", "urn:example:3"] {
    let got = registry.get_or_retrieve(uri)
    assert_true(got.value == resources[uri])
    assert_true(physical_equal(registry.get_or_retrieve(uri).value, got.value))
    assert_true(physical_equal(registry.get_or_retrieve(uri).value, got.value))
  }
  // And now this fails (as we popped the value out of `mapping`)
  try registry.get_or_retrieve("urn:example:1") catch {
    @referencing.Unretrievable(..) => ()
    _ => fail("expected Unretrievable")
  } noraise {
    _ => fail("expected Unretrievable")
  }
}
