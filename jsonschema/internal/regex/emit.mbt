///|
priv struct Emitter {
  sb : StringBuilder
  global_ignorecase : Bool
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
/// ASCII simple case folding of a set (the engine's character classes are
/// case-sensitive).
fn fold_set(set : Array[(Int, Int)]) -> Array[(Int, Int)] {
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
fn Emitter::emit_set(self : Emitter, set : Array[(Int, Int)]) -> Unit {
  // drop surrogate code points, which the engine cannot represent
  let ranges = []
  for r in set {
    let (lo, hi) = r
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
  if is_ascii_alnum(c) || (c > 0x7F && (c < 0xD800 || c > 0xDFFF)) {
    @unicodedata.write_code_point(self.sb, c)
  } else if c >= 0xD800 && c <= 0xDFFF {
    self.sb.write_string("[^\\u{0}-\\u{10ffff}]")
  } else {
    write_hex_escape(self.sb, c)
  }
}

///|
fn Emitter::with_case(
  self : Emitter,
  ignorecase : Bool,
  f : () -> Unit raise UnsupportedPattern,
) -> Unit raise UnsupportedPattern {
  if ignorecase == self.global_ignorecase {
    f()
  } else {
    self.sb.write_string(if ignorecase { "(?i:" } else { "(?-i:" })
    f()
    self.sb.write_char(')')
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
    Literal(c, ignorecase~) =>
      if ignorecase && is_ascii_letter(c) {
        self.emit_set(fold_set([(c, c)]))
      } else if ignorecase && c > 0x7F {
        self.with_case(true, () => self.emit_literal(c))
      } else {
        self.emit_literal(c)
      }
    Set(set, ignorecase~) =>
      self.emit_set(if ignorecase { fold_set(set) } else { set })
    At(kind) =>
      self.sb.write_string(
        match kind {
          BeginString => "^"
          BeginLine => "(?m:^)"
          EndDollar => "(?:\\u{a}?$)"
          EndLine => "(?m:$)"
          EndString => "$"
          Boundary => "\\b"
          NonBoundary => "\\B"
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
fn translate(n : Node, flags : Flags) -> String raise UnsupportedPattern {
  let e = { sb: StringBuilder(), global_ignorecase: flags.ignorecase, }
  e.emit(n)
  e.sb.to_string()
}
