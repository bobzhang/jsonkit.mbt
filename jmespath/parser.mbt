// Port of jmespath/parser.py: a top down operator precedence (Pratt)
// parser.  Token dispatch (`_token_nud_<type>` / `_token_led_<type>` looked
// up with `getattr` upstream) is done with `match` on the token type.

///|
/// `Parser.BINDING_POWER`.
fn token_binding_power(token_type : String) -> Int {
  match token_type {
    "eof"
    | "unquoted_identifier"
    | "quoted_identifier"
    | "literal"
    | "rbracket"
    | "rparen"
    | "comma"
    | "rbrace"
    | "number"
    | "current"
    | "expref"
    | "colon" => 0
    "pipe" => 1
    "or" => 2
    "and" => 3
    "eq" | "gt" | "lt" | "gte" | "lte" | "ne" => 5
    "flatten" => 9
    // Everything above stops a projection.
    "star" => 20
    "filter" => 21
    "dot" => 40
    "not" => 45
    "lbrace" => 50
    "lbracket" => 55
    "lparen" => 60
    _ => abort("unknown token type: \{token_type}")
  }
}

///|
/// The maximum binding power for a token that can stop a projection.
let projection_stop : Int = 10

///|
/// The number of most recently compiled expressions kept in the cache
/// (`Parser._MAX_SIZE`).
pub let parser_max_size : Int = 512

///|
/// `Parser._CACHE`: shared by all parsers.  When full, the oldest entry is
/// evicted (insertion order, like upstream's dict).
let parser_cache : Map[String, ParsedResult] = Map([])

///|
/// The JMESPath parser (`jmespath.parser.Parser`).
pub struct Parser {
  priv mut tokens : Array[Token]
  priv mut index : Int
}

///|
pub fn Parser::new() -> Parser {
  { tokens: [], index: 0 }
}

///|
/// Parses (and caches) an expression.
pub fn Parser::parse(
  self : Parser,
  expression : String,
) -> ParsedResult raise JMESPathError {
  if parser_cache.get(expression) is Some(cached) {
    return cached
  }
  let parsed_result = self.do_parse(expression)
  if parser_cache.length() >= parser_max_size {
    let mut oldest = None
    for key in parser_cache.keys() {
      oldest = Some(key)
      break
    }
    if oldest is Some(key) {
      parser_cache.remove(key)
    }
  }
  parser_cache[expression] = parsed_result
  parsed_result
}

///|
/// Clear the expression compilation cache (`Parser.purge()`).
pub fn Parser::purge() -> Unit {
  parser_cache.clear()
}

///|
/// The number of expressions currently cached.
pub fn Parser::cache_size() -> Int {
  parser_cache.length()
}

///|
fn Parser::do_parse(
  self : Parser,
  expression : String,
) -> ParsedResult raise JMESPathError {
  self.parse_tokens(expression) catch {
    LexerError(lexer_position~, lexer_value~, message~, ..) =>
      raise LexerError(
        lexer_position~,
        lexer_value~,
        message~,
        expression=Some(expression),
      )
    IncompleteExpressionError(..) =>
      raise IncompleteExpressionError(
        lex_position=expression.char_length(),
        token_value=None,
        token_type=None,
        expression=Some(expression),
      )
    ParseError(lex_position~, token_value~, token_type~, msg~, ..) =>
      raise ParseError(
        lex_position~,
        token_value~,
        token_type~,
        msg~,
        expression=Some(expression),
      )
    e => raise e
  }
}

///|
fn Parser::parse_tokens(
  self : Parser,
  expression : String,
) -> ParsedResult raise JMESPathError {
  self.tokens = Lexer::new().tokenize(expression)
  self.index = 0
  let parsed = self.expression()
  if self.current_token() != "eof" {
    let t = self.lookahead_token(0)
    raise new_parse_error(t, "Unexpected token: \{t.value.py_str()}")
  }
  { expression, parsed }
}

///|
fn new_parse_error(token : Token, msg : String) -> JMESPathError {
  ParseError(
    lex_position=token.start,
    token_value=token.value.py_str(),
    token_type=token.type_.to_upper(),
    msg~,
    expression=None,
  )
}

///|
fn Parser::expression(
  self : Parser,
  binding_power~ : Int = 0,
) -> Node raise JMESPathError {
  let left_token = self.lookahead_token(0)
  self.advance()
  let mut left = self.nud(left_token)
  let mut current_token = self.current_token()
  while binding_power < token_binding_power(current_token) {
    self.advance()
    left = self.led(current_token, left)
    current_token = self.current_token()
  }
  left
}

