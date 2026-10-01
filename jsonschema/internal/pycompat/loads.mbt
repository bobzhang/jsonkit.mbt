///|
/// Raised by `loads`, mirroring Python's `json.JSONDecodeError`.
pub suberror JSONDecodeError {
  JSONDecodeError(msg~ : String, pos~ : Int, lineno~ : Int, colno~ : Int)
}

///|
pub impl Show for JSONDecodeError with fn output(self, logger) {
  let JSONDecodeError(msg~, pos~, lineno~, colno~) = self
  logger.write_string("\{msg}: line \{lineno} column \{colno} (char \{pos})")
}

///|
priv struct Decoder {
  src : String
  mut pos : Int
}

///|
fn Decoder::error(self : Decoder, msg : String, pos : Int) -> JSONDecodeError {
  // line / column are counted in UTF-16 units here; Python counts code points.
  let mut lineno = 1
  let mut last_nl = -1
  for i in 0..<pos {
    if self.src.code_unit_at(i) == '\n' {
      lineno += 1
      last_nl = i
    }
  }
  JSONDecodeError(msg~, pos~, lineno~, colno=pos - last_nl)
}

///|
fn Decoder::peek(self : Decoder) -> Int {
  if self.pos < self.src.length() {
    self.src.code_unit_at(self.pos).to_int()
  } else {
    -1
  }
}

///|
fn Decoder::skip_ws(self : Decoder) -> Unit {
  while self.peek() is (0x20 | 0x09 | 0x0A | 0x0D) {
    self.pos += 1
  }
}

///|
fn Decoder::starts_with(self : Decoder, lit : String) -> Bool {
  let n = lit.length()
  if self.pos + n > self.src.length() {
    return false
  }
  for i in 0..<n {
    if self.src.code_unit_at(self.pos + i) != lit.code_unit_at(i) {
      return false
    }
  }
  true
}

///|
/// Parse a JSON document exactly like Python's `json.loads` (with default
/// arguments) would, representing the result as a core `Json`.
///
/// Python distinguishes `int` from `float`; core `Json` stores both as a
/// `Double`.  To keep the distinction observable, every float-like token
/// (one with a fraction or exponent, or one of `NaN` / `Infinity` /
/// `-Infinity`) keeps its source spelling in the `repr~` field, as do
/// integers too large to be represented exactly.  See `is_int` / `is_float`.
///
/// Like Python: duplicate object keys keep the first position and the last
/// value, lone surrogate escapes are preserved, and `NaN` / `Infinity` are
/// accepted.
pub fn loads(s : String) -> Json raise JSONDecodeError {
  let d = { src: s, pos: 0, }
  if d.peek() == 0xFEFF {
    raise d.error("Unexpected UTF-8 BOM (decode using utf-8-sig)", 0)
  }
  d.skip_ws()
  let value = d.value()
  d.skip_ws()
  if d.pos != s.length() {
    raise d.error("Extra data", d.pos)
  }
  value
}

///|
fn Decoder::value(self : Decoder) -> Json raise JSONDecodeError {
  let c = self.peek()
  match c {
    0x22 => {
      self.pos += 1
      Json::string(self.string_body())
    }
    0x7B => self.object()
    0x5B => self.array()
    _ =>
      if c == 'n' && self.starts_with("null") {
        self.pos += 4
        Json::null()
      } else if c == 't' && self.starts_with("true") {
        self.pos += 4
        Json::boolean(true)
      } else if c == 'f' && self.starts_with("false") {
        self.pos += 5
        Json::boolean(false)
      } else if c == 'N' && self.starts_with("NaN") {
        self.pos += 3
        Json::number(@double.not_a_number, repr="NaN")
      } else if c == 'I' && self.starts_with("Infinity") {
        self.pos += 8
        Json::number(@double.infinity, repr="Infinity")
      } else if c == '-' && self.starts_with("-Infinity") {
        self.pos += 9
        Json::number(@double.neg_infinity, repr="-Infinity")
      } else if c == '-' || (c >= '0' && c <= '9') {
        match self.number() {
          Some(n) => n
          None => raise self.error("Expecting value", self.pos)
        }
      } else {
        raise self.error("Expecting value", self.pos)
      }
  }
}

