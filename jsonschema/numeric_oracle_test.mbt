///|
/// Differential test of Python-numeric edge cases (huge ints, NaN,
/// infinities) against upstream's outcomes.
test "numeric edge cases agree with upstream" {
  let failures = []
  for line in numeric_oracle_json.split("\n") {
    if line.is_empty() {
      continue
    }
    guard @jsonschema.loads(line.to_owned())
      is [String(schema_text), String(instance_text), String(expected)] else {
      fail("bad case")
    }
    let schema = @jsonschema.loads(schema_text)
    let instance = @jsonschema.loads(instance_text)
    let validator = @jsonschema.draft202012_validator.new(schema)
    let got = try {
      let errors = validator.iter_errors(instance).to_array()
      if errors.is_empty() {
        "valid"
      } else {
        let cps = errors[0].message
        "invalid: " +
        (if cps.length() > 60 {
          cps.unsafe_substring(start=0, end=60)
        } else {
          cps
        })
      }
    } catch {
      @jsonschema.PythonError(m) =>
        "error: " +
        (match m.find(":") {
          Some(i) => m.unsafe_substring(start=0, end=i)
          None => m
        })
      e => "error: \{e}"
    }
    if got != expected {
      failures.push(
        "\{schema_text} / \{instance_text}: got \{got}, upstream \{expected}",
      )
    }
  }
  debug_inspect(failures, content="[]")
}