///|
fn Parser::nud(self : Parser, token : Token) -> Node raise JMESPathError {
  match token.type_ {
    "literal" => {
      guard token.value is Literal(v) else { Literal(Json::null()) }
      Literal(v)
    }
    "unquoted_identifier" => Field(token.value.py_str())
    "quoted_identifier" => {
      let field = Field(token.value.py_str())
      // You can't have a quoted identifier as a function name.
      if self.current_token() == "lparen" {
        let t = self.lookahead_token(0)
        raise ParseError(
          lex_position=0,
          token_value=t.value.py_str(),
          token_type=t.type_.to_upper(),
          msg="Quoted identifier not allowed for function names.",
          expression=None,
        )
      }
      field
    }
    "star" => {
      let left = Identity
      let right = if self.current_token() == "rbracket" {
        Identity
      } else {
        self.parse_projection_rhs(token_binding_power("star"))
      }
      ValueProjection(left, right)
    }
    "filter" => self.led_filter(Identity)
    "lbrace" => self.parse_multi_select_hash()
    "lparen" => {
      let expression = self.expression()
      self.match_("rparen")
      expression
    }
    "flatten" => {
      let left = Flatten(Identity)
      let right = self.parse_projection_rhs(token_binding_power("flatten"))
      Projection(left, right)
    }
    "not" => {
      let expr = self.expression(binding_power=token_binding_power("not"))
      NotExpression(expr)
    }
    "lbracket" =>
      if self.current_token() is ("number" | "colon") {
        let right = self.parse_index_expression()
        // We could optimize this and remove the identity() node.
        self.project_if_slice(Identity, right)
      } else if self.current_token() == "star" && self.lookahead(1) == "rbracket" {
        self.advance()
        self.advance()
        let right = self.parse_projection_rhs(token_binding_power("star"))
        Projection(Identity, right)
      } else {
        self.parse_multi_select_list()
      }
    "current" => Current
    "expref" => {
      let expression = self.expression(binding_power=token_binding_power("expref"))
      Expref(expression)
    }
    _ => self.error_nud_token(token)
  }
}

///|
fn Parser::led(
  self : Parser,
  token_type : String,
  left : Node,
) -> Node raise JMESPathError {
  match token_type {
    "dot" =>
      if self.current_token() != "star" {
        let right = self.parse_dot_rhs(token_binding_power("dot"))
        if left is Subexpression(children) {
          children.push(right)
          left
        } else {
          Subexpression([left, right])
        }
      } else {
        // We're creating a projection.
        self.advance()
        let right = self.parse_projection_rhs(token_binding_power("dot"))
        ValueProjection(left, right)
      }
    "pipe" => {
      let right = self.expression(binding_power=token_binding_power("pipe"))
      Pipe(left, right)
    }
    "or" => {
      let right = self.expression(binding_power=token_binding_power("or"))
      OrExpression(left, right)
    }
    "and" => {
      let right = self.expression(binding_power=token_binding_power("and"))
      AndExpression(left, right)
    }
    "lparen" => {
      guard left is Field(name) else {
        //  0 - first func arg or closing paren.
        // -1 - '(' token
        // -2 - invalid function "name".
        let prev_t = self.lookahead_token(-2)
        raise new_parse_error(
          prev_t,
          "Invalid function name '\{prev_t.value.py_str()}'",
        )
      }
      let args = []
      while self.current_token() != "rparen" {
        let expression = self.expression()
        if self.current_token() == "comma" {
          self.match_("comma")
        }
        args.push(expression)
      }
      self.match_("rparen")
      FunctionExpression(name, args)
    }
    "filter" => self.led_filter(left)
    "eq" | "ne" | "gt" | "gte" | "lt" | "lte" =>
      self.parse_comparator(left, token_type)
    "flatten" => {
      let left = Flatten(left)
      let right = self.parse_projection_rhs(token_binding_power("flatten"))
      Projection(left, right)
    }
    "lbracket" => {
      let token = self.lookahead_token(0)
      if token.type_ is ("number" | "colon") {
        let right = self.parse_index_expression()
        if left is IndexExpression(children) {
          // Optimization: if the left node is an index expr, we can avoid
          // creating another node and instead just add the right node as a
          // child of the left.
          children.push(right)
          left
        } else {
          self.project_if_slice(left, right)
        }
      } else {
        // We have a projection
        self.match_("star")
        self.match_("rbracket")
        let right = self.parse_projection_rhs(token_binding_power("star"))
        Projection(left, right)
      }
    }
    _ => {
      // No led function for this token: undo the advance done by the
      // caller so the error points at the offending token.
      self.index -= 1
      self.error_led_token(self.lookahead_token(0))
    }
  }
}

