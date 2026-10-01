// Port of upstream's referencing/tests/test_exceptions.py.

///|
fn error_thunks() -> Array[@referencing.ReferencingError] {
  let true_ = opaque_resource(true)
  [
    CannotDetermineSpecification(contents=true_.contents),
    NoSuchResource(reference="urn:example:foo"),
    NoInternalID(resource=true_),
    InvalidAnchor(resource=true_, anchor="foo", reference="a#b"),
    NoSuchAnchor(resource=true_, anchor="foo", reference="a#b"),
    PointerToNowhere(resource=true_, reference="urn:example:foo"),
    Unresolvable(reference="urn:example:foo"),
    Unretrievable(reference="urn:example:foo", cause=None),
  ]
}

///|
test "eq incompatible types" {
  let errors = error_thunks()
  for i, one in errors {
    for j, two in errors {
      if i != j {
        assert_true(one != two, msg="\{one} == \{two}")
      }
    }
  }
}

///|
test "eq of equal errors" {
  for i, one in error_thunks() {
    assert_true(one == error_thunks()[i])
  }
}

///|
test "str of errors (as Python's str())" {
  let messages = error_thunks().map(e => e.to_string())
  debug_inspect(
    messages,
    content=(
      #|[
      #|  "True",
      #|  "'urn:example:foo'",
      #|  "Resource(contents=True, _specification=<Specification name='opaque'>)",
      #|  "'#foo' is not a valid anchor, neither as a plain name anchor nor as a JSON Pointer. You may have intended to use '#/foo', as the slash is required *before each segment* of a JSON pointer.",
      #|  "'foo' does not exist within True",
      #|  "'urn:example:foo' does not exist within True",
      #|  "urn:example:foo",
      #|  "'urn:example:foo'",
      #|]
    ),
  )
}

///|
test "is_unresolvable" {
  let flags = error_thunks().map(e => e.is_unresolvable())
  debug_inspect(
    flags,
    content="[false, false, false, true, true, true, true, false]",
  )
}
