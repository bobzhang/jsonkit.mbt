///|
/// Recursive-descent port of CPython's `re._parser` for `str` patterns.
priv struct Parser {
  src : Array[Int]
  mut pos : Int
  mut flags : Flags
  /// number of groups opened so far + 1 (like `State.groups`)
  mut groups : Int
  group_names : Map[String, Int]
  open_groups : Array[Int]
  mut lookbehind_groups : Int?
  /// widths of closed groups, for lookbehind fixed-width checks
  group_widths : Map[Int, (Int, Int)]
}

///|
fn Parser::error(_self : Parser, msg : String) -> PatternError {
  PatternError(msg)
}

///|
fn Parser::case_mode(self : Parser) -> CaseMode {
  if !self.flags.ignorecase {
    Sensitive
  } else if self.flags.ascii {
    AsciiFold
  } else {
    UnicodeFold
  }
}

///|
fn Parser::next(self : Parser) -> Int? {
  if self.pos < self.src.length() {
    Some(self.src[self.pos])
  } else {
    None
  }
}

///|
fn Parser::get(self : Parser) -> Int? {
  if self.pos < self.src.length() {
    let c = self.src[self.pos]
    self.pos += 1
    Some(c)
  } else {
    None
  }
}

///|
fn Parser::matches(self : Parser, c : Int) -> Bool {
  if self.next() == Some(c) {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn is_ascii_letter(c : Int) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Int) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_octdigit(c : Int) -> Bool {
  c >= '0' && c <= '7'
}

///|
fn hex_value(c : Int) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c - '0')
  } else if c >= 'a' && c <= 'f' {
    Some(c - 'a' + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c - 'A' + 10)
  } else {
    None
  }
}

///|
fn cps_to_string(cps : ArrayView[Int]) -> String {
  @unicodedata.from_code_points(cps)
}

///|
/// Parse a Python regular expression.
fn parse(pattern : String) -> (Node, Flags, Int) raise PatternError {
  let p : Parser = {
    src: @unicodedata.code_points(pattern),
    pos: 0,
    flags: {
      ignorecase: false,
      multiline: false,
      dotall: false,
      verbose: false,
      ascii: false,
    },
    groups: 1,
    group_names: {},
    open_groups: [],
    lookbehind_groups: None,
    group_widths: {},
  }
  let node = p.parse_sub(true, 0)
  if p.next() is Some(_) {
    // only ")" can stop the top-level parse early
    raise p.error("unbalanced parenthesis")
  }
  (node, p.flags, p.groups - 1)
}

///|
fn Parser::parse_sub(
  self : Parser,
  first : Bool,
  nested : Int,
) -> Node raise PatternError {
  let items = [self.parse_seq(first, nested)]
  while self.matches('|') {
    items.push(self.parse_seq(false, nested))
  }
  if items.length() == 1 {
    items[0]
  } else {
    Alt(items)
  }
}

///|
fn is_repeat(n : Node) -> Bool {
  n is Repeat(_)
}

