// A backtracking matcher over the parsed pattern, following CPython's `sre`
// (leftmost-first alternation, greedy / lazy / possessive repeats, atomic
// groups, lookaround, backreferences, conditional groups, Unicode `\b`).
// It is used for the patterns MoonBit core's `@string.Regex` cannot run
// exactly.

///|
/// The parsed pattern with every character class resolved to the code
/// points it matches.
priv enum BNode {
  BChar(Array[(Int, Int)])
  BAt(AtKind)
  BSeq(Array[BNode])
  BAlt(Array[BNode])
  BGroup(Int?, BNode)
  BRepeat(BNode, Int, Int?, Int) // 0 greedy, 1 lazy, 2 possessive
  BBackref(Int, CaseMode)
  BLook(BNode, Bool, Bool, Int) // ahead, negate, behind width
  BAtomic(BNode)
  BCond(Int, BNode, BNode?)
}

///|
fn lower_node(n : Node) -> BNode {
  match n {
    Literal(c, case_~) => BChar(class_members([(c, c)], false, case_))
    Set(set, negate~, case_~) => BChar(class_members(set, negate, case_))
    At(kind) => BAt(kind)
    Seq(items) => BSeq(items.map(i => lower_node(i)))
    Alt(items) => BAlt(items.map(i => lower_node(i)))
    Group(g, p) => BGroup(g, lower_node(p))
    Repeat(p, min~, max~, lazy_~, possessive~) =>
      BRepeat(
        lower_node(p),
        min,
        max,
        if possessive {
          2
        } else if lazy_ {
          1
        } else {
          0
        },
      )
    Backref(g, case_~) => BBackref(g, case_)
    Look(p, ahead~, negate~, width~) => BLook(lower_node(p), ahead, negate, width)
    Atomic(p) => BAtomic(lower_node(p))
    Conditional(g, yes, no) =>
      BCond(g, lower_node(yes), no.map(x => lower_node(x)))
  }
}

