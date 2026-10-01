// Translation of parsed patterns to the syntax of MoonBit core's
// `@string.Regex` (lexmatch regexes) for the patterns it can run exactly.

///|
/// The largest repetition count `@string.Regex` accepts.
const MAX_CORE_REPEAT : Int = 256

///|
priv struct Emitter {
  sb : StringBuilder
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
  // drop surrogate code points: the engine matches supplementary characters
  // as surrogate pairs, so classes must not match lone surrogates
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
  if is_ascii_alnum(c) {
    self.sb.write_char(Int::unsafe_to_char(c))
  } else if c >= 0xD800 && c <= 0xDFFF {
    self.sb.write_string("[^\\u{0}-\\u{10ffff}]")
  } else {
    write_hex_escape(self.sb, c)
  }
}

///|
fn needs_wrapping(n : Node) -> Bool {
  match n {
    Literal(_) | Set(_) | Group(_) => false
    Seq(items) => items.length() != 1
    _ => true
  }
}

///|
/// Whether `@string.Regex` runs the pattern exactly like CPython: no
/// multi-line anchors, Unicode word boundaries, lookaround, atomic or
/// possessive constructs, conditionals or backreferences; repetition counts
/// within the engine's limit; `$` only where nothing can follow it (see
/// `Pattern::search`), and never together with `\Z`.
fn core_eligible(n : Node) -> Bool {
  fn ok(n : Node, tail : Bool) -> Bool {
    match n {
      Literal(_) | Set(_) => true
      At(BeginString | EndString) => true
      At(EndDollar) => tail
      At(_) => false
      Seq(items) => {
        // an item is in tail position when only `$`s follow it
        let mut tail_from = items.length()
        while tail_from > 0 && items[tail_from - 1] is At(EndDollar) {
          tail_from -= 1
        }
        for i, item in items {
          let item_tail = tail && i >= tail_from - 1
          if !ok(item, item_tail) {
            return false
          }
        }
        true
      }
      Alt(items) => items.iter().all(item => ok(item, tail))
      Group(_, p) => ok(p, tail)
      Repeat(p, min~, max~, possessive~, ..) =>
        !possessive &&
        min <= MAX_CORE_REPEAT &&
        (match max {
          Some(m) => m <= MAX_CORE_REPEAT
          None => true
        }) &&
        ok(p, tail && max is Some(0 | 1))
      Backref(_) | Look(_, ..) | Atomic(_) | Conditional(_, _, _) => false
    }
  }

  ok(n, true) && !(has_end_assertion(n) && has_end_string(n))
}

///|
fn Emitter::emit(self : Emitter, n : Node) -> Unit {
  match n {
    Literal(c, case_~) => {
      let members = class_members([(c, c)], false, case_)
      if members.length() == 1 && members[0] == (c, c) {
        self.emit_literal(c)
      } else {
        self.emit_set(members)
      }
    }
    Set(set, negate~, case_~) =>
      self.emit_set(class_members(set, negate, case_))
    At(BeginString) => self.sb.write_char('^')
    At(_) => self.sb.write_char('$')
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
    Repeat(p, min~, max~, lazy_~, ..) => {
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
    // excluded by `core_eligible`
    Backref(_) | Look(_, ..) | Atomic(_) | Conditional(_, _, _) => ()
  }
}

///|
/// Translate a `core_eligible` pattern into `@string.Regex` syntax.
fn translate(n : Node) -> String {
  let e = { sb: StringBuilder() }
  e.emit(n)
  e.sb.to_string()
}