///|
fn Parser::led_filter(self : Parser, left : Node) -> Node raise JMESPathError {
  // Filters are projections.
  let condition = self.expression(binding_power=0)
  self.match_("rbracket")
  let right = if self.current_token() == "flatten" {
    Identity
  } else {
    self.parse_projection_rhs(token_binding_power("filter"))
  }
  FilterProjection(left, right, condition)
}

///|
fn Parser::parse_index_expression(self : Parser) -> Node raise JMESPathError {
  // We're here:
  // [<current>
  //  ^
  //  | current token
  if self.lookahead(0) == "colon" || self.lookahead(1) == "colon" {
    self.parse_slice_expression()
  } else {
    // Parse the syntax [number]
    let index = match self.lookahead_token(0).value {
      Int(i) => i
      _ => 0
    }
    let node = Index(index)
    self.advance()
    self.match_("rbracket")
    node
  }
}

///|
fn Parser::parse_slice_expression(self : Parser) -> Node raise JMESPathError {
  // [start:end:step]
  // Where start, end, and step are optional.
  // The last colon is optional as well.
  let parts : Array[Int?] = [None, None, None]
  let mut index = 0
  let mut current_token = self.current_token()
  while current_token != "rbracket" && index < 3 {
    if current_token == "colon" {
      index += 1
      if index == 3 {
        self.raise_parse_error_for_token(self.lookahead_token(0), "syntax error")
      }
      self.advance()
    } else if current_token == "number" {
      parts[index] = match self.lookahead_token(0).value {
        Int(i) => Some(i)
        _ => None
      }
      self.advance()
    } else {
      self.raise_parse_error_for_token(self.lookahead_token(0), "syntax error")
    }
    current_token = self.current_token()
  }
  self.match_("rbracket")
  Slice(parts[0], parts[1], parts[2])
}

///|
fn Parser::project_if_slice(
  self : Parser,
  left : Node,
  right : Node,
) -> Node raise JMESPathError {
  let index_expr = IndexExpression([left, right])
  if right is Slice(_, _, _) {
    Projection(index_expr, self.parse_projection_rhs(token_binding_power("star")))
  } else {
    index_expr
  }
}

///|
fn Parser::parse_comparator(
  self : Parser,
  left : Node,
  comparator : String,
) -> Node raise JMESPathError {
  let right = self.expression(binding_power=token_binding_power(comparator))
  Comparator(comparator, left, right)
}

///|
fn Parser::parse_multi_select_list(self : Parser) -> Node raise JMESPathError {
  let expressions = []
  while true {
    let expression = self.expression()
    expressions.push(expression)
    if self.current_token() == "rbracket" {
      break
    } else {
      self.match_("comma")
    }
  }
  self.match_("rbracket")
  MultiSelectList(expressions)
}

///|
fn Parser::parse_multi_select_hash(self : Parser) -> Node raise JMESPathError {
  let pairs = []
  while true {
    let key_token = self.lookahead_token(0)
    // Before getting the token value, verify it's an identifier.
    self.match_multiple_tokens(["quoted_identifier", "unquoted_identifier"])
    let key_name = key_token.value.py_str()
    self.match_("colon")
    let value = self.expression(binding_power=0)
    let node = KeyValPair(key_name, value)
    pairs.push(node)
    if self.current_token() == "comma" {
      self.match_("comma")
    } else if self.current_token() == "rbrace" {
      self.match_("rbrace")
      break
    }
  }
  MultiSelectDict(pairs)
}

///|
fn Parser::parse_projection_rhs(
  self : Parser,
  binding_power : Int,
) -> Node raise JMESPathError {
  // Parse the right hand side of the projection.
  let current = self.current_token()
  if token_binding_power(current) < projection_stop {
    // BP of 10 are all the tokens that stop a projection.
    Identity
  } else if current == "lbracket" {
    self.expression(binding_power~)
  } else if current == "filter" {
    self.expression(binding_power~)
  } else if current == "dot" {
    self.match_("dot")
    self.parse_dot_rhs(binding_power)
  } else {
    self.raise_parse_error_for_token(self.lookahead_token(0), "syntax error")
  }
}

