///|
/// A compiled Python regular expression (`re.Pattern`).
///
/// Patterns are parsed with a port of CPython's `re` parser (so the same
/// patterns are accepted / rejected as by `re.compile`) and then translated
/// to `moonbitlang/regexp` for matching. Matching follows `re.search`
/// semantics, including Python's `$` matching before a trailing newline,
/// Unicode-aware `\d`, `\w` and `\s`, and Python's `.` (anything but `\n`).
///
/// Known deviations: lookaround assertions, atomic groups, possessive
/// quantifiers and conditional groups are accepted by `compile` but raise
/// `UnsupportedPattern` when used for matching; case-insensitive matching of
/// character classes only folds ASCII letters; `\b` / `\B` use the engine's
/// notion of word characters.
pub struct Pattern {
  pattern : String
  priv compiled : Result[@regexp.Regexp, String]
}

///|
let cache : Map[String, Pattern] = Map([])

///|
/// `re.compile(pattern)`.
pub fn compile(pattern : String) -> Pattern raise PatternError {
  if cache.get(pattern) is Some(p) {
    return p
  }
  let (node, flags, _) = parse(pattern)
  let compiled = try {
    let translated = translate(node, flags)
    let flags = if flags.ignorecase { "i" } else { "" }
    Ok(@regexp.compile(translated, flags~))
  } catch {
    UnsupportedPattern(msg) => Err(msg)
    err => Err("engine error: \{err}")
  }
  let p = { pattern, compiled, }
  cache[pattern] = p
  p
}

///|
/// `re.search(pattern, s) is not None`.
pub fn Pattern::search(
  self : Pattern,
  s : StringView,
) -> Bool raise UnsupportedPattern {
  match self.compiled {
    Ok(re) => re.execute(s).matched()
    Err(msg) =>
      raise UnsupportedPattern(
        "cannot match \{self.pattern}: unsupported \{msg}",
      )
  }
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
  match self.compiled {
    Ok(re) => {
      let result = re.execute(s)
      if result.matched() {
        Some(result.results().map(g => g.map(v => v.to_owned())))
      } else {
        None
      }
    }
    Err(msg) =>
      raise UnsupportedPattern(
        "cannot match \{self.pattern}: unsupported \{msg}",
      )
  }
}
