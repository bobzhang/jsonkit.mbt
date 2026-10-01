///|
priv struct PrettyPrinter {
  width : Int
  sb : StringBuilder
}

///|
/// Python `pprint.pformat(obj, width=width, sort_dicts=False)` (default
/// `indent=1`, `compact=False`, unlimited depth).
pub fn pformat(j : Json, width? : Int = 80) -> String {
  let p = { width, sb: StringBuilder(), }
  p.format(j, 0, 0, 0)
  p.sb.to_string()
}

///|
fn PrettyPrinter::format(
  self : PrettyPrinter,
  obj : Json,
  indent : Int,
  allowance : Int,
  level : Int,
) -> Unit {
  let rep = repr(obj)
  let max_width = self.width - indent - allowance
  if @unicodedata.py_len(rep) > max_width {
    match obj {
      Object(m) => {
        self.pprint_dict(m, indent, allowance, level + 1)
        return
      }
      Array(xs) => {
        self.pprint_list(xs, indent, allowance, level + 1)
        return
      }
      String(s) => {
        self.pprint_str(s, indent, allowance, level + 1)
        return
      }
      _ => ()
    }
  }
  self.sb.write_string(rep)
}

///|
fn PrettyPrinter::pprint_dict(
  self : PrettyPrinter,
  m : Map[String, Json],
  indent : Int,
  allowance : Int,
  level : Int,
) -> Unit {
  self.sb.write_char('{')
  if m.length() > 0 {
    // _format_dict_items
    let indent = indent + 1
    let allowance = allowance + 1
    let delimnl = ",\n" + " ".repeat(indent)
    let last_index = m.length() - 1
    let mut i = 0
    for key, ent in m {
      let last = i == last_index
      let rep = repr_string(key)
      self.sb.write_string(rep)
      self.sb.write_string(": ")
      self.format(
        ent,
        indent + @unicodedata.py_len(rep) + 2,
        if last {
          allowance
        } else {
          1
        },
        level,
      )
      if !last {
        self.sb.write_string(delimnl)
      }
      i += 1
    }
  }
  self.sb.write_char('}')
}

///|
fn PrettyPrinter::pprint_list(
  self : PrettyPrinter,
  xs : Array[Json],
  indent : Int,
  allowance : Int,
  level : Int,
) -> Unit {
  self.sb.write_char('[')
  // _format_items
  let indent = indent + 1
  let allowance = allowance + 1
  let delimnl = ",\n" + " ".repeat(indent)
  for i, ent in xs {
    let last = i == xs.length() - 1
    if i > 0 {
      self.sb.write_string(delimnl)
    }
    self.format(ent, indent, if last { allowance } else { 1 }, level)
  }
  self.sb.write_char(']')
}

///|
/// Python `str.splitlines(keepends=True)` over code points.
pub fn splitlines_keepends(cps : Array[Int]) -> Array[Array[Int]] {
  let lines = []
  let mut current = []
  let n = cps.length()
  for i = 0; i < n; {
    let c = cps[i]
    current.push(c)
    if c == '\r' && i + 1 < n && cps[i + 1] == '\n' {
      current.push('\n')
      lines.push(current)
      current = []
      continue i + 2
    }
    if c
      is ('\n'
      | '\r'
      | 0x0B
      | 0x0C
      | 0x1C
      | 0x1D
      | 0x1E
      | 0x85
      | 0x2028
      | 0x2029) {
      lines.push(current)
      current = []
    }
    continue i + 1
  }
  if current.length() > 0 {
    lines.push(current)
  }
  lines
}

///|
/// `re.findall(r'\S*\s*', line)` minus the trailing empty match.
fn split_words(line : Array[Int]) -> Array[Array[Int]] {
  let parts = []
  let n = line.length()
  for i = 0; i < n; {
    let part = []
    let mut j = i
    while j < n && !@unicodedata.is_space(line[j]) {
      part.push(line[j])
      j += 1
    }
    while j < n && @unicodedata.is_space(line[j]) {
      part.push(line[j])
      j += 1
    }
    parts.push(part)
    continue j
  }
  parts
}