///|
fn Parser::parse_dot_rhs(
  self : Parser,
  binding_power : Int,
) -> Node raise JMESPathError {
  // From the grammar:
  // expression '.' ( identifier /
  //                  multi-select-list /
  //                  multi-select-hash /
  //                  function-expression /
  //                  *
  // In terms of tokens that means that after a '.',
  // you can have:
  let lookahead = self.current_token()
  // Common case "foo.bar", so first check for an identifier.
  if lookahead is ("quoted_identifier" | "unquoted_identifier" | "star") {
    self.expression(binding_power~)
  } else if lookahead == "lbracket" {
    self.match_("lbracket")
    self.parse_multi_select_list()
  } else if lookahead == "lbrace" {
    self.match_("lbrace")
    self.parse_multi_select_hash()
  } else {
    let t = self.lookahead_token(0)
    let allowed = py_repr_str_list([
      "quoted_identifier", "unquoted_identifier", "lbracket", "lbrace",
    ])
    let msg = "Expecting: \{allowed}, got: \{t.type_}"
    self.raise_parse_error_for_token(t, msg)
  }
}

///|
fn[T] Parser::error_nud_token(
  self : Parser,
  token : Token,
) -> T raise JMESPathError {
  if token.type_ == "eof" {
    raise IncompleteExpressionError(
      lex_position=token.start,
      token_value=Some(token.value.py_str()),
      token_type=Some(token.type_),
      expression=None,
    )
  }
  self.raise_parse_error_for_token(token, "invalid token")
}

///|
fn[T] Parser::error_led_token(
  self : Parser,
  token : Token,
) -> T raise JMESPathError {
  self.raise_parse_error_for_token(token, "invalid token")
}

///|
fn Parser::match_(self : Parser, token_type : String) -> Unit raise JMESPathError {
  if self.current_token() == token_type {
    self.advance()
  } else {
    self.raise_parse_error_maybe_eof(token_type, self.lookahead_token(0))
  }
}

///|
fn Parser::match_multiple_tokens(
  self : Parser,
  token_types : Array[String],
) -> Unit raise JMESPathError {
  if !token_types.contains(self.current_token()) {
    self.raise_parse_error_maybe_eof(
      py_repr_str_list(token_types),
      self.lookahead_token(0),
    )
  }
  self.advance()
}

///|
fn Parser::advance(self : Parser) -> Unit {
  self.index += 1
}

///|
fn Parser::current_token(self : Parser) -> String {
  self.tokens[self.index].type_
}

///|
fn Parser::lookahead(self : Parser, number : Int) -> String {
  self.lookahead_token(number).type_
}

///|
fn Parser::lookahead_token(self : Parser, number : Int) -> Token {
  let i = self.index + number
  // Python lists accept negative indices.
  self.tokens[if i < 0 { i + self.tokens.length() } else { i }]
}

///|
fn[T] Parser::raise_parse_error_for_token(
  _self : Parser,
  token : Token,
  reason : String,
) -> T raise JMESPathError {
  raise new_parse_error(token, reason)
}

///|
fn[T] Parser::raise_parse_error_maybe_eof(
  _self : Parser,
  expected_type : String,
  token : Token,
) -> T raise JMESPathError {
  if token.type_ == "eof" {
    raise IncompleteExpressionError(
      lex_position=token.start,
      token_value=Some(token.value.py_str()),
      token_type=Some(token.type_),
      expression=None,
    )
  }
  let message = "Expecting: \{expected_type}, got: \{token.type_}"
  raise new_parse_error(token, message)
}

///|
/// The result of compiling an expression (`jmespath.parser.ParsedResult`).
pub struct ParsedResult {
  /// The source expression.
  expression : String
  /// The AST.
  parsed : Node
}

///|
/// Evaluates the compiled expression against `value`.
pub fn ParsedResult::search(
  self : ParsedResult,
  value : Json,
  options? : Options,
) -> Json raise JMESPathError {
  let interpreter = TreeInterpreter::new(options?)
  interpreter.visit(self.parsed, value)
}

///|
/// Renders the parsed AST as a Graphviz dot file (`_render_dot_file`).
/// The AST is an implementation detail; this is meant for debugging.
pub fn ParsedResult::render_dot_file(self : ParsedResult) -> String {
  GraphvizVisitor::new().visit(self.parsed)
}

///|
pub impl Show for ParsedResult with output(self, logger) {
  // Upstream's repr(ParsedResult) is repr(self.parsed), a Python dict.
  logger.write_string(py_repr(self.parsed.to_json()))
}
