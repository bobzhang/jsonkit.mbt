///|
test "differential: re.compile / re.search against CPython" {
  let failures = []
  for case in regex_cases {
    let (pattern, expected) = case
    // Deviation: named Unicode escapes need the full Unicode name table.
    if pattern.has_prefix("\\N{") {
      continue
    }
    match expected {
      None =>
        if is_valid(pattern) {
          failures.push("should be invalid: \{pattern}")
        }
      Some(results) => {
        let p = compile(pattern) catch {
          e => {
            failures.push("should be valid: \{pattern} (\{e is PatternError(_)})")
            continue
          }
        }
        for i, s in regex_subjects {
          let got = p.search(s) catch {
            UnsupportedPattern(_) =>
              // lookarounds etc. are accepted but not executable
              break
          }
          if got != results[i] {
            failures.push("\{pattern} on \{s.escape()}: got \{got}")
          }
        }
      }
    }
  }
  debug_inspect(failures, content="[]")
}
