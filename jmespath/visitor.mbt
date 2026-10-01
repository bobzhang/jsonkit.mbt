// Port of jmespath/visitor.py.

///|
/// Options to control how a JMESPath expression is evaluated
/// (`jmespath.visitor.Options`).
///
/// Upstream also has `dict_cls`, the mapping class used for multi-select
/// hashes; it is not needed here because `Map` always preserves insertion
/// order (the behaviour upstream gets with `dict_cls=OrderedDict`).
pub struct Options {
  /// The function table to use instead of the builtin one.
  custom_functions : Functions?
}

///|
pub fn Options::new(custom_functions? : Functions) -> Options {
  { custom_functions, }
}

///|
/// A function argument: either a JSON value or an expression reference
/// (`&expr`, upstream's `_Expression`).
pub enum Value {
  Data(Json)
  Expref(Expression)
}

///|
pub impl Show for Value with output(self, logger) {
  match self {
    Data(v) => logger.write_string(py_str(v))
    Expref(_) => logger.write_string("<jmespath.visitor._Expression object>")
  }
}

///|
/// Python's `type(value).__name__`.
fn Value::py_type_name(self : Value) -> String {
  match self {
    Data(v) => py_type_name(v)
    Expref(_) => "_Expression"
  }
}

///|
/// An expression reference bound to the interpreter that created it
/// (`jmespath.visitor._Expression`).
pub struct Expression {
  /// The referenced AST.
  expression : Node
  priv interpreter : TreeInterpreter
}

///|
/// Evaluates the referenced expression against `value`
/// (upstream: `expref.visit(expref.expression, value)`).
pub fn Expression::visit(self : Expression, value : Json) -> Json raise JMESPathError {
  self.interpreter.visit(self.expression, value)
}

///|
/// Evaluates AST nodes against JSON values (`TreeInterpreter`).
pub struct TreeInterpreter {
  priv options : Options
  priv functions : Functions
}

///|
pub fn TreeInterpreter::new(options? : Options) -> TreeInterpreter {
  let options = match options {
    Some(o) => o
    None => Options::new()
  }
  let functions = match options.custom_functions {
    Some(f) => f
    None => default_functions
  }
  { options, functions }
}

///|
/// The options this interpreter was created with.
pub fn TreeInterpreter::options(self : TreeInterpreter) -> Options {
  self.options
}