///|
fn Parser::parse_seq(
  self : Parser,
  first : Bool,
  nested : Int,
) -> Node raise PatternError {
  let items : Array[Node] = []
  for ;; {
    guard self.next() is Some(this) else { break }
    if this == '|' || this == ')' {
      break
    }
    self.pos += 1
    if self.flags.verbose {
      if this is (' ' | '\t' | '\n' | '\r' | 0x0B | 0x0C) {
        continue
      }
      if this == '#' {
        while self.get() is Some(c) {
          if c == '\n' {
            break
          }
        }
        continue
      }
    }
    match this {
      '\\' => items.push(self.escape())
      '[' => items.push(self.parse_class())
      '.' =>
        items.push(
          Set(
            if self.flags.dotall {
              [(0, 0x10FFFF)]
            } else {
              [(0, 9), (11, 0x10FFFF)]
            },
            negate=false,
            case_=Sensitive,
          ),
        )
      '^' =>
        items.push(
          At(if self.flags.multiline { BeginLine } else { BeginString }),
        )
      '$' =>
        items.push(At(if self.flags.multiline { EndLine } else { EndDollar }))
      '(' =>
        match self.parse_group(first && items.length() == 0, nested) {
          Some(n) => items.push(n)
          None => ()
        }
      '*' | '+' | '?' | '{' => {
        let here = self.pos
        let mut min = 0
        let mut max : Int? = None
        if this == '?' {
          max = Some(1)
        } else if this == '+' {
          min = 1
        } else if this == '{' {
          if self.next() == Some('}') {
            items.push(Literal(this, case_=self.case_mode()))
            continue
          }
          let lo = []
          let hi = []
          while self.next() is Some(c) && is_digit(c) {
            lo.push(c)
            self.pos += 1
          }
          let has_comma = self.matches(',')
          if has_comma {
            while self.next() is Some(c) && is_digit(c) {
              hi.push(c)
              self.pos += 1
            }
          }
          if !self.matches('}') {
            items.push(Literal(this, case_=self.case_mode()))
            self.pos = here
            continue
          }
          let to_int = (ds : Array[Int]) => {
            let mut v = 0L
            for d in ds {
              v = v * 10L + (d - '0').to_int64()
              if v >= 4294967295L {
                raise self.error("the repetition number is too large")
              }
            }
            v.to_int()
          }
          if lo.length() > 0 {
            min = to_int(lo)
          }
          if has_comma {
            if hi.length() > 0 {
              max = Some(to_int(hi))
            }
          } else if lo.length() > 0 {
            max = Some(min)
          }
          if max is Some(m) && m < min {
            raise self.error("min repeat greater than max repeat")
          }
        }
        guard items.last() is Some(item) && !(item is At(_)) else {
          raise self.error("nothing to repeat")
        }
        if is_repeat(item) {
          raise self.error("multiple repeat")
        }
        let lazy_ = self.matches('?')
        let possessive = !lazy_ && self.matches('+')
        items[items.length() - 1] = Repeat(
          item,
          min~,
          max~,
          lazy_~,
          possessive~,
        )
      }
      _ => items.push(Literal(this, case_=self.case_mode()))
    }
  }
  if items.length() == 1 {
    items[0]
  } else {
    Seq(items)
  }
}

///|
/// Category sets, honouring the ASCII flag.
fn category_set(c : Int, ascii : Bool) -> Array[(Int, Int)] {
  match c {
    'd' => if ascii { [('0', '9')] } else { @unicodedata.decimal_set() }
    'D' => complement_set(category_set('d', ascii))
    'w' =>
      if ascii {
        [('0', '9'), ('A', 'Z'), ('_', '_'), ('a', 'z')]
      } else {
        normalize_set(@unicodedata.alnum_set() + [('_', '_')])
      }
    'W' => complement_set(category_set('w', ascii))
    's' => if ascii { [(9, 13), (32, 32)] } else { @unicodedata.space_set() }
    'S' => complement_set(category_set('s', ascii))
    _ => []
  }
}

///|
fn Parser::hex_escape(
  self : Parser,
  count : Int,
  escape : Array[Int],
) -> Int raise PatternError {
  let mut v = 0
  for _ in 0..<count {
    match self.next() {
      Some(c) if hex_value(c) is Some(h) => {
        escape.push(c)
        self.pos += 1
        v = v * 16 + h
      }
      _ => raise self.error("incomplete escape \\" + cps_to_string(escape[1:]))
    }
  }
  v
}

