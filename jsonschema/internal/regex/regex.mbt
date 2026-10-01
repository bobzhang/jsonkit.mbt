///|
/// A compiled Python regular expression (`re.Pattern`).
///
/// Patterns are parsed with a port of CPython's `re` parser (so the same
/// patterns are accepted / rejected as by `re.compile`). Matching follows
/// `re.search`: most patterns are translated to `moonbitlang/regexp`
/// (explicit code point classes for `\d`, `\w`, `\s`, `.`, and CPython's
/// case-insensitive equivalences, so no engine flags are involved; Python's
/// `$` -- end, or before a final newline -- is made exact by mapping the
/// subject's other newlines to a sentinel and using the engine's
/// multi-line `$`). Patterns with word boundaries, lookaround, atomic groups,
/// possessive quantifiers, conditional groups or backreferences run on a
/// backtracking matcher that follows CPython's `sre`.
pub struct Pattern {
  pattern : String
  priv node : Node
  priv has_end : Bool
  priv has_line_anchor : Bool
  /// set for patterns run by the backtracking matcher
  priv backtrack : BNode?
  priv groups : Int
  priv programs : Map[Int, Result[@regexp.Regexp, String]]
}

///|
/// CPython's `re._MAXCACHE`.
const MAX_CACHE : Int = 512

///|
let cache : Map[String, Pattern] = Map([])

///|
fn has_end_assertion(n : Node) -> Bool {
  match n {
    At(EndDollar) => true
    Literal(_) | Set(_) | At(_) | Backref(_) => false
    Seq(items) | Alt(items) => items.iter().any(has_end_assertion)
    Group(_, p) | Repeat(p, ..) | Look(p, ..) | Atomic(p) => has_end_assertion(p)
    Conditional(_, yes, no) =>
      has_end_assertion(yes) ||
      (match no {
        Some(n) => has_end_assertion(n)
        None => false
      })
  }
}

///|
/// `re.compile(pattern)`, with a bounded cache like CPython's (the oldest
/// entry is evicted once it holds `MAX_CACHE` patterns).
pub fn compile(pattern : String) -> Pattern raise PatternError {
  if cache.get(pattern) is Some(p) {
    return p
  }
  let (node, _, groups) = parse(pattern)
  let p = {
    pattern,
    node,
    has_end: has_end_assertion(node),
    has_line_anchor: has_line_anchor(node),
    backtrack: if needs_backtracking(node) { Some(lower_node(node)) } else { None },
    groups,
    programs: Map([]),
  }
  if cache.length() >= MAX_CACHE {
    match cache.keys().head() {
      Some(oldest) => cache.remove(oldest)
      None => ()
    }
  }
  cache[pattern] = p
  p
}

///|
fn has_line_anchor(n : Node) -> Bool {
  match n {
    At(BeginLine | EndLine) => true
    Literal(_) | Set(_) | At(_) | Backref(_) => false
    Seq(items) | Alt(items) => items.iter().any(has_line_anchor)
    Group(_, p) | Repeat(p, ..) | Look(p, ..) | Atomic(p) => has_line_anchor(p)
    Conditional(_, yes, no) =>
      has_line_anchor(yes) ||
      (match no {
        Some(n) => has_line_anchor(n)
        None => false
      })
  }
}

///|
fn mode_index(mode : EndMode) -> Int {
  match mode {
    Plain => 0
    Newlines => 1
    Consuming => 2
  }
}

///|
fn Pattern::program(
  self : Pattern,
  mode : EndMode,
) -> @regexp.Regexp raise UnsupportedPattern {
  let key = mode_index(mode)
  let compiled = match self.programs.get(key) {
    Some(c) => c
    None => {
      let c = try {
        Ok(@regexp.compile(translate(self.node, mode)))
      } catch {
        UnsupportedPattern(msg) => Err(msg)
        err => Err("engine error: \{err}")
      }
      self.programs[key] = c
      c
    }
  }
  match compiled {
    Ok(re) => re
    Err(msg) =>
      raise UnsupportedPattern(
        "cannot match \{self.pattern}: unsupported \{msg}",
      )
  }
}

///|
/// Pick the translation for a subject (see `EndMode`): Python's `$` matches
/// at the end and right before a final newline, the engine's only at the
/// end.
fn Pattern::prepare(
  self : Pattern,
  s : StringView,
) -> (@regexp.Regexp, StringView, Bool) raise UnsupportedPattern {
  if !self.has_end || !s.contains("\n") {
    return (self.program(Plain), s, false)
  }
  if self.has_line_anchor || s.contains("\u{10FFFF}") {
    return (self.program(Consuming), s, false)
  }
  let n = s.length()
  let final_newline = s.code_unit_at(n - 1) == '\n'
  let body = if final_newline { s[:n - 1] } else { s }
  let subject = body.to_owned().replace_all(old="\n", new="\u{10FFFF}") +
    (if final_newline { "\n" } else { "" })
  (self.program(Newlines), subject, true)
}

///|
/// `re.search(pattern, s) is not None`.
pub fn Pattern::search(
  self : Pattern,
  s : StringView,
) -> Bool raise UnsupportedPattern {
  if self.backtrack is Some(root) {
    return backtrack_search(root, self.groups, @unicodedata.code_points(s))
      is Some(_)
  }
  let (re, subject, _) = self.prepare(s)
  re.execute(subject).matched()
}

///|
/// `bool(re.search(pattern, s))`, raising `PatternError` for invalid
/// patterns like Python's `re.error`.
pub fn search(pattern : String, s : StringView) -> Bool raise {
  compile(pattern).search(s)
}

///|
/// Whether `re.compile(pattern)` succeeds.
pub fn is_valid(pattern : String) -> Bool {
  try {
    ignore(compile(pattern))
    true
  } catch {
    _ => false
  }
}

///|
/// `re.search(pattern, s)`: the match's groups (group 0 first), or `None`
/// when there is no match.
pub fn Pattern::search_groups(
  self : Pattern,
  s : StringView,
) -> Array[String?]? raise UnsupportedPattern {
  if self.backtrack is Some(root) {
    let cps = @unicodedata.code_points(s)
    return backtrack_search(root, self.groups, cps).map(spans => spans.map(span => if span.0 < 0 ||
      span.1 < 0 {
      None
    } else {
      Some(@unicodedata.from_code_points(cps[span.0:span.1]))
    }))
  }
  let (re, subject, sentinel) = self.prepare(s)
  let result = re.execute(subject)
  if result.matched() {
    Some(
      result
      .results()
      .map(g => g.map(v => if sentinel {
        v.to_owned().replace_all(old="\u{10FFFF}", new="\n")
      } else {
        v.to_owned()
      })),
    )
  } else {
    None
  }
}