///|
fn is_digit(c : Int) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn Decoder::number(self : Decoder) -> Json? {
  let start = self.pos
  let src = self.src
  let n = src.length()
  let at = (i : Int) => if i < n { src.code_unit_at(i).to_int() } else { -1 }
  let mut i = start
  if at(i) == '-' {
    i += 1
  }
  if at(i) == '0' {
    i += 1
  } else if at(i) >= '1' && at(i) <= '9' {
    while is_digit(at(i)) {
      i += 1
    }
  } else {
    return None
  }
  let mut is_float = false
  if at(i) == '.' && is_digit(at(i + 1)) {
    is_float = true
    i += 2
    while is_digit(at(i)) {
      i += 1
    }
  }
  if at(i) is ('e' | 'E') {
    let mut j = i + 1
    if at(j) is ('+' | '-') {
      j += 1
    }
    if is_digit(at(j)) {
      is_float = true
      while is_digit(at(j)) {
        j += 1
      }
      i = j
    }
  }
  self.pos = i
  let token = src.unsafe_substring(start~, end=i)
  let d = @string.parse_double(token) catch { _ => overflowed_value(token) }
  if is_float {
    Some(Json::number(d, repr=token))
  } else {
    let digits = if token.has_prefix("-") {
      token.length() - 1
    } else {
      token.length()
    }
    if digits > 15 {
      Some(Json::number(d, repr=normalize_int_token(token)))
    } else if d == 0.0 {
      // `int("-0")` is `0`
      Some(Json::number(0.0))
    } else {
      Some(Json::number(d))
    }
  }
}

///|
fn normalize_int_token(token : String) -> String {
  if token.has_prefix("-") && token.iter().all(c => c is ('-' | '0')) {
    "0"
  } else {
    token
  }
}

///|
fn Decoder::string_body(self : Decoder) -> String raise JSONDecodeError {
  let begin = self.pos - 1
  let sb = StringBuilder()
  let src = self.src
  let n = src.length()
  for ;; {
    if self.pos >= n {
      raise self.error("Unterminated string starting at", begin)
    }
    let c = src.code_unit_at(self.pos).to_int()
    if c == '"' {
      self.pos += 1
      break
    } else if c == '\\' {
      self.pos += 1
      if self.pos >= n {
        raise self.error("Unterminated string starting at", begin)
      }
      let e = src.code_unit_at(self.pos).to_int()
      match e {
        '"' => sb.write_char('"')
        '\\' => sb.write_char('\\')
        '/' => sb.write_char('/')
        'b' => sb.write_char('\b')
        'f' => sb.write_char('\u{0c}')
        'n' => sb.write_char('\n')
        'r' => sb.write_char('\r')
        't' => sb.write_char('\t')
        'u' => {
          let u = self.hex4(self.pos + 1)
          self.pos += 4
          let mut cp = u
          if u >= 0xD800 &&
            u <= 0xDBFF &&
            self.pos + 2 < n &&
            src.code_unit_at(self.pos + 1) == '\\' &&
            src.code_unit_at(self.pos + 2) == 'u' {
            let u2 = self.hex4(self.pos + 3)
            if u2 >= 0xDC00 && u2 <= 0xDFFF {
              cp = 0x10000 + ((u - 0xD800) << 10) + (u2 - 0xDC00)
              self.pos += 6
            }
          }
          @unicodedata.write_code_point(sb, cp)
        }
        _ => raise self.error("Invalid \\escape", self.pos - 1)
      }
      self.pos += 1
    } else if c < 0x20 {
      raise self.error("Invalid control character at", self.pos)
    } else {
      sb.write_char(Int::unsafe_to_char(c))
      self.pos += 1
    }
  }
  sb.to_string()
}

