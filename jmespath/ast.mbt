// Port of jmespath/ast.py.
//
// Upstream AST nodes are dicts `{"type": ..., "children": [...], "value": ...}`
// built by small constructor functions (`ast.field(name)`, ...).  Here each
// node type is a constructor of the `Node` enum; `Node::type_name`,
// `Node::children`, `Node::value` and `Node::to_json` recover the dict view.
// `Subexpression` and `IndexExpression` hold a (mutable) `Array` because the
// parser appends to them, as upstream does.

///|
/// A JMESPath AST node.
pub(all) enum Node {
  /// `comparator(name, first, second)`; `name` is one of
  /// `eq`, `ne`, `lt`, `gt`, `lte`, `gte`.
  Comparator(String, Node, Node)
  /// `current_node()`
  Current
  /// `expref(expression)`
  Expref(Node)
  /// `function_expression(name, args)`
  FunctionExpression(String, Array[Node])
  /// `field(name)`
  Field(String)
  /// `filter_projection(left, right, comparator)`
  FilterProjection(Node, Node, Node)
  /// `flatten(node)`
  Flatten(Node)
  /// `identity()`
  Identity
  /// `index(index)`
  Index(Int)
  /// `index_expression(children)`
  IndexExpression(Array[Node])
  /// `key_val_pair(key_name, node)`
  KeyValPair(String, Node)
  /// `literal(literal_value)`
  Literal(Json)
  /// `multi_select_dict(nodes)`, the nodes are `KeyValPair`s.
  MultiSelectDict(Array[Node])
  /// `multi_select_list(nodes)`
  MultiSelectList(Array[Node])
  /// `or_expression(left, right)`
  OrExpression(Node, Node)
  /// `and_expression(left, right)`
  AndExpression(Node, Node)
  /// `not_expression(expr)`
  NotExpression(Node)
  /// `pipe(left, right)`
  Pipe(Node, Node)
  /// `projection(left, right)`
  Projection(Node, Node)
  /// `subexpression(children)`
  Subexpression(Array[Node])
  /// `slice(start, end, step)`
  Slice(Int?, Int?, Int?)
  /// `value_projection(left, right)`
  ValueProjection(Node, Node)
} derive(Eq, Debug)

///|
/// The upstream `node['type']`.
pub fn Node::type_name(self : Node) -> String {
  match self {
    Comparator(_, _, _) => "comparator"
    Current => "current"
    Expref(_) => "expref"
    FunctionExpression(_, _) => "function_expression"
    Field(_) => "field"
    FilterProjection(_, _, _) => "filter_projection"
    Flatten(_) => "flatten"
    Identity => "identity"
    Index(_) => "index"
    IndexExpression(_) => "index_expression"
    KeyValPair(_, _) => "key_val_pair"
    Literal(_) => "literal"
    MultiSelectDict(_) => "multi_select_dict"
    MultiSelectList(_) => "multi_select_list"
    OrExpression(_, _) => "or_expression"
    AndExpression(_, _) => "and_expression"
    NotExpression(_) => "not_expression"
    Pipe(_, _) => "pipe"
    Projection(_, _) => "projection"
    Subexpression(_) => "subexpression"
    Slice(_, _, _) => "slice"
    ValueProjection(_, _) => "value_projection"
  }
}

///|
/// The upstream `node['children']` that are nodes.  (Upstream `slice` nodes
/// store their integer bounds as children; they are not returned here.)
pub fn Node::children(self : Node) -> Array[Node] {
  match self {
    Comparator(_, a, b) => [a, b]
    Current | Identity | Field(_) | Index(_) | Literal(_) | Slice(_, _, _) => []
    Expref(n) | Flatten(n) | KeyValPair(_, n) | NotExpression(n) => [n]
    FunctionExpression(_, args) => args
    FilterProjection(left, right, comparator) => [left, right, comparator]
    IndexExpression(children)
    | MultiSelectDict(children)
    | MultiSelectList(children)
    | Subexpression(children) => children
    OrExpression(a, b)
    | AndExpression(a, b)
    | Pipe(a, b)
    | Projection(a, b)
    | ValueProjection(a, b) => [a, b]
  }
}

///|
/// The upstream `node['value']`, for the node types that have one.
pub fn Node::value(self : Node) -> Json? {
  match self {
    Comparator(name, _, _)
    | FunctionExpression(name, _)
    | Field(name)
    | KeyValPair(name, _) => Some(Json::string(name))
    Index(i) => Some(Json::number(i.to_double()))
    Literal(v) => Some(v)
    _ => None
  }
}

///|
fn optional_int_json(i : Int?) -> Json {
  match i {
    Some(i) => Json::number(i.to_double())
    None => Json::null()
  }
}

///|
/// The upstream dict representation of the node, e.g.
/// `{"type": "field", "children": [], "value": "foo"}`.
pub impl ToJson for Node with to_json(self) {
  // Same key order as the upstream constructors.
  let obj : Map[String, Json] = Map([])
  obj["type"] = Json::string(self.type_name())
  if self is (Index(_) | Literal(_)) {
    obj["value"] = self.value().unwrap()
  }
  obj["children"] = match self {
    Slice(start, end, step) =>
      Json::array([
        optional_int_json(start),
        optional_int_json(end),
        optional_int_json(step),
      ])
    _ => Json::array(self.children().map(child => child.to_json()))
  }
  if self.value() is Some(v) {
    obj["value"] = v
  }
  Json::object(obj)
}

///|
pub extend Node with ToJson::{to_json}