///|
/// Evaluates `node` against `value`.
pub fn TreeInterpreter::visit(
  self : TreeInterpreter,
  node : Node,
  value : Json,
) -> Json raise JMESPathError {
  match node {
    Subexpression(children) | IndexExpression(children) => {
      let mut result = value
      for child in children {
        result = self.visit(child, result)
      }
      result
    }
    Pipe(left, right) => self.visit(right, self.visit(left, value))
    Field(name) =>
      match value {
        Object(map) =>
          match map.get(name) {
            Some(v) => v
            None => Json::null()
          }
        _ => Json::null()
      }
    Comparator(name, first, second) => {
      // Common case: comparator is == or !=
      let left = self.visit(first, value)
      let right = self.visit(second, value)
      match name {
        "eq" => Json::boolean(jmespath_equals(left, right))
        "ne" => Json::boolean(!jmespath_equals(left, right))
        _ => {
          // Ordering operators are only valid for numbers (and strings,
          // which upstream supports as an extension).  Evaluating any other
          // type with a comparison operator will yield a None value.
          if !(is_comparable(left) && is_comparable(right)) {
            return Json::null()
          }
          let op = match name {
            "lt" => "<"
            "gt" => ">"
            "lte" => "<="
            _ => ">="
          }
          Json::boolean(py_order(op, left, right))
        }
      }
    }
    Current => value
    Expref(_) =>
      // Upstream returns an `_Expression` object here.  JSON values cannot
      // hold expression references, so they are only supported as direct
      // function arguments (see `visit_function_args`).
      raise TypeError(
        "expression references can only be used as function arguments",
      )
    FunctionExpression(name, args) => {
      let resolved_args = []
      for child in args {
        let current = match child {
          Expref(expression) => Value::Expref({ expression, interpreter: self })
          _ => Value::Data(self.visit(child, value))
        }
        resolved_args.push(current)
      }
      self.functions.call_function(name, resolved_args)
    }
    FilterProjection(left, right, comparator) => {
      guard self.visit(left, value) is Array(base) else { Json::null() }
      let collected = []
      for element in base {
        if is_true(self.visit(comparator, element)) {
          let current = self.visit(right, element)
          if !(current is Null) {
            collected.push(current)
          }
        }
      }
      Json::array(collected)
    }
    Flatten(child) => {
      guard self.visit(child, value) is Array(base) else {
        // Can't flatten the object if it's not a list.
        Json::null()
      }
      let merged_list = []
      for element in base {
        match element {
          Array(items) => merged_list.append(items)
          _ => merged_list.push(element)
        }
      }
      Json::array(merged_list)
    }
    Identity => value
    Index(index) => {
      // Even though we can index strings, we don't want to support that.
      guard value is Array(items) else { Json::null() }
      let i = if index < 0 { index + items.length() } else { index }
      if i >= 0 && i < items.length() {
        items[i]
      } else {
        Json::null()
      }
    }
    Slice(start, stop, step) => {
      guard value is Array(items) else { Json::null() }
      Json::array(py_slice(items, start, stop, step))
    }
    KeyValPair(_, child) => self.visit(child, value)
    Literal(literal) => literal
    MultiSelectDict(children) => {
      if value is Null {
        return Json::null()
      }
      let collected : Map[String, Json] = Map([])
      for child in children {
        let key = match child {
          KeyValPair(key, _) => key
          _ => ""
        }
        collected[key] = self.visit(child, value)
      }
      Json::object(collected)
    }
    MultiSelectList(children) => {
      if value is Null {
        return Json::null()
      }
      let collected = []
      for child in children {
        collected.push(self.visit(child, value))
      }
      Json::array(collected)
    }
    OrExpression(left, right) => {
      let matched = self.visit(left, value)
      if is_false(matched) {
        self.visit(right, value)
      } else {
        matched
      }
    }
    AndExpression(left, right) => {
      let matched = self.visit(left, value)
      if is_false(matched) {
        matched
      } else {
        self.visit(right, value)
      }
    }
    NotExpression(child) => {
      let original_result = self.visit(child, value)
      // Special case for 0, !0 should be false, not true (0 is not a
      // special cased integer in jmespath).  Every other number is truthy
      // in Python, so `not number` is always False.
      match original_result {
        Number(_, ..) => Json::boolean(false)
        other => Json::boolean(is_false(other))
      }
    }
    Projection(left, right) => {
      guard self.visit(left, value) is Array(base) else { Json::null() }
      let collected = []
      for element in base {
        let current = self.visit(right, element)
        if !(current is Null) {
          collected.push(current)
        }
      }
      Json::array(collected)
    }
    ValueProjection(left, right) => {
      guard self.visit(left, value) is Object(base) else { Json::null() }
      let collected = []
      for _, element in base {
        let current = self.visit(right, element)
        if !(current is Null) {
          collected.push(current)
        }
      }
      Json::array(collected)
    }
  }
}

///|
/// Python's `value[start:stop:step]` for lists (`PySlice_AdjustIndices`).
fn py_slice(
  items : Array[Json],
  start : Int?,
  stop : Int?,
  step : Int?,
) -> Array[Json] raise JMESPathError {
  let step = match step {
    Some(s) => s
    None => 1
  }
  if step == 0 {
    raise ValueError("slice step cannot be zero")
  }
  let length = items.length()
  let adjust = (bound : Int?, default : Int) => match bound {
    None => default
    Some(b) =>
      if b < 0 {
        let b = b + length
        if b < 0 {
          if step < 0 { -1 } else { 0 }
        } else {
          b
        }
      } else if b >= length {
        if step < 0 { length - 1 } else { length }
      } else {
        b
      }
  }
  let start = adjust(start, if step < 0 { length - 1 } else { 0 })
  let stop = adjust(stop, if step < 0 { -1 } else { length })
  let result = []
  let mut i = start
  if step > 0 {
    while i < stop {
      result.push(items[i])
      i += step
    }
  } else {
    while i > stop {
      result.push(items[i])
      i += step
    }
  }
  result
}

///|
/// `GraphvizVisitor`: renders an AST as a dot file.
priv struct GraphvizVisitor {
  lines : Array[String]
  mut count : Int
}

///|
fn GraphvizVisitor::new() -> GraphvizVisitor {
  { lines: [], count: 1 }
}

///|
fn GraphvizVisitor::visit(self : GraphvizVisitor, node : Node) -> String {
  self.lines.push("digraph AST {")
  let current = "\{node.type_name()}\{self.count}"
  self.count += 1
  self.visit_node(node, current)
  self.lines.push("}")
  self.lines.join("\n")
}

///|
fn GraphvizVisitor::visit_node(
  self : GraphvizVisitor,
  node : Node,
  current : String,
) -> Unit {
  let value = match node.value() {
    Some(v) => py_str(v)
    None => ""
  }
  self.lines.push("\{current} [label=\"\{node.type_name()}(\{value})\"]")
  for child in node.children() {
    let child_name = "\{child.type_name()}\{self.count}"
    self.count += 1
    self.lines.push("  \{current} -> \{child_name}")
    self.visit_node(child, child_name)
  }
}
