///|
fn format_checker_for(version : String) -> @jsonschema.FormatChecker {
  match version {
    "draft3" => @jsonschema.draft3_format_checker
    "draft4" => @jsonschema.draft4_format_checker
    "draft6" => @jsonschema.draft6_format_checker
    "draft7" => @jsonschema.draft7_format_checker
    "draft2019-09" => @jsonschema.draft201909_format_checker
    _ => @jsonschema.draft202012_format_checker
  }
}

///|
fn validator_version_for(class_name : String) -> String {
  match class_name {
    "TestDraft3" => "draft3"
    "TestDraft4" => "draft4"
    "TestDraft6" => "draft6"
    "TestDraft7" => "draft7"
    "TestDraft201909" | "TestDraft201909Format" => "draft2019-09"
    _ => "draft2020-12"
  }
}

///|
/// Run one test, returning `'v'` (valid), `'i'` (invalid) or `'e'` (some
/// other error).
fn run_one(
  class_name : String,
  _format_checker : Bool,
  test_ : SuiteTest,
) -> Char {
  // Phase 1: only `optional/format` groups exist; their schemas consist of
  // `format` (and `$schema`), so validating amounts to checking the format.
  guard test_.schema is Object({ "format": String(format), .. }) else {
    return 'v'
  }
  let checker = format_checker_for(validator_version_for(class_name))
  let ok = checker.conforms(test_.data, format) catch { _ => return 'e' }
  if ok {
    'v'
  } else {
    'i'
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
  let _ = version
  let cases = @jsonschema.loads(text) catch {
    e => return "cannot parse \{path}: \{e}"
  }
  guard cases is Array(cases)
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
        { "description": String(case_description), "schema": schema, "tests": Array(tests), .. }
      )
    for t in tests {
      guard t
        is Object(
          { "description": String(description), "data": data, "valid": valid, .. }
        )
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
        notes.push(
          "skip mismatch: \{case_description} / \{description}",
        )
      }
      if reason is Some(_) {
        skipped += 1
        continue
      }
      let ours = run_one(class_name, format_checker, test_)
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