///|
fn repr_cps(cps : Array[Int]) -> String {
  repr_string(@unicodedata.from_code_points(cps))
}

///|
fn PrettyPrinter::pprint_str(
  self : PrettyPrinter,
  s : String,
  indent : Int,
  allowance : Int,
  level : Int,
) -> Unit {
  if s.length() == 0 {
    self.sb.write_string(repr_string(s))
    return
  }
  let chunks : Array[String] = []
  let lines = splitlines_keepends(@unicodedata.code_points(s))
  let (indent, allowance) = if level == 1 {
    (indent + 1, allowance + 1)
  } else {
    (indent, allowance)
  }
  let max_width = self.width - indent
  let mut max_width1 = max_width
  let mut rep = ""
  for i, line in lines {
    rep = repr_cps(line)
    if i == lines.length() - 1 {
      max_width1 -= allowance
    }
    if @unicodedata.py_len(rep) <= max_width1 {
      chunks.push(rep)
    } else {
      let parts = split_words(line)
      let mut max_width2 = max_width
      let mut current : Array[Int] = []
      for j, part in parts {
        let candidate = current + part
        if j == parts.length() - 1 && i == lines.length() - 1 {
          max_width2 -= allowance
        }
        if @unicodedata.py_len(repr_cps(candidate)) > max_width2 {
          if current.length() > 0 {
            chunks.push(repr_cps(current))
          }
          current = part
        } else {
          current = candidate
        }
      }
      if current.length() > 0 {
        chunks.push(repr_cps(current))
      }
    }
  }
  if chunks.length() == 1 {
    self.sb.write_string(rep)
    return
  }
  if level == 1 {
    self.sb.write_char('(')
  }
  for i, chunk in chunks {
    if i > 0 {
      self.sb.write_string("\n" + " ".repeat(indent))
    }
    self.sb.write_string(chunk)
  }
  if level == 1 {
    self.sb.write_char(')')
  }
}

///|
/// Python `textwrap.indent(text, prefix)` with the default predicate.
pub fn text_indent(text : String, prefix : String) -> String {
  let sb = StringBuilder()
  for line in splitlines_keepends(@unicodedata.code_points(text)) {
    if !line.iter().all(c => @unicodedata.is_space(c)) {
      sb.write_string(prefix)
    }
    for c in line {
      @unicodedata.write_code_point(sb, c)
    }
  }
  sb.to_string()
}

///|
/// Python `textwrap.dedent(text)`.
pub fn text_dedent(text : String) -> String {
  // lines split on "\n" only (the `re` MULTILINE semantics used upstream)
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  // _whitespace_only_re.sub('', text): lines of only spaces/tabs become ""
  let lines = lines.map(l => {
    if l.length() > 0 && l.iter().all(c => c is (' ' | '\t')) {
      ""
    } else {
      l
    }
  })
  let mut margin : String? = None
  for line in lines {
    // _leading_whitespace_re: (^[ \t]*)(?:[^ \t\n])
    let mut k = 0
    while k < line.length() && line.code_unit_at(k) is (' ' | '\t') {
      k += 1
    }
    if k == line.length() {
      continue
    }
    let ind = line.unsafe_substring(start=0, end=k)
    match margin {
      None => margin = Some(ind)
      Some(m) =>
        if ind.has_prefix(m) {
          ()
        } else if m.has_prefix(ind) {
          margin = Some(ind)
        } else {
          let mut i = 0
          while i < m.length() &&
                i < ind.length() &&
                m.code_unit_at(i) == ind.code_unit_at(i) {
            i += 1
          }
          margin = Some(m.unsafe_substring(start=0, end=i))
        }
    }
  }
  match margin {
    Some(m) if m.length() > 0 =>
      lines
      .map(l => {
        if l.has_prefix(m) {
          l.unsafe_substring(start=m.length(), end=l.length())
        } else {
          l
        }
      })
      .join("\n")
    _ => lines.join("\n")
  }
}
