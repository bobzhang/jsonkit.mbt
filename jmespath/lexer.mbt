// Port of jmespath/lexer.py.
//
// The lexer works on code points (`Array[Char]`) so that token positions are
// the same as Python's string indices.

///|
/// The value of a token: identifiers and operators carry their text,
/// `number` tokens an integer and `literal` tokens a JSON value.
pub(all) enum TokenValue {
  Str(String)
  Int(Int)
  Literal(Json)
} derive(Eq, Debug)

///|
/// `str()` of a token value, used by error messages.
fn TokenValue::py_str(self : TokenValue) -> String {
  match self {
    Str(s) => s
    Int(i) => i.to_string()
    Literal(v) => py_str(v)
  }
}

///|
/// A token, `{'type': ..., 'value': ..., 'start': ..., 'end': ...}` upstream.
/// `end` reproduces upstream's values exactly, including its quirks (for
/// literals it is the token length, for two-character operators `start + 1`).
pub(all) struct Token {
  type_ : String
  value : TokenValue
  start : Int
  end : Int
} derive(Eq, Debug)

///|
/// The JMESPath tokenizer (`jmespath.lexer.Lexer`).
pub struct Lexer {
  priv mut position : Int
  priv mut chars : Array[Char]
  priv mut current : Char?
  priv mut length : Int
}

///|
pub fn Lexer::new() -> Lexer {
  { position: 0, chars: [], current: None, length: 0, }
}

///|
fn simple_token_type(c : Char) -> String? {
  match c {
    '.' => Some("dot")
    '*' => Some("star")
    ']' => Some("rbracket")
    ',' => Some("comma")
    ':' => Some("colon")
    '@' => Some("current")
    '(' => Some("lparen")
    ')' => Some("rparen")
    '{' => Some("lbrace")
    '}' => Some("rbrace")
    _ => None
  }
}

///|
fn is_start_identifier(c : Char) -> Bool {
  c is ('a'..='z' | 'A'..='Z' | '_')
}

///|
fn is_valid_identifier(c : Char?) -> Bool {
  c is Some('a'..='z' | 'A'..='Z' | '_' | '0'..='9')
}

///|
fn is_valid_number(c : Char?) -> Bool {
  c is Some('0'..='9')
}

///|
/// Python's `int(buff)` for `-?[0-9]+`, saturating at the `Int` range.
fn parse_token_int(buff : String) -> Int {
  let mut negative = false
  let mut acc = 0L
  for c in buff {
    if c == '-' {
      negative = true
    } else {
      acc = acc * 10L + (c.to_int() - '0'.to_int()).to_int64()
      if acc > 2147483648L {
        acc = 2147483648L
      }
    }
  }
  let v = if negative { -acc } else { acc }
  if v > 2147483647L {
    2147483647
  } else {
    v.to_int()
  }
}

///|
/// Tokenizes `expression`.  Upstream yields tokens lazily, but the parser
/// always consumes the whole generator first, so an eager array is
/// equivalent.  The last token is always `eof`.
pub fn Lexer::tokenize(
  self : Lexer,
  expression : String,
) -> Array[Token] raise JMESPathError {
  self.initialize_for_expression(expression)
  let tokens : Array[Token] = []
  while self.current is Some(current) {
    if simple_token_type(current) is Some(type_) {
      tokens.push({
        type_,
        value: Str(current.to_string()),
        start: self.position,
        end: self.position + 1,
      })
      self.next() |> ignore
    } else if is_start_identifier(current) {
      let start = self.position
      let buff = StringBuilder()
      buff.write_char(current)
      while is_valid_identifier(self.next()) {
        buff.write_char(self.current.unwrap())
      }
      let buff = buff.to_string()
      tokens.push({
        type_: "unquoted_identifier",
        value: Str(buff),
        start,
        end: start + buff.char_length(),
      })
    } else if current is (' ' | '\t' | '\n' | '\r') {
      self.next() |> ignore
    } else if current == '[' {
      let start = self.position
      let next_char = self.next()
      if next_char == Some(']') {
        self.next() |> ignore
        tokens.push({
          type_: "flatten",
          value: Str("[]"),
          start,
          end: start + 2,
        })
      } else if next_char == Some('?') {
        self.next() |> ignore
        tokens.push({
          type_: "filter",
          value: Str("[?"),
          start,
          end: start + 2,
        })
      } else {
        tokens.push({
          type_: "lbracket",
          value: Str("["),
          start,
          end: start + 1,
        })
      }
    } else if current == '\'' {
      tokens.push(self.consume_raw_string_literal())
    } else if current == '|' {
      tokens.push(self.match_or_else('|', "or", "pipe"))
    } else if current == '&' {
      tokens.push(self.match_or_else('&', "and", "expref"))
    } else if current == '`' {
      tokens.push(self.consume_literal())
    } else if is_valid_number(Some(current)) {
      let start = self.position
      let buff = self.consume_number()
      tokens.push({
        type_: "number",
        value: Int(parse_token_int(buff)),
        start,
        end: start + buff.char_length(),
      })
    } else if current == '-' {
      // Negative number.
      let start = self.position
      let buff = self.consume_number()
      if buff.char_length() > 1 {
        tokens.push({
          type_: "number",
          value: Int(parse_token_int(buff)),
          start,
          end: start + buff.char_length(),
        })
      } else {
        raise LexerError(
          lexer_position=start,
          lexer_value=buff,
          message="Unknown token '\{buff}'",
          expression=None,
        )
      }
    } else if current == '"' {
      tokens.push(self.consume_quoted_identifier())
    } else if current == '<' {
      tokens.push(self.match_or_else('=', "lte", "lt"))
    } else if current == '>' {
      tokens.push(self.match_or_else('=', "gte", "gt"))
    } else if current == '!' {
      tokens.push(self.match_or_else('=', "ne", "not"))
    } else if current == '=' {
      if self.next() == Some('=') {
        tokens.push({
          type_: "eq",
          value: Str("=="),
          start: self.position - 1,
          end: self.position,
        })
        self.next() |> ignore
      } else {
        // If we're at the EOF, we never advanced the position so we don't
        // need to rewind it back one location.
        let position = if self.current is None {
          self.position
        } else {
          self.position - 1
        }
        raise LexerError(
          lexer_position=position,
          lexer_value="=",
          message="Unknown token '='",
          expression=None,
        )
      }
    } else {
      raise LexerError(
        lexer_position=self.position,
        lexer_value=current.to_string(),
        message="Unknown token \{current}",
        expression=None,
      )
    }
  }
  tokens.push({
    type_: "eof",
    value: Str(""),
    start: self.length,
    end: self.length,
  })
  tokens
}