///|
/// Escapes shared by `_escape` and `_class_escape`. Returns `None` when the
/// escape is not one of the literal-producing forms.
fn Parser::literal_escape(
  self : Parser,
  c : Int,
  in_class : Bool,
) -> Int? raise PatternError {
  let escape : Array[Int] = ['\\', c]
  match c {
    'a' => Some(7)
    'f' => Some(12)
    'n' => Some(10)
    'r' => Some(13)
    't' => Some(9)
    'v' => Some(11)
    '\\' => Some('\\')
    'x' => Some(self.hex_escape(2, escape))
    'u' => Some(self.hex_escape(4, escape))
    'U' => {
      let v = self.hex_escape(8, escape)
      if v > 0x10FFFF {
        raise self.error("bad escape \\" + cps_to_string(escape[1:]))
      }
      Some(v)
    }
    'N' =>
      raise self.error(
        "bad escape \\N (named Unicode escapes are not supported by this port)",
      )
    '0' if !in_class => {
      // octal escape: up to two more octal digits
      let mut v = 0
      for _ in 0..<2 {
        match self.next() {
          Some(d) if is_octdigit(d) => {
            v = v * 8 + (d - '0')
            self.pos += 1
          }
          _ => break
        }
      }
      Some(v)
    }
    _ =>
      if in_class && is_octdigit(c) {
        let mut v = c - '0'
        for _ in 0..<2 {
          match self.next() {
            Some(d) if is_octdigit(d) => {
              v = v * 8 + (d - '0')
              self.pos += 1
            }
            _ => break
          }
        }
        if v > 0o377 {
          raise self.error(
            "octal escape value \\" +
            v.to_string() +
            " outside of range 0-0o377",
          )
        }
        Some(v)
      } else if in_class && is_digit(c) {
        raise self.error("bad escape \\" + cps_to_string([c]))
      } else {
        None
      }
  }
}

///|
fn Parser::escape(self : Parser) -> Node raise PatternError {
  guard self.get() is Some(c) else {
    raise self.error("bad escape (end of pattern)")
  }
  let ic = self.case_mode()
  match c {
    'A' => return At(BeginString)
    'Z' => return At(EndString)
    'b' => return At(Boundary(ascii=self.flags.ascii))
    'B' => return At(NonBoundary(ascii=self.flags.ascii))
    'd' | 'D' | 's' | 'S' | 'w' | 'W' =>
      return Set(
        category_set(c, self.flags.ascii),
        negate=false,
        case_=Sensitive,
      )
    _ => ()
  }
  if self.literal_escape(c, false) is Some(v) {
    return Literal(v, case_=ic)
  }
  if is_digit(c) {
    // octal escape *or* decimal group reference
    let digits = [c]
    if self.next() is Some(d) && is_digit(d) {
      digits.push(d)
      self.pos += 1
      if is_octdigit(digits[0]) &&
        is_octdigit(digits[1]) &&
        self.next() is Some(e) &&
        is_octdigit(e) {
        self.pos += 1
        let v = (digits[0] - '0') * 64 + (digits[1] - '0') * 8 + (e - '0')
        if v > 0o377 {
          raise self.error("octal escape value outside of range 0-0o377")
        }
        return Literal(v, case_=ic)
      }
    }
    let mut group = 0
    for d in digits {
      group = group * 10 + (d - '0')
    }
    if group < self.groups {
      if self.open_groups.contains(group) {
        raise self.error("cannot refer to an open group")
      }
      self.check_lookbehind_group(group)
      return Backref(group, case_=ic)
    }
    raise self.error("invalid group reference " + group.to_string())
  }
  if is_ascii_letter(c) {
    raise self.error("bad escape \\" + cps_to_string([c]))
  }
  Literal(c, case_=ic)
}

///|
fn Parser::check_lookbehind_group(
  self : Parser,
  gid : Int,
) -> Unit raise PatternError {
  if self.lookbehind_groups is Some(lb) {
    if !self.group_widths.contains(gid) {
      raise self.error("cannot refer to an open group")
    }
    if gid >= lb {
      raise self.error(
        "cannot refer to group defined in the same lookbehind subpattern",
      )
    }
  }
}

