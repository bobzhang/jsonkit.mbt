///|
/// How the end-of-string assertions are translated (see `Pattern`).
priv enum EndMode {
  /// The subject does not end with a newline: `$` is the end of the text.
  Plain
  /// Every newline of the subject but a final one is replaced by the
  /// sentinel U+10FFFF (and every pattern element matching a newline also
  /// matches the sentinel), so that the engine's multi-line `$` -- "at the
  /// end or before a newline" -- is exactly Python's `$`: "at the end or
  /// before a final newline".
  Newlines
  /// Fallback when the subject itself contains the sentinel, or the pattern
  /// mixes `$` with multi-line anchors: `$` consumes an optional final
  /// newline.
  Consuming
} derive(Eq)

///|
const SENTINEL : Int = 0x10FFFF

///|
priv struct Emitter {
  sb : StringBuilder
  mode : EndMode
}

///|
fn write_hex_escape(sb : StringBuilder, c : Int) -> Unit {
  sb.write_string("\\u{")
  sb.write_string(c.to_string(radix=16))
  sb.write_char('}')
}

///|
fn is_ascii_alnum(c : Int) -> Bool {
  is_ascii_letter(c) || is_digit(c)
}

///|
/// ASCII-only case folding of a set (`(?ai)`).
fn fold_set_ascii(set : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let extra = []
  for r in set {
    let (lo, hi) = r
    // a-z -> A-Z
    let a = @cmp.maximum(lo, 'a')
    let b = @cmp.minimum(hi, 'z')
    if a <= b {
      extra.push((a - 32, b - 32))
    }
    let a = @cmp.maximum(lo, 'A')
    let b = @cmp.minimum(hi, 'Z')
    if a <= b {
      extra.push((a + 32, b + 32))
    }
  }
  normalize_set(set + extra)
}

///|
/// The code points a (possibly negated, possibly case-insensitive) class
/// matches: like CPython, the positive set is case-folded first and only
/// then complemented.
fn class_members(
  set : Array[(Int, Int)],
  negate : Bool,
  case_ : CaseMode,
) -> Array[(Int, Int)] {
  let folded = match case_ {
    Sensitive => set
    UnicodeFold => normalize_set(set + @unicodedata.case_fold_extras(set))
    AsciiFold => fold_set_ascii(set)
  }
  if negate {
    complement_set(folded)
  } else {
    folded
  }
}

///|
fn Emitter::emit_set(self : Emitter, set : Array[(Int, Int)]) -> Unit {
  let set = if self.mode == Newlines &&
    set.iter().any(r => r.0 <= 10 && 10 <= r.1) {
    set + [(SENTINEL, SENTINEL)]
  } else {
    set
  }
  // drop surrogate code points, which the engine cannot represent (and the
  // sentinel, when in use)
  let ranges = []
  for r in set {
    let (lo, hi) = r
    let hi = if self.mode == Newlines &&
      hi == SENTINEL &&
      !set.contains((SENTINEL, SENTINEL)) {
      hi - 1
    } else {
      hi
    }
    if hi < lo {
      continue
    }
    if hi < 0xD800 || lo > 0xDFFF {
      ranges.push(r)
    } else {
      if lo < 0xD800 {
        ranges.push((lo, 0xD7FF))
      }
      if hi > 0xDFFF {
        ranges.push((0xE000, hi))
      }
    }
  }
  if ranges.length() == 0 {
    // matches nothing
    self.sb.write_string("[^\\u{0}-\\u{10ffff}]")
    return
  }
  self.sb.write_char('[')
  for r in ranges {
    write_hex_escape(self.sb, r.0)
    if r.1 != r.0 {
      self.sb.write_char('-')
      write_hex_escape(self.sb, r.1)
    }
  }
  self.sb.write_char(']')
}

///|
fn Emitter::emit_literal(self : Emitter, c : Int) -> Unit {
  if self.mode == Newlines && c == SENTINEL {
    self.sb.write_string("[^\\u{0}-\\u{10ffff}]")
  } else if is_ascii_alnum(c) || (c > 0x7F && (c < 0xD800 || c > 0xDFFF)) {
    @unicodedata.write_code_point(self.sb, c)
  } else if c >= 0xD800 && c <= 0xDFFF {
    self.sb.write_string("[^\\u{0}-\\u{10ffff}]")
  } else {
    write_hex_escape(self.sb, c)
  }
}

///|
fn needs_wrapping(n : Node) -> Bool {
  match n {
    Literal(_) | Set(_) | Group(_) | Backref(_) => false
    Seq(items) => items.length() != 1
    _ => true
  }
}

///|
fn Emitter::emit(self : Emitter, n : Node) -> Unit raise UnsupportedPattern {
  match n {
    Literal(c, case_~) => {
      let members = class_members([(c, c)], false, case_)
      if self.mode == Newlines && c == '\n' {
        self.emit_set(members)
      } else if members.length() == 1 && members[0] == (c, c) {
        self.emit_literal(c)
      } else {
        self.emit_set(members)
      }
    }
    Set(set, negate~, case_~) =>
      self.emit_set(class_members(set, negate, case_))
    At(kind) =>
      self.sb.write_string(
        match kind {
          BeginString => "^"
          BeginLine => "(?m:^)"
          EndDollar =>
            match self.mode {
              Plain => "$"
              Newlines => "(?m:$)"
              Consuming => "(?:\\u{a}?$)"
            }
          EndLine => "(?m:$)"
          EndString => "$"
          // word boundaries are matched by the backtracking matcher
          Boundary(_) | NonBoundary(_) => raise UnsupportedPattern("\\b")
        },
      )
    Seq(items) =>
      for it in items {
        if it is Alt(_) {
          self.sb.write_string("(?:")
          self.emit(it)
          self.sb.write_char(')')
        } else {
          self.emit(it)
        }
      }
    Alt(items) =>
      for i, it in items {
        if i > 0 {
          self.sb.write_char('|')
        }
        self.emit(it)
      }
    Group(Some(_), p) => {
      self.sb.write_char('(')
      self.emit(p)
      self.sb.write_char(')')
    }
    Group(None, p) => {
      self.sb.write_string("(?:")
      self.emit(p)
      self.sb.write_char(')')
    }
    Repeat(p, min~, max~, lazy_~, possessive~) => {
      if possessive {
        raise UnsupportedPattern("possessive quantifiers")
      }
      if needs_wrapping(p) {
        self.sb.write_string("(?:")
        self.emit(p)
        self.sb.write_char(')')
      } else {
        self.emit(p)
      }
      match (min, max) {
        (0, None) => self.sb.write_char('*')
        (1, None) => self.sb.write_char('+')
        (0, Some(1)) => self.sb.write_char('?')
        (m, None) => self.sb.write_string("{\{m},}")
        (m, Some(x)) if m == x => self.sb.write_string("{\{m}}")
        (m, Some(x)) => self.sb.write_string("{\{m},\{x}}")
      }
      if lazy_ {
        self.sb.write_char('?')
      }
    }
    Backref(g, ..) => self.sb.write_string("(?:\\\{g})")
    Look(_, ..) => raise UnsupportedPattern("lookaround assertions")
    Atomic(_) => raise UnsupportedPattern("atomic groups")
    Conditional(_, _, _) => raise UnsupportedPattern("conditional groups")
  }
}

///|
/// Translate a parsed Python pattern into `moonbitlang/regexp` syntax.
fn translate(n : Node, mode : EndMode) -> String raise UnsupportedPattern {
  let e = { sb: StringBuilder(), mode }
  e.emit(n)
  e.sb.to_string()
}
