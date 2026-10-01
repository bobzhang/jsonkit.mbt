///|
test "differential: random patterns against CPython" {
  let failures = []
  let mut on_core = 0
  let mut total = 0
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
    total += 1
    if p.engine() == "core" {
      on_core += 1
    }
    // the backtracking matcher is also checked on every pattern
    let (node, _, groups) = parse(pattern) catch { _ => panic() }
    let root = lower_node(node)
    for r in results {
      let got = p.search(r.0)
      if got != r.1 {
        failures.push("\{p.engine()} \{pattern.escape()} on \{r.0.escape()}: got \{got}")
      }
      let bt = backtrack_search(root, groups, @unicodedata.code_points(r.0)) is Some(_)
      if bt != r.1 {
        failures.push("backtrack \{pattern.escape()} on \{r.0.escape()}: got \{bt}")
      }
    }
  }
  println("regex fuzz: \{on_core}/\{total} patterns on core")
  debug_inspect(failures.length(), content="0")
  debug_inspect(failures[:@cmp.minimum(failures.length(), 30)].to_owned(), content="[]")
}
