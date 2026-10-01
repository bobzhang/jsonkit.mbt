///|
/// Differential test: format checks on mutated suite strings, against
/// CPython's results (`None`: the check raised an unexpected error).
test "format checks agree with upstream on mutated inputs" {
  let failures = []
  for case in format_fuzz_cases {
    let (draft, format, instance, expected) = case
    let checker = if draft == "draft3" {
      @jsonschema.draft3_format_checker
    } else {
      @jsonschema.draft202012_format_checker
    }
    let got = Some(checker.conforms(Json::string(instance), format)) catch {
      _ => None
    }
    if got != expected {
      failures.push(
        "\{draft} \{format} \{instance.escape()}: got \{got is Some(true)}",
      )
    }
  }
  debug_inspect(failures, content="[]")
}
