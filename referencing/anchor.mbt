///|
/// An anchor within a `Resource` (Python's `referencing.Anchor`, and more
/// generally the `referencing.typing.Anchor` protocol).
///
/// Plain anchors resolve to their resource's contents. Other kinds of anchors
/// (such as JSON Schema 2020-12's dynamic anchors, see `dynamic_anchor`) carry
/// a `kind` tag (Python's class name) and their own resolution closure.
pub struct Anchor {
  /// The name of this anchor.
  name : String
  /// The resource this anchor points at.
  resource : Resource
  priv kind : String
  priv resolve_impl : ((Anchor, Resolver) -> Resolved raise)?
}

///|
/// Create a simple anchor in a `Resource`.
pub fn Anchor::new(name~ : String, resource~ : Resource) -> Anchor {
  { name, resource, kind: "Anchor", resolve_impl: None, }
}

///|
/// Create a custom kind of anchor (Python: any object implementing the
/// `referencing.typing.Anchor` protocol). `kind` plays the role of the Python
/// class name (used for equality and display), and `resolve` is called with
/// the anchor itself and the resolver.
pub fn Anchor::custom(
  name~ : String,
  resource~ : Resource,
  kind~ : String,
  resolve~ : (Anchor, Resolver) -> Resolved raise,
) -> Anchor {
  { name, resource, kind, resolve_impl: Some(resolve), }
}

///|
/// The kind of the anchor: `"Anchor"` for simple anchors, `"DynamicAnchor"`
/// for JSON Schema dynamic anchors, or a custom kind.
pub fn Anchor::kind(self : Anchor) -> String {
  self.kind
}

///|
/// Return the resource for this anchor.
pub fn Anchor::resolve(self : Anchor, resolver : Resolver) -> Resolved raise {
  match self.resolve_impl {
    None => { contents: self.resource.contents, resolver, }
    Some(f) => f(self, resolver)
  }
}

///|
pub impl Eq for Anchor with fn equal(self, other) {
  self.kind == other.kind &&
  self.name == other.name &&
  self.resource == other.resource
}

///|
/// `Anchor(name='...', resource=Resource(...))`, as Python's `repr`.
pub impl Show for Anchor with fn output(self, logger) {
  logger.write_string(
    "\{self.kind}(name=\{py_str_repr(self.name)}, resource=\{self.resource})",
  )
}
