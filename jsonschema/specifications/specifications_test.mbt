///|
test "metaschemas" {
  let all = @specifications.schemas()
  inspect(all.length(), content="20")
  guard @specifications.contents("http://json-schema.org/draft-07/schema")
    is Some(Object({ "title": String(title), .. })) else {
    fail("missing draft 7")
  }
  inspect(title, content="Core schema meta-schema")
  guard @specifications.contents(
      "https://json-schema.org/draft/2020-12/meta/core",
    )
    is Some(Object({ "$dynamicAnchor": String(anchor), .. })) else {
    fail("missing 2020-12 core vocabulary")
  }
  inspect(anchor, content="meta")
  assert_true(@specifications.contents("urn:nope") is None)
}
