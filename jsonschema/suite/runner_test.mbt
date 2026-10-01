///|
fn validator_class_for(class_name : String) -> @jsonschema.ValidatorClass {
  match class_name {
    "TestDraft3" => @jsonschema.draft3_validator
    "TestDraft4" => @jsonschema.draft4_validator
    "TestDraft6" => @jsonschema.draft6_validator
    "TestDraft7" => @jsonschema.draft7_validator
    "TestDraft201909" | "TestDraft201909Format" =>
      @jsonschema.draft201909_validator
    _ => @jsonschema.draft202012_validator
  }
}

///|
let remote_registries : Map[String, @referencing.Registry] = Map([])

///|
/// Upstream's `Suite.version(name)._remotes`: the suite's remotes, served
/// at `http://localhost:1234/`, filtered like `remotes_in`.
fn remotes_for(version : String) -> @referencing.Registry raise {
  if remote_registries.get(version) is Some(r) {
    return r
  }
  let cls = match @jsonschema.registered_validators().get(version) {
    Some(c) => c
    None => fail("unknown version \{version}")
  }
  let uri = (cls.id_of)(cls.meta_schema).unwrap()
  let specification = @referencing.specification_with(uri)
  let contents = []
  for remote in suite_remotes {
    let (relative, text) = remote
    let schema = @jsonschema.loads(text)
    let stem = match relative.rev_find("/") {
      Some(i) => relative.unsafe_substring(start=i + 1, end=relative.length())
      None => relative
    }
    let has_schema = schema is Object({ "$schema": _, .. })
    if ((version == "draft3" || version == "draft4") && stem == "tree.json") ||
      (
        !has_schema &&
        relative.has_prefix("draft") &&
        !relative.has_prefix(version)
      ) {
      continue
    }
    contents.push(("http://localhost:1234/\{relative}", schema))
  }
  let registry = @referencing.Registry::new().with_contents(
    contents,
    default_specification=specification,
  )
  remote_registries[version] = registry
  registry
}

///|
/// Run one test like upstream's `_Test.validate`, returning `'v'` (valid),
/// `'i'` (a `ValidationError` was raised) or `'e'` (some other error).
fn run_one(
  class_name : String,
  version : String,
  format_checker : Bool,
  test_ : SuiteTest,
) -> Char {
  let cls = validator_class_for(class_name)
  try {
    cls.check_schema(test_.schema)
    let validator = if format_checker {
      cls.new(
        test_.schema,
        registry=remotes_for(version),
        format_checker=cls.format_checker,
      )
    } else {
      cls.new(test_.schema, registry=remotes_for(version))
    }
    validator.validate(test_.data)
    'v'
  } catch {
    @jsonschema.ValidationError(_) => 'i'
    _ => 'e'
  }
}

///|
/// Run a suite file the way upstream's test class does; returns a summary
/// listing counts and every test where the port differs from upstream.
fn run_suite_file(
  class_name : String,
  version : String,
  path : String,
  format_checker~ : Bool,
  upstream~ : String,
  text : String,
) -> String {
  let cases = @jsonschema.loads(text) catch {
    e => return "cannot parse \{path}: \{e}"
  }
  guard cases is Array(cases) else { return "not a list of cases" }
  let file = match path.rev_find("/") {
    Some(i) => path.unsafe_substring(start=i + 1, end=path.length())
    None => path
  }
  let subject = file.unsafe_substring(start=0, end=file.length() - 5)
  let skip = skip_for(class_name)
  let mut index = 0
  let mut passed = 0
  let mut xfailed = 0
  let mut skipped = 0
  let notes = []
  for case in cases {
    guard case
      is Object(
        {
          "description": String(case_description),
          "schema": schema,
          "tests": Array(tests),
          ..
        }
      ) else {
      return "malformed case"
    }
    for t in tests {
      guard t
        is Object(
          {
            "description": String(description),
            "data": data,
            "valid": valid,
            ..
          }
        ) else {
        return "malformed test"
      }
      let test_ = {
        subject,
        case_description,
        description,
        schema,
        data,
        valid: valid is True,
      }
      let up = upstream.get_char(index)
      index += 1
      let upstream_skipped = up is Some('A'..='Z')
      let reason = skip(test_)
      if (reason is Some(_)) != upstream_skipped {
        notes.push("skip mismatch: \{case_description} / \{description}")
      }
      if reason is Some(_) {
        skipped += 1
        continue
      }
      let ours = run_one(class_name, version, format_checker, test_)
      let expected = if test_.valid { 'v' } else { 'i' }
      let python = match up {
        Some(c) => c.to_ascii_lowercase()
        None => expected
      }
      if ours == expected {
        passed += 1
        if python != expected {
          notes.push(
            "fixed (upstream fails): \{case_description} / \{description}",
          )
        }
      } else if ours == python {
        xfailed += 1
      } else {
        notes.push(
          "FAIL: \{case_description} / \{description}: got \{ours}, upstream \{python}",
        )
      }
    }
  }
  let summary = "passed \{passed}, upstream-xfail \{xfailed}, skipped \{skipped}"
  if notes.is_empty() {
    summary
  } else {
    summary + "\n" + notes.join("\n")
  }
}