///|
fn chars_contain(set : Array[(Int, Int)], cp : Int) -> Bool {
  for lo = 0, hi = set.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < set[mid].0 {
      continue lo, mid
    } else if cp > set[mid].1 {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
priv struct Matcher {
  input : Array[Int]
  /// start / end of each group (index 0 unused), -1 when unset
  starts : Array[Int]
  ends : Array[Int]
}

///|
fn Matcher::is_word(self : Matcher, i : Int, ascii : Bool) -> Bool {
  if i < 0 || i >= self.input.length() {
    return false
  }
  let c = self.input[i]
  if ascii {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_'
  } else {
    c == '_' || @unicodedata.is_alnum(c)
  }
}

///|
fn Matcher::at(self : Matcher, kind : AtKind, pos : Int) -> Bool {
  let n = self.input.length()
  match kind {
    BeginString => pos == 0
    BeginLine => pos == 0 || self.input[pos - 1] == '\n'
    EndDollar => pos == n || (pos == n - 1 && self.input[n - 1] == '\n')
    EndLine => pos == n || self.input[pos] == '\n'
    EndString => pos == n
    Boundary(ascii~) => self.is_word(pos - 1, ascii) != self.is_word(pos, ascii)
    NonBoundary(ascii~) =>
      n > 0 && self.is_word(pos - 1, ascii) == self.is_word(pos, ascii)
  }
}

///|
fn same_case(a : Int, b : Int, case_ : CaseMode) -> Bool {
  a == b || chars_contain(class_members([(a, a)], false, case_), b)
}

///|
/// Match `node` at `pos`, then the continuation `k`.
fn Matcher::run(
  self : Matcher,
  node : BNode,
  pos : Int,
  k : (Int) -> Bool,
) -> Bool {
  match node {
    BChar(set) =>
      pos < self.input.length() &&
      chars_contain(set, self.input[pos]) &&
      k(pos + 1)
    BAt(kind) => self.at(kind, pos) && k(pos)
    BSeq(items) => self.run_seq(items, 0, pos, k)
    BAlt(items) => items.iter().any(item => self.run(item, pos, k))
    BGroup(None, p) => self.run(p, pos, k)
    BGroup(Some(g), p) => {
      let old_start = self.starts[g]
      let old_end = self.ends[g]
      let ok = self.run(p, pos, end => {
        let s = self.starts[g]
        let e = self.ends[g]
        self.starts[g] = pos
        self.ends[g] = end
        if k(end) {
          true
        } else {
          self.starts[g] = s
          self.ends[g] = e
          false
        }
      })
      if !ok {
        self.starts[g] = old_start
        self.ends[g] = old_end
      }
      ok
    }
    BRepeat(p, min, max, 2) => {
      // possessive: the greedy maximum, without backtracking into it
      let mut count = 0
      let mut cur = pos
      while max is None || count < max.unwrap() {
        let mut next = -1
        if !self.run(p, cur, e => {
            next = e
            true
          }) {
          break
        }
        count += 1
        if next == cur {
          // an empty iteration ends the loop
          count = @cmp.maximum(count, min)
          break
        }
        cur = next
      }
      count >= min && k(cur)
    }
    BRepeat(p, min, max, mode) => self.run_repeat(p, min, max, mode == 1, 0, pos, k)
    BBackref(g, case_) => {
      let s = self.starts[g]
      let e = self.ends[g]
      if s < 0 || e < 0 {
        return false
      }
      let len = e - s
      if pos + len > self.input.length() {
        return false
      }
      for i in 0..<len {
        if !same_case(self.input[s + i], self.input[pos + i], case_) {
          return false
        }
      }
      k(pos + len)
    }
    BLook(p, ahead, negate, width) => {
      let found = if ahead {
        self.run(p, pos, _ => true)
      } else {
        let start = pos - width
        start >= 0 && self.run(p, start, e => e == pos)
      }
      if negate {
        !found && k(pos)
      } else {
        found && k(pos)
      }
    }
    BAtomic(p) => {
      let mut end = -1
      self.run(p, pos, e => {
        end = e
        true
      }) &&
      k(end)
    }
    BCond(g, yes, no) =>
      if self.starts[g] >= 0 && self.ends[g] >= 0 {
        self.run(yes, pos, k)
      } else {
        match no {
          Some(n) => self.run(n, pos, k)
          None => k(pos)
        }
      }
  }
}

///|
fn Matcher::run_seq(
  self : Matcher,
  items : Array[BNode],
  i : Int,
  pos : Int,
  k : (Int) -> Bool,
) -> Bool {
  if i == items.length() {
    k(pos)
  } else {
    self.run(items[i], pos, p => self.run_seq(items, i + 1, p, k))
  }
}

///|
fn Matcher::run_repeat(
  self : Matcher,
  p : BNode,
  min : Int,
  max : Int?,
  lazy_ : Bool,
  count : Int,
  pos : Int,
  k : (Int) -> Bool,
) -> Bool {
  let can_more = match max {
    Some(m) => count < m
    None => true
  }
  let more = () => can_more &&
    self.run(p, pos, next => {
      // like sre, an iteration matching the empty string ends the loop
      if next == pos && count >= min {
        k(next)
      } else {
        self.run_repeat(p, min, max, lazy_, count + 1, next, k)
      }
    })
  if count < min {
    more()
  } else if lazy_ {
    k(pos) || more()
  } else {
    more() || k(pos)
  }
}

///|
/// `re.search` with the backtracking matcher: the groups of the leftmost
/// match (as code point offsets), if any.
fn backtrack_search(
  root : BNode,
  groups : Int,
  input : Array[Int],
) -> Array[(Int, Int)]? {
  for start in 0..=input.length() {
    let m = {
      input,
      starts: Array::make(groups + 1, -1),
      ends: Array::make(groups + 1, -1),
    }
    let mut end = -1
    if m.run(root, start, e => {
        end = e
        true
      }) {
      m.starts[0] = start
      m.ends[0] = end
      return Some(Array::makei(groups + 1, i => (m.starts[i], m.ends[i])))
    }
  }
  None
}