///|
fn Decoder::hex4(self : Decoder, at : Int) -> Int raise JSONDecodeError {
  let src = self.src
  if at + 4 > src.length() {
    raise self.error("Invalid \\uXXXX escape", at - 1)
  }
  let mut v = 0
  for i in 0..<4 {
    let c = src.code_unit_at(at + i).to_int()
    let d = if c >= '0' && c <= '9' {
      c - '0'
    } else if c >= 'a' && c <= 'f' {
      c - 'a' + 10
    } else if c >= 'A' && c <= 'F' {
      c - 'A' + 10
    } else {
      raise self.error("Invalid \\uXXXX escape", at - 1)
    }
    v = v * 16 + d
  }
  v
}

///|
fn Decoder::object(self : Decoder) -> Json raise JSONDecodeError {
  self.pos += 1
  let map : Map[String, Json] = Map([])
  self.skip_ws()
  if self.peek() == '}' {
    self.pos += 1
    return Json::object(map)
  }
  for ;; {
    if self.peek() != '"' {
      raise self.error(
        "Expecting property name enclosed in double quotes",
        self.pos,
      )
    }
    self.pos += 1
    let key = self.string_body()
    self.skip_ws()
    if self.peek() != ':' {
      raise self.error("Expecting ':' delimiter", self.pos)
    }
    self.pos += 1
    self.skip_ws()
    let v = self.value()
    map[key] = v
    self.skip_ws()
    match self.peek() {
      0x7D => {
        self.pos += 1
        break
      }
      0x2C => {
        self.pos += 1
        self.skip_ws()
        if self.peek() == '}' {
          raise self.error(
            "Illegal trailing comma before end of object",
            self.pos - 1,
          )
        }
      }
      _ => raise self.error("Expecting ',' delimiter", self.pos)
    }
  }
  Json::object(map)
}

///|
fn Decoder::array(self : Decoder) -> Json raise JSONDecodeError {
  self.pos += 1
  let items : Array[Json] = []
  self.skip_ws()
  if self.peek() == ']' {
    self.pos += 1
    return Json::array(items)
  }
  for ;; {
    items.push(self.value())
    self.skip_ws()
    match self.peek() {
      0x5D => {
        self.pos += 1
        break
      }
      0x2C => {
        self.pos += 1
        self.skip_ws()
        if self.peek() == ']' {
          raise self.error(
            "Illegal trailing comma before end of array",
            self.pos - 1,
          )
        }
      }
      _ => raise self.error("Expecting ',' delimiter", self.pos)
    }
  }
  Json::array(items)
}

///|
/// The value Python's `float(token)` gives for tokens that do not fit a
/// double: infinity for huge magnitudes, zero for tiny ones.
fn overflowed_value(token : String) -> Double {
  let negative = token.has_prefix("-")
  let body = if negative {
    token.unsafe_substring(start=1, end=token.length())
  } else {
    token
  }
  let (mantissa, exp) = match body.find("e") {
    Some(i) =>
      (
        body.unsafe_substring(start=0, end=i),
        body.unsafe_substring(start=i + 1, end=body.length()),
      )
    None =>
      match body.find("E") {
        Some(i) =>
          (
            body.unsafe_substring(start=0, end=i),
            body.unsafe_substring(start=i + 1, end=body.length()),
          )
        None => (body, "0")
      }
  }
  let exp_negative = exp.has_prefix("-")
  let int_digits = match mantissa.find(".") {
    Some(i) => i
    None => mantissa.length()
  }
  let magnitude = if exp_negative { -1 } else { int_digits }
  let v = if magnitude > 0 { @double.infinity } else { 0.0 }
  if negative {
    -v
  } else {
    v
  }
}
