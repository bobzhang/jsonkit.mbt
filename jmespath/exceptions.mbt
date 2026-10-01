// Port of jmespath/exceptions.py.
//
// Python models the errors as a class hierarchy rooted at
// `JMESPathError(ValueError)`.  In MoonBit they are the constructors of a
// single `JMESPathError` suberror.  The class hierarchy is recoverable with
// the predicates `is_parse_error`, `is_arity_error`, ...  The rendered
// messages (`Show`) are the same as Python's `str(exception)`.

///|
/// All errors raised while compiling or evaluating a JMESPath expression.
///
/// Constructors mirror the exception classes of jmespath.py:
///
/// - `ParseError` (`exceptions.ParseError`): `token_value` is the `str()` of
///   the offending token's value, `token_type` is upper-cased like upstream.
/// - `IncompleteExpressionError`: after the parser fills in the expression,
///   `lex_position` is the length of the expression and `token_value` /
///   `token_type` are `None`, just like `set_expression` upstream.
/// - `LexerError`
/// - `ArityError` / `VariadictArityError` (sic, upstream spelling)
/// - `JMESPathTypeError`
/// - `EmptyExpressionError`
/// - `UnknownFunctionError`
///
/// Python can additionally leak *builtin* exceptions from the interpreter
/// (for example `ValueError: slice step cannot be zero`, or a `TypeError`
/// when `<` compares a number with a string).  These are modelled by the
/// `ValueError`, `TypeError` and `OverflowError` constructors.
pub(all) suberror JMESPathError {
  ParseError(
    lex_position~ : Int,
    token_value~ : String,
    token_type~ : String,
    msg~ : String,
    expression~ : String?
  )
  IncompleteExpressionError(
    lex_position~ : Int,
    token_value~ : String?,
    token_type~ : String?,
    expression~ : String?
  )
  LexerError(
    lexer_position~ : Int,
    lexer_value~ : String,
    message~ : String,
    expression~ : String?
  )
  ArityError(
    expected_arity~ : Int,
    actual_arity~ : Int,
    function_name~ : String
  )
  VariadictArityError(
    expected_arity~ : Int,
    actual_arity~ : Int,
    function_name~ : String
  )
  JMESPathTypeError(
    function_name~ : String,
    current_value~ : Value,
    actual_type~ : String,
    expected_types~ : Array[String]
  )
  EmptyExpressionError
  UnknownFunctionError(String)
  /// Python's builtin `ValueError` (e.g. "slice step cannot be zero").
  ValueError(String)
  /// Python's builtin `TypeError` (e.g. unorderable comparison).
  TypeError(String)
  /// Python's builtin `OverflowError` (e.g. `ceil` of infinity).
  OverflowError(String)
}

///|
fn optional_str(s : String?) -> String {
  match s {
    Some(s) => s
    None => "None"
  }
}

///|
fn pluralize(word : String, count : Int) -> String {
  if count == 1 {
    word
  } else {
    word + "s"
  }
}

///|
pub impl Show for JMESPathError with fn output(self, logger) {
  match self {
    ParseError(lex_position~, token_value~, token_type~, msg~, expression~) => {
      // lex_position + 1 to account for the starting double quote char.
      let underline = " ".repeat(lex_position + 1) + "^"
      logger.write_string(
        "\{msg}: Parse error at column \{lex_position}, token \"\{token_value}\" (\{token_type}), for expression:\n\"\{optional_str(expression)}\"\n\{underline}",
      )
    }
    IncompleteExpressionError(lex_position~, expression~, ..) => {
      let underline = " ".repeat(lex_position + 1) + "^"
      logger.write_string(
        "Invalid jmespath expression: Incomplete expression:\n\"\{optional_str(expression)}\"\n\{underline}",
      )
    }
    LexerError(lexer_position~, message~, expression~, ..) => {
      let underline = " ".repeat(lexer_position) + "^"
      logger.write_string(
        "Bad jmespath expression: \{message}:\n\{optional_str(expression)}\n\{underline}",
      )
    }
    ArityError(expected_arity~, actual_arity~, function_name~) =>
      logger.write_string(
        "Expected \{expected_arity} \{pluralize("argument", expected_arity)} for function \{function_name}(), received \{actual_arity}",
      )
    VariadictArityError(expected_arity~, actual_arity~, function_name~) =>
      logger.write_string(
        "Expected at least \{expected_arity} \{pluralize("argument", expected_arity)} for function \{function_name}(), received \{actual_arity}",
      )
    JMESPathTypeError(
      function_name~,
      current_value~,
      actual_type~,
      expected_types~
    ) =>
      logger.write_string(
        "In function \{function_name}(), invalid type for value: \{current_value}, expected one of: \{py_repr_str_list(expected_types)}, received: \"\{actual_type}\"",
      )
    EmptyExpressionError =>
      logger.write_string("Invalid JMESPath expression: cannot be empty.")
    UnknownFunctionError(msg) => logger.write_string(msg)
    ValueError(msg) => logger.write_string(msg)
    TypeError(msg) => logger.write_string(msg)
    OverflowError(msg) => logger.write_string(msg)
  }
}

///|
/// `isinstance(e, ParseError)` (includes lexer, incomplete-expression and
/// arity errors, which subclass `ParseError` upstream).
pub fn JMESPathError::is_parse_error(self : JMESPathError) -> Bool {
  self
  is (ParseError(..)
  | IncompleteExpressionError(..)
  | LexerError(..)
  | ArityError(..)
  | VariadictArityError(..))
}

///|
/// `isinstance(e, ArityError)` (includes `VariadictArityError`).
pub fn JMESPathError::is_arity_error(self : JMESPathError) -> Bool {
  self is (ArityError(..) | VariadictArityError(..))
}

///|
/// Whether upstream raises this as a subclass of Python's `ValueError`.
/// Every error except the builtin `TypeError` / `OverflowError` ones is.
pub fn JMESPathError::is_value_error(self : JMESPathError) -> Bool {
  !(self is (TypeError(_) | OverflowError(_)))
}

///|
/// Raised by `loads` (Python's `json.JSONDecodeError`).  `pos`, `lineno` and
/// `colno` count code points, like Python.
pub(all) suberror JSONDecodeError {
  JSONDecodeError(msg~ : String, doc~ : String, pos~ : Int)
}

///|
pub impl Show for JSONDecodeError with fn output(self, logger) {
  let JSONDecodeError(msg~, doc~, pos~) = self
  // Python: lineno = doc.count('\n', 0, pos) + 1
  //         colno = pos - doc.rfind('\n', 0, pos)
  let mut lineno = 1
  let mut last_nl = -1
  for i, c in doc.to_array() {
    if i >= pos {
      break
    }
    if c == '\n' {
      lineno += 1
      last_nl = i
    }
  }
  let colno = pos - last_nl
  logger.write_string("\{msg}: line \{lineno} column \{colno} (char \{pos})")
}

///|
pub extend JMESPathError with Show::{to_string}

///|
pub extend JSONDecodeError with Show::{to_string}
