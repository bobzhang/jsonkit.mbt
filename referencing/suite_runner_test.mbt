// Runner for the generated referencing-suite tests (suite_*_test.mbt),
// mirroring upstream's referencing/tests/test_referencing_suite.py.

///|
/// Check one test (and its chain of `then`s), returning a failure message.
fn check_suite_test(
  registry : @referencing.Registry,
  test_ : Map[String, Json],
) -> String? {
  let base_uri = match test_.get("base_uri") {
    Some(String(s)) => s
    _ => ""
  }
  guard test_.get("ref") is Some(String(reference)) else {
    return Some("malformed test")
  }
  let resolver = registry.resolver(base_uri~)
  if test_.get("error") is Some(True) {
    return resolver.lookup(reference) catch {
      error =>
        if @referencing.is_unresolvable(error) {
          None
        } else {
          Some("\{reference}: expected Unresolvable, got \{error}")
        }
    } noraise {
      resolved =>
        Some(
          "\{reference}: expected Unresolvable, got \{resolved.contents.stringify()}",
        )
    }
  }
  let mut resolved = resolver.lookup(reference) catch {
    error => return Some("\{reference}: unexpected error \{error}")
  }
  if test_.get("target") != Some(resolved.contents) {
    return Some(
      "\{reference}: got \{resolved.contents.stringify()}, expected \{test_.get("target").map(t => t.stringify())}",
    )
  }
  let mut then = test_.get("then")
  while then is Some(Object(step)) {
    guard step.get("ref") is Some(String(reference)) else {
      return Some("malformed then")
    }
    resolved = resolved.resolver.lookup(reference) catch {
      error => return Some("then \{reference}: unexpected error \{error}")
    }
    if step.get("target") != Some(resolved.contents) {
      return Some(
        "then \{reference}: got \{resolved.contents.stringify()}, expected \{step.get("target").map(t => t.stringify())}",
      )
    }
    then = step.get("then")
  }
  None
}

///|
/// Run every test of one suite file. Files upstream marks as expected
/// failures (`xfail`, the RFC 3986 normalization ones) must not pass
/// entirely, mirroring a strict xfail.
fn run_suite_file(
  name : String,
  dialect_id : String,
  xfail~ : Bool,
  text : String,
) -> Unit raise {
  let specification = @referencing.specification_with(dialect_id)
  guard @json.parse(text) is Object(loaded) else { fail("malformed suite file") }
  guard loaded.get("registry") is Some(Object(resources)) else {
    fail("malformed suite registry")
  }
  let registry = @referencing.Registry::new().with_resources(
    resources
    .iter()
    .map(pair => (pair.0, specification.create_resource(pair.1)))
    .to_array(),
  )
  guard loaded.get("tests") is Some(Array(tests)) else {
    fail("malformed suite tests")
  }
  let failures = []
  for i, test_ in tests {
    guard test_ is Object(test_) else { fail("malformed suite test") }
    if check_suite_test(registry, test_) is Some(message) {
      failures.push("\{name} #\{i}: \{message}")
    }
  }
  if xfail {
    if failures.is_empty() {
      fail("\{name}: expected (xfail) failures, but everything passed")
    }
  } else if !failures.is_empty() {
    fail(failures.join("\n"))
  }
}
