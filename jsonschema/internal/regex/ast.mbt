///|
/// Raised for patterns Python's `re.compile` rejects (`re.error`).
pub suberror PatternError {
  PatternError(String)
} derive(Debug)

///|
/// Python regex flags (subset relevant to `str` patterns).
priv struct Flags {
  ignorecase : Bool
  multiline : Bool
  dotall : Bool
  verbose : Bool
  ascii : Bool
}

///|
priv enum Node {
  Literal(Int, case_~ : CaseMode)
  /// sorted, merged inclusive code point ranges
  Set(Array[(Int, Int)], negate~ : Bool, case_~ : CaseMode)
  /// `^`, `$`, `\A`, `\Z`, `\b`, `\B`
  At(AtKind)
  Seq(Array[Node])
  Alt(Array[Node])
  Group(Int?, Node) // capture index (1-based) or non-capturing
  Repeat(Node, min~ : Int, max~ : Int?, lazy_~ : Bool, possessive~ : Bool)
  Backref(Int, case_~ : CaseMode)
  Look(Node, ahead~ : Bool, negate~ : Bool, width~ : Int)
  Atomic(Node)
  Conditional(Int, Node, Node?)
}

///|
/// How a literal / character class matches case: as written, with `re`'s
/// Unicode case-insensitive equivalences, or (`(?ai)`) ASCII-only.
priv enum CaseMode {
  Sensitive
  UnicodeFold
  AsciiFold
}

///|
priv enum AtKind {
  BeginString // ^ (non-multiline) and \A
  BeginLine // ^ (multiline)
  EndDollar // $ (non-multiline): end or before a final newline
  EndLine // $ (multiline)
  EndString // \Z
  Boundary(ascii~ : Bool)
  NonBoundary(ascii~ : Bool)
}

///|
fn normalize_set(ranges : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let sorted = ranges.copy()
  sorted.sort_by((a, b) => a.0.compare(b.0))
  let out : Array[(Int, Int)] = []
  for r in sorted {
    match out.last() {
      Some((s, e)) if r.0 <= e + 1 =>
        out[out.length() - 1] = (s, @cmp.maximum(e, r.1))
      _ => out.push(r)
    }
  }
  out
}

///|
fn complement_set(set : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let out = []
  let mut next = 0
  for r in set {
    if r.0 > next {
      out.push((next, r.0 - 1))
    }
    next = r.1 + 1
  }
  if next <= 0x10FFFF {
    out.push((next, 0x10FFFF))
  }
  out
}