///|
fn Parser::class_item(
  self : Parser,
  this : Int,
) -> Result[Int, Array[(Int, Int)]] raise PatternError {
  if this != '\\' {
    return Ok(this)
  }
  guard self.get() is Some(c) else {
    raise self.error("bad escape (end of pattern)")
  }
  match c {
    'b' => return Ok(8)
    'd' | 'D' | 's' | 'S' | 'w' | 'W' =>
      return Err(category_set(c, self.flags.ascii))
    _ => ()
  }
  if self.literal_escape(c, true) is Some(v) {
    return Ok(v)
  }
  if is_ascii_letter(c) {
    raise self.error("bad escape \\" + cps_to_string([c]))
  }
  Ok(c)
}

///|
fn Parser::parse_class(self : Parser) -> Node raise PatternError {
  let ranges : Array[(Int, Int)] = []
  let negate = self.matches('^')
  let mut nonempty = false
  for ;; {
    guard self.get() is Some(this) else {
      raise self.error("unterminated character set")
    }
    if this == ']' && nonempty {
      break
    }
    nonempty = true
    let code1 = self.class_item(this)
    if self.matches('-') {
      guard self.get() is Some(that) else {
        raise self.error("unterminated character set")
      }
      if that == ']' {
        match code1 {
          Ok(v) => ranges.push((v, v))
          Err(set) => ranges.append(set)
        }
        ranges.push(('-', '-'))
        break
      }
      let code2 = self.class_item(that)
      match (code1, code2) {
        (Ok(lo), Ok(hi)) => {
          if hi < lo {
            raise self.error("bad character range")
          }
          ranges.push((lo, hi))
        }
        _ => raise self.error("bad character range")
      }
    } else {
      match code1 {
        Ok(v) => ranges.push((v, v))
        Err(set) => ranges.append(set)
      }
    }
  }
  Set(normalize_set(ranges), negate~, case_=self.case_mode())
}

///|
fn is_identifier(name : Array[Int]) -> Bool {
  if name.length() == 0 {
    return false
  }
  for i, c in name {
    let ok = c == '_' ||
      @unicodedata.is_alpha(c) ||
      (i > 0 && @unicodedata.is_alnum(c))
    if !ok {
      return false
    }
  }
  true
}

///|
fn Parser::get_until(
  self : Parser,
  terminator : Int,
  what : String,
) -> Array[Int] raise PatternError {
  let name = []
  for ;; {
    match self.get() {
      None => raise self.error("missing " + what)
      Some(c) if c == terminator => break
      Some(c) => name.push(c)
    }
  }
  if name.length() == 0 {
    raise self.error("missing " + what)
  }
  name
}

///|
fn flag_of(c : Int) -> Bool {
  c is ('i' | 'L' | 'm' | 's' | 'x' | 'a' | 'u')
}

///|
fn Flags::with_flag(self : Flags, c : Int, on : Bool) -> Flags {
  match c {
    'i' => { ..self, ignorecase: on, }
    'm' => { ..self, multiline: on, }
    's' => { ..self, dotall: on, }
    'x' => { ..self, verbose: on, }
    'a' => { ..self, ascii: on, }
    _ => self
  }
}

