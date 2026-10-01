///|
test "differential: random patterns against CPython" {
  let failures = []
  for line in regex_fuzz_json.split("\n") {
    if line.is_empty() {
      continue
    }
    guard (try! @json.parse(line)) is [String(pattern), Array(rows)] else {
      fail("bad case")
    }
    let results = rows.map(row => match row {
      [String(s), True] => (s, true)
      [String(s), _] => (s, false)
      _ => ("", false)
    })
    let p = compile(pattern) catch {
      e => {
        failures.push("should be valid: \{pattern} (\{e is PatternError(_)})")
        continue
      }
    }
    for r in results {
      let got = p.search(r.0) catch { _ => !r.1 }
      if got != r.1 {
        failures.push("\{pattern.escape()} on \{r.0.escape()}: got \{got}")
      }
    }
  }
  debug_inspect(failures.length(), content="0")
  debug_inspect(failures[:@cmp.minimum(failures.length(), 30)].to_owned(), content="[]")
}