///|
fn Lexer::consume_number(self : Lexer) -> String {
  let buff = StringBuilder()
  buff.write_char(self.current.unwrap())
  while is_valid_number(self.next()) {
    buff.write_char(self.current.unwrap())
  }
  buff.to_string()
}

///|
fn Lexer::initialize_for_expression(
  self : Lexer,
  expression : String,
) -> Unit raise JMESPathError {
  if expression == "" {
    raise EmptyExpressionError
  }
  self.position = 0
  self.chars = expression.to_array()
  self.current = Some(self.chars[self.position])
  self.length = self.chars.length()
}

///|
fn Lexer::next(self : Lexer) -> Char? {
  if self.position == self.length - 1 {
    self.current = None
  } else {
    self.position += 1
    self.current = Some(self.chars[self.position])
  }
  self.current
}

///|
/// `self._expression[start:]` (code point indexed).
fn Lexer::expression_from(self : Lexer, start : Int) -> String {
  String::from_array(self.chars[start:])
}

///|
/// Consume until the delimiter is reached, allowing for the delimiter to be
/// escaped with "\".
fn Lexer::consume_until(
  self : Lexer,
  delimiter : Char,
) -> String raise JMESPathError {
  let start = self.position
  let buff = StringBuilder()
  self.next() |> ignore
  while self.current != Some(delimiter) {
    if self.current == Some('\\') {
      buff.write_char('\\')
      self.next() |> ignore
    }
    match self.current {
      None =>
        // We're at the EOF.
        raise LexerError(
          lexer_position=start,
          lexer_value=self.expression_from(start),
          message="Unclosed \{delimiter} delimiter",
          expression=None,
        )
      Some(c) => buff.write_char(c)
    }
    self.next() |> ignore
  }
  // Skip the closing delimiter.
  self.next() |> ignore
  buff.to_string()
}

///|
fn Lexer::consume_literal(self : Lexer) -> Token raise JMESPathError {
  let start = self.position
  let lexeme = self.consume_until('`').replace_all(old="\\`", new="`")
  let parsed_json = loads(lexeme) catch {
    _ =>
      // Invalid JSON values should be converted to quoted JSON strings
      // during the JEP-12 deprecation period (upstream also emits a
      // PendingDeprecationWarning here).
      loads("\"" + py_lstrip(lexeme) + "\"") catch {
        _ =>
          raise LexerError(
            lexer_position=start,
            lexer_value=self.expression_from(start),
            message="Bad token \{lexeme}",
            expression=None,
          )
      }
  }
  let token_len = self.position - start
  { type_: "literal", value: Literal(parsed_json), start, end: token_len, }
}

///|
fn Lexer::consume_quoted_identifier(self : Lexer) -> Token raise JMESPathError {
  let start = self.position
  let lexeme = "\"" + self.consume_until('"') + "\""
  let token_len = self.position - start
  let value = loads(lexeme) catch {
    e => {
      // error_message = str(e).split(':')[0]
      let full = e.to_string()
      let error_message = match full.find(":") {
        Some(i) => full.view(end_offset=i).to_owned()
        None => full
      }
      raise LexerError(
        lexer_position=start,
        lexer_value=lexeme,
        message=error_message,
        expression=None,
      )
    }
  }
  let value = match value {
    String(s) => s
    other => py_str(other)
  }
  { type_: "quoted_identifier", value: Str(value), start, end: token_len, }
}

///|
fn Lexer::consume_raw_string_literal(self : Lexer) -> Token raise JMESPathError {
  let start = self.position
  let lexeme = self.consume_until('\'').replace_all(old="\\'", new="'")
  let token_len = self.position - start
  {
    type_: "literal",
    value: Literal(Json::string(lexeme)),
    start,
    end: token_len,
  }
}

///|
fn Lexer::match_or_else(
  self : Lexer,
  expected : Char,
  match_type : String,
  else_type : String,
) -> Token {
  let start = self.position
  let current = self.current.unwrap()
  let next_char = self.next()
  if next_char == Some(expected) {
    self.next() |> ignore
    return {
      type_: match_type,
      value: Str(current.to_string() + expected.to_string()),
      start,
      end: start + 1,
    }
  }
  { type_: else_type, value: Str(current.to_string()), start, end: start, }
}
