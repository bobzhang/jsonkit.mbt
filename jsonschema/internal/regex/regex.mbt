///|
/// A compiled Python regular expression (`re.Pattern`).
///
/// Patterns are parsed with a port of CPython's `re` parser (so the same
/// patterns are accepted / rejected as by `re.compile`) and matched with
/// `re.search` semantics. Patterns that MoonBit core's `@string.Regex` can
/// run exactly are translated to its syntax (classes, `\d`, `\w`, `\s`, `.`
/// and case-insensitive matching become explicit code point sets following
/// CPython's case equivalences; `$` is only allowed where nothing can follow
/// it); everything else -- multi-line anchors, Unicode word boundaries,
/// lookaround, atomic groups, possessive quantifiers, conditional groups,
/// backreferences, repetition counts above 256 -- runs on a backtracking
/// matcher following CPython's `sre`. See `Pattern::engine`.
pub struct Pattern {
  pattern : String
  priv node : Node
  priv has_dollar : Bool
  /// `@string.Regex` program, for `core_eligible` patterns
  priv core : @string.Regex?
  /// set for patterns run by the backtracking matcher
  priv backtrack : BNode?
  priv groups : Int
}

///|
/// CPython's `re._MAXCACHE`.
const MAX_CACHE : Int = 512

///|
let cache : Map[String, Pattern] = Map([])

///|
fn any_node(n : Node, pred : (Node) -> Bool) -> Bool {
  if pred(n) {
    return true
  }
  match n {
    Literal(_) | Set(_) | At(_) | Backref(_) => false
    Seq(items) | Alt(items) => items.iter().any(i => any_node(i, pred))
    Group(_, p) | Repeat(p, ..) | Look(p, ..) | Atomic(p) => any_node(p, pred)
    Conditional(_, yes, no) =>
      any_node(yes, pred) ||
      (match no {
        Some(n) => any_node(n, pred)
        None => false
      })
  }
}

///|
fn has_end_assertion(n : Node) -> Bool {
  any_node(n, x => x is At(EndDollar))
}

///|
fn has_end_string(n : Node) -> Bool {
  any_node(n, x => x is At(EndString))
}

///|
/// `re.compile(pattern)`, with a bounded cache like CPython's (the oldest
/// entry is evicted once it holds `MAX_CACHE` patterns).
pub fn compile(pattern : String) -> Pattern raise PatternError {
  if cache.get(pattern) is Some(p) {
    return p
  }
  let (node, _, groups) = parse(pattern)
  let core = if core_eligible(node) {
    // an engine rejection would be a bug; fall back to the backtracker
    @string.Regex(translate(node)) catch {
      _ => None
    } noraise {
      re => Some(re)
    }
  } else {
    None
  }
  let p = {
    pattern,
    node,
    has_dollar: has_end_assertion(node),
    core,
    backtrack: if core is None { Some(lower_node(node)) } else { None },
    groups,
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
/// Which matcher runs the pattern: `"core"` (`@string.Regex`) or
/// `"backtrack"`.
pub fn Pattern::engine(self : Pattern) -> String {
  if self.core is Some(_) {
    "core"
  } else {
    "backtrack"
  }
}

///|
/// Run the core program like `re.search`. Python's `$` also matches before a
/// final newline; as `core_eligible` patterns only have `$` where nothing
/// can follow it, such matches are exactly the matches of the subject
/// without its final newline.
fn Pattern::core_search(
  self : Pattern,
  re : @string.Regex,
  s : StringView,
) -> (Int, Array[String?])? {
  let to_result = (m : @string.MatchResult) => (
    m.before().length(),
    Array::makei(self.groups + 1, i => m.group(i).map(v => v.to_owned())),
  )
  let first = re.execute(s).map(to_result)
  let n = s.length()
  if !self.has_dollar || n == 0 || s.code_unit_at(n - 1) != '\n' {
    return first
  }
  let second = re.execute(s[:n - 1]).map(to_result)
  match (first, second) {
    (Some(a), Some(b)) => if b.0 < a.0 { Some(b) } else { Some(a) }
    (None, b) => b
    (a, None) => a
  }
}

///|
/// `re.search(pattern, s) is not None`.
pub fn Pattern::search(
  self : Pattern,
  s : StringView,
) -> Bool {
  self.search_groups(s) is Some(_)
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
) -> Array[String?]? {
  match (self.core, self.backtrack) {
    (Some(re), _) => self.core_search(re, s).map(r => r.1)
    (None, Some(root)) => {
      let cps = @unicodedata.code_points(s)
      backtrack_search(root, self.groups, cps).map(spans => spans.map(span => if span.0 <
        0 ||
        span.1 < 0 {
        None
      } else {
        Some(@unicodedata.from_code_points(cps[span.0:span.1]))
      }))
    }
    (None, None) => None
  }
}
