///|
/// ErrorTrees make it easier to check which validations failed
/// (`jsonschema.exceptions.ErrorTree`).
///
/// `errors` maps each failed keyword at this level of the instance to its
/// error (keyed by the keyword name, or by its Python `repr` for non-string
/// `validator`s).
pub struct ErrorTree {
  errors : Map[String, ValidationError]
  priv contents : Map[PathItem, ErrorTree]
  priv mut instance : Json?
}

///|
/// Raised when indexing an `ErrorTree` at an index its instance lacks
/// (Python's `KeyError` / `IndexError` / `TypeError`).
pub suberror LookupError {
  KeyError(String)
  IndexError(Int)
  TypeError(String)
} derive(Debug)

///|
fn validator_key(v : Json?) -> String {
  match v {
    Some(String(k)) => k
    Some(other) => @pycompat.repr(other)
    None => "<unset>"
  }
}

///|
/// Build a tree from errors; `instance`, if known, enables indexing the tree
/// at indices not present in it to raise the same error that indexing the
/// instance itself would.
pub fn ErrorTree::new(
  errors? : ArrayView[ValidationError] = [],
  instance? : Json,
) -> ErrorTree {
  let tree = { errors: Map([]), contents: Map([]), instance }
  for error in errors {
    let mut container = tree
    for element in error.path {
      container = match container.contents.get(element) {
        Some(t) => t
        None => {
          let t = { errors: Map([]), contents: Map([]), instance: None }
          container.contents[element] = t
          t
        }
      }
    }
    container.errors[validator_key(error.validator)] = error
    container.instance = error.instance
  }
  tree
}

///|
/// Check whether `instance[index]` has any errors.
pub fn ErrorTree::contains(self : ErrorTree, index : PathItem) -> Bool {
  self.contents.contains(index)
}

///|
/// Retrieve the child tree one level down at the given `index`.
///
/// If the index is not in the instance that this tree corresponds to and is
/// not known by this tree, the error indexing the instance would produce is
/// raised.
pub fn ErrorTree::at(
  self : ErrorTree,
  index : PathItem,
) -> ErrorTree raise LookupError {
  if self.contents.get(index) is Some(t) {
    return t
  }
  guard self.instance is Some(instance) else { return ErrorTree::new() }
  let child = match (instance, index) {
    (Object(m), Key(k)) =>
      match m.get(k) {
        Some(v) => v
        None => raise KeyError(k)
      }
    (Array(xs), Index(i)) => {
      let j = if i < 0 { i + xs.length() } else { i }
      if j < 0 || j >= xs.length() {
        raise IndexError(i)
      }
      xs[j]
    }
    (String(s), Index(i)) => {
      let cps = @unicodedata.code_points(s)
      let j = if i < 0 { i + cps.length() } else { i }
      if j < 0 || j >= cps.length() {
        raise IndexError(i)
      }
      Json::string(@unicodedata.from_code_points([cps[j]]))
    }
    (Object(_), Index(i)) => raise KeyError(i.to_string())
    _ => raise TypeError("cannot index \{@pycompat.repr(instance)}")
  }
  ErrorTree::new(instance=child)
}

///|
/// Iterate (non-recursively) over the indices in the instance with errors.
pub fn ErrorTree::iter(self : ErrorTree) -> Iter[PathItem] {
  self.contents.keys()
}

///|
/// The total number of errors in the entire tree, including children.
pub fn ErrorTree::total_errors(self : ErrorTree) -> Int {
  let mut child_errors = 0
  for _, tree in self.contents {
    child_errors += tree.total_errors()
  }
  self.errors.length() + child_errors
}

///|
/// `len(tree)`: the `total_errors`.
pub fn ErrorTree::length(self : ErrorTree) -> Int {
  self.total_errors()
}

///|
/// `repr(tree)`: `<ErrorTree (2 total errors)>`.
pub impl Show for ErrorTree with output(self, logger) {
  let total = self.total_errors()
  let errors = if total == 1 { "error" } else { "errors" }
  logger.write_string("<ErrorTree (\{total} total \{errors})>")
}