///|
/// Parse `(...)` after the opening parenthesis. Returns `None` for constructs
/// that produce nothing (comments, global flags).
fn Parser::parse_group(
  self : Parser,
  at_start : Bool,
  nested : Int,
) -> Node? raise PatternError {
  let mut capture = true
  let mut is_atomic = false
  let mut name : String? = None
  let saved_flags = self.flags
  let mut scoped = false
  if self.matches('?') {
    guard self.get() is Some(char) else {
      raise self.error("unexpected end of pattern")
    }
    if char == 'P' {
      if self.matches('<') {
        let n = self.get_until('>', "group name")
        if !is_identifier(n) {
          raise self.error("bad character in group name")
        }
        name = Some(cps_to_string(n))
      } else if self.matches('=') {
        let n = self.get_until(')', "group name")
        if !is_identifier(n) {
          raise self.error("bad character in group name")
        }
        guard self.group_names.get(cps_to_string(n)) is Some(gid) else {
          raise self.error("unknown group name")
        }
        if self.open_groups.contains(gid) {
          raise self.error("cannot refer to an open group")
        }
        self.check_lookbehind_group(gid)
        return Some(Backref(gid, case_=self.case_mode()))
      } else {
        match self.get() {
          None => raise self.error("unexpected end of pattern")
          Some(c) =>
            raise self.error("unknown extension ?P" + cps_to_string([c]))
        }
      }
    } else if char == ':' {
      capture = false
    } else if char == '#' {
      for ;; {
        match self.get() {
          None => raise self.error("missing ), unterminated comment")
          Some(')') => break
          Some(_) => ()
        }
      }
      return None
    } else if char is ('=' | '!' | '<') {
      let mut kind = char
      let mut ahead = true
      if char == '<' {
        match self.get() {
          None => raise self.error("unexpected end of pattern")
          Some(c) if c is ('=' | '!') => kind = c
          Some(c) =>
            raise self.error("unknown extension ?<" + cps_to_string([c]))
        }
        ahead = false
      }
      let lookbehind_groups = self.lookbehind_groups
      if !ahead && lookbehind_groups is None {
        self.lookbehind_groups = Some(self.groups)
      }
      let p = self.parse_sub(false, nested + 1)
      if !ahead && lookbehind_groups is None {
        self.lookbehind_groups = None
      }
      if !self.matches(')') {
        raise self.error("missing ), unterminated subpattern")
      }
      let mut width = 0
      if !ahead {
        let (lo, hi) = self.width(p)
        if lo != hi {
          raise self.error("look-behind requires fixed-width pattern")
        }
        width = lo
      }
      return Some(Look(p, ahead~, negate=kind == '!', width~))
    } else if char == '(' {
      // conditional backreference group
      let cond = self.get_until(')', "group name")
      let gid = if cond.iter().all(is_digit) {
        let mut v = 0
        for d in cond {
          v = v * 10 + (d - '0')
        }
        if v == 0 {
          raise self.error("bad group number")
        }
        if v >= 100 {
          raise self.error("invalid group reference " + v.to_string())
        }
        v
      } else {
        if !is_identifier(cond) {
          raise self.error("bad character in group name")
        }
        match self.group_names.get(cps_to_string(cond)) {
          Some(g) => g
          None => raise self.error("unknown group name")
        }
      }
      let yes = self.parse_seq(false, nested + 1)
      let no = if self.matches('|') {
        let n = self.parse_seq(false, nested + 1)
        if self.next() == Some('|') {
          raise self.error("conditional backref with more than two branches")
        }
        Some(n)
      } else {
        None
      }
      if !self.matches(')') {
        raise self.error("missing ), unterminated subpattern")
      }
      if gid >= self.groups {
        raise self.error("invalid group reference " + gid.to_string())
      }
      return Some(Conditional(gid, yes, no))
    } else if char == '>' {
      capture = false
      is_atomic = true
    } else if flag_of(char) || char == '-' {
      // inline flags
      let add : Array[Int] = []
      let mut c = char
      if c != '-' {
        for ;; {
          if c == 'L' {
            raise self.error(
              "bad inline flags: cannot use 'L' flag with a str pattern",
            )
          }
          add.push(c)
          if add.contains('a') && add.contains('u') {
            raise self.error(
              "bad inline flags: flags 'a', 'u' and 'L' are incompatible",
            )
          }
          match self.get() {
            None => raise self.error("missing -, : or )")
            Some(n) => c = n
          }
          if c is (')' | '-' | ':') {
            break
          }
          if !flag_of(c) {
            raise self.error(
              if @unicodedata.is_alpha(c) {
                "unknown flag"
              } else {
                "missing -, : or )"
              },
            )
          }
        }
      }
      if c == ')' {
        // global flags
        if !at_start {
          raise self.error("global flags not at the start of the expression")
        }
        for f in add {
          self.flags = self.flags.with_flag(f, true)
        }
        return None
      }
      let del : Array[Int] = []
      if c == '-' {
        match self.get() {
          None => raise self.error("missing flag")
          Some(n) => c = n
        }
        if !flag_of(c) {
          raise self.error(
            if @unicodedata.is_alpha(c) {
              "unknown flag"
            } else {
              "missing flag"
            },
          )
        }
        for ;; {
          if c is ('a' | 'u' | 'L') {
            raise self.error(
              "bad inline flags: cannot turn off flags 'a', 'u' and 'L'",
            )
          }
          del.push(c)
          match self.get() {
            None => raise self.error("missing :")
            Some(n) => c = n
          }
          if c == ':' {
            break
          }
          if !flag_of(c) {
            raise self.error(
              if @unicodedata.is_alpha(c) {
                "unknown flag"
              } else {
                "missing :"
              },
            )
          }
        }
      }
      for f in add {
        if del.contains(f) {
          raise self.error("bad inline flags: flag turned on and off")
        }
      }
      for f in add {
        self.flags = self.flags.with_flag(f, true)
      }
      for f in del {
        self.flags = self.flags.with_flag(f, false)
      }
      capture = false
      scoped = true
    } else {
      raise self.error("unknown extension ?" + cps_to_string([char]))
    }
  }
  let gid = if capture {
    let gid = self.groups
    self.groups += 1
    if self.groups > 100 {
      raise self.error("too many groups")
    }
    if name is Some(n) {
      if self.group_names.contains(n) {
        raise self.error("redefinition of group name")
      }
      self.group_names[n] = gid
    }
    self.open_groups.push(gid)
    Some(gid)
  } else {
    None
  }
  let p = self.parse_sub(false, nested + 1)
  if scoped {
    self.flags = { ..saved_flags, verbose: saved_flags.verbose, }
  }
  if !self.matches(')') {
    raise self.error("missing ), unterminated subpattern")
  }
  if gid is Some(g) {
    self.open_groups.remove(self.open_groups.length() - 1) |> ignore
    self.group_widths[g] = self.width(p)
  }
  if is_atomic {
    Some(Atomic(p))
  } else {
    Some(Group(gid, p))
  }
}

