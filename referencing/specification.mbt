///|
/// A segment of a JSON pointer as seen by `Specification::maybe_in_subresource`
/// (Python's `int | str`): array indices are `Index`, everything else `Key`.
pub(all) enum Segment {
  Key(String)
  Index(Int)
} derive(Debug, Eq)

///|
/// Whether the segment is the string `key` (Python's `segment == key`).
pub fn Segment::is_key(self : Segment, key : String) -> Bool {
  self is Key(k) && k == key
}

///|
/// A specification which defines referencing behavior.
///
/// The various callbacks of a `Specification` allow for varying referencing
/// behavior across JSON Schema specification versions, etc. Each callback is
/// a first-class closure stored in a field, and also callable with method
/// syntax (`spec.id_of(contents)`).
pub struct Specification {
  /// A short human-readable name for the specification, used for debugging.
  name : String
  /// Find the ID of a given document.
  id_of : (Json) -> String?
  /// Retrieve the subresources of the given document (without traversing into
  /// the subresources themselves).
  subresources_of : (Json) -> Array[Json]
  /// While resolving a JSON pointer, conditionally enter a subresource
  /// (if e.g. we have just entered a keyword whose value is a subresource).
  /// Arguments are `(segments, resolver, subresource)`.
  maybe_in_subresource : (Array[Segment], Resolver, Resource) -> Resolver raise
  /// Retrieve the anchors contained in the given document. Arguments are
  /// `(specification, contents)`; see `Specification::anchors_in`.
  anchors_in : (Specification, Json) -> Array[Anchor]
}

///|
/// Create a new specification from its callbacks.
pub fn Specification::new(
  name~ : String,
  id_of~ : (Json) -> String?,
  subresources_of~ : (Json) -> Array[Json],
  anchors_in~ : (Specification, Json) -> Array[Anchor],
  maybe_in_subresource~ : (Array[Segment], Resolver, Resource) -> Resolver raise,
) -> Specification {
  { name, id_of, subresources_of, maybe_in_subresource, anchors_in }
}

///|
/// Find the ID of a given document.
pub fn Specification::id_of(self : Specification, contents : Json) -> String? {
  (self.id_of)(contents)
}

///|
/// Retrieve the subresources of the given document.
pub fn Specification::subresources_of(
  self : Specification,
  contents : Json,
) -> Array[Json] {
  (self.subresources_of)(contents)
}

///|
/// Retrieve the anchors contained in the given document.
pub fn Specification::anchors_in(
  self : Specification,
  contents : Json,
) -> Array[Anchor] {
  (self.anchors_in)(self, contents)
}

///|
/// Conditionally enter a subresource while resolving a JSON pointer.
pub fn Specification::maybe_in_subresource(
  self : Specification,
  segments : Array[Segment],
  resolver : Resolver,
  subresource : Resource,
) -> Resolver raise {
  (self.maybe_in_subresource)(segments, resolver, subresource)
}

///|
/// Create a resource which is interpreted using this specification.
pub fn Specification::create_resource(
  self : Specification,
  contents : Json,
) -> Resource {
  { contents, specification: self }
}

///|
/// An opaque specification where resources have no subresources nor internal
/// identifiers (Python's `Specification.OPAQUE`).
pub let opaque_specification : Specification = Specification::new(
  name="opaque",
  id_of=_ => None,
  subresources_of=_ => [],
  anchors_in=(_, _) => [],
  maybe_in_subresource=(_, resolver, _) => resolver,
)

///|
/// Attempt to discern which specification applies to the given contents.
///
/// Mirrors Python's `Specification.detect`, which may be called either as a
/// class method (here: no `default`) or as an instance method (here:
/// `default=that_specification`). Recall that not all contents contain enough
/// information about which specification they are written for -- the JSON
/// Schema `{}`, for instance, is valid under many different dialects.
///
/// * Without `default`, raises `CannotDetermineSpecification` if the contents
///   are not an object or have no string `$schema`, and `UnknownDialect` if
///   `$schema` names an unknown dialect.
/// * With `default`, that specification is returned for unidentifiable or
///   unknown-dialect contents.
pub fn Specification::detect(
  contents : Json,
  default? : Specification,
) -> Specification raise ReferencingError {
  match default {
    None => {
      guard contents is Object(obj) else {
        raise CannotDetermineSpecification(contents~)
      }
      guard obj.get("$schema") is Some(String(dialect_id)) else {
        raise CannotDetermineSpecification(contents~)
      }
      specification_with(dialect_id)
    }
    Some(default) => {
      guard contents is Object(obj) else { return default }
      match obj.get("$schema") {
        Some(String(dialect_id)) => specification_with(dialect_id, default~)
        // Python raises an AttributeError for a non-string `$schema` here;
        // we fall back to the default instead.
        _ => default
      }
    }
  }
}

///|
/// Specifications compare equal when they are the same object, or have the
/// same name and the very same callbacks (as with upstream's attrs equality,
/// where functions compare by identity).
pub impl Eq for Specification with equal(self, other) {
  physical_equal(self, other) ||
  (
    self.name == other.name &&
    physical_equal(self.id_of, other.id_of) &&
    physical_equal(self.subresources_of, other.subresources_of) &&
    physical_equal(self.maybe_in_subresource, other.maybe_in_subresource) &&
    physical_equal(self.anchors_in, other.anchors_in)
  )
}

///|
/// `<Specification name='...'>`, as Python's `repr`.
pub impl Show for Specification with output(self, logger) {
  logger.write_string("<Specification name=\{py_str_repr(self.name)}>")
}