///|
const MAXWIDTH : Int = 0x7FFFFFFF

///|
fn add_width(a : Int, b : Int) -> Int {
  if a >= MAXWIDTH - b {
    MAXWIDTH
  } else {
    a + b
  }
}

///|
/// `SubPattern.getwidth()`: (min, max) match width.
fn Parser::width(self : Parser, n : Node) -> (Int, Int) {
  match n {
    Literal(_) | Set(_) => (1, 1)
    At(_) | Look(_) => (0, 0)
    Seq(items) => {
      let mut lo = 0
      let mut hi = 0
      for it in items {
        let (l, h) = self.width(it)
        lo = add_width(lo, l)
        hi = add_width(hi, h)
      }
      (lo, hi)
    }
    Alt(items) => {
      let mut lo = MAXWIDTH
      let mut hi = 0
      for it in items {
        let (l, h) = self.width(it)
        lo = @cmp.minimum(lo, l)
        hi = @cmp.maximum(hi, h)
      }
      (lo, hi)
    }
    Group(_, p) | Atomic(p) => self.width(p)
    Repeat(p, min~, max~, ..) => {
      let (l, h) = self.width(p)
      let lo = if l == 0 || min == 0 {
        0
      } else if l >= MAXWIDTH / min {
        MAXWIDTH
      } else {
        l * min
      }
      let hi = match max {
        None => if h == 0 { 0 } else { MAXWIDTH }
        Some(m) =>
          if h == 0 || m == 0 {
            0
          } else if h >= MAXWIDTH / m {
            MAXWIDTH
          } else {
            h * m
          }
      }
      (lo, hi)
    }
    Backref(g, ..) =>
      match self.group_widths.get(g) {
        Some(w) => w
        None => (0, MAXWIDTH)
      }
    Conditional(_, yes, no) => {
      let (l1, h1) = self.width(yes)
      let (l2, h2) = match no {
        Some(n) => self.width(n)
        None => (0, 0)
      }
      (@cmp.minimum(l1, l2), @cmp.maximum(h1, h2))
    }
  }
}
