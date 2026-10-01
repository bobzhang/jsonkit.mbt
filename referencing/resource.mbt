///|
/// A document (deserialized JSON) with a concrete interpretation under a
/// specification.
///
/// In other words, a `Json` value along with a `Specification` which describes
/// how the document interacts with referencing -- both internally (how it
/// refers to other resources) and externally (how it should be identified
/// such that it is referenceable by other documents).
pub struct Resource {
  contents : Json
  specification : Specification
}

///|
/// Create a resource with an explicit specification
/// (Python's `Resource(contents=..., specification=...)`).
pub fn Resource::new(
  contents : Json,
  specification~ : Specification,
) -> Resource {
  { contents, specification, }
}

///|
/// Create a resource guessing which specification applies to the contents.
///
/// Without `default_specification`, raises `CannotDetermineSpecification` if
/// the contents have no discernible information (a `$schema` keyword) which
/// could be used to guess which specification they identify as (and
/// `UnknownDialect` for unknown `$schema`s). See `Specification::detect`.
pub fn Resource::from_contents(
  contents : Json,
  default_specification? : Specification,
) -> Resource raise ReferencingError {
  let specification = Specification::detect(
    contents,
    default?=default_specification,
  )
  specification.create_resource(contents)
}

///|
/// Create an opaque `Resource` -- i.e. one with the opaque specification.
pub fn Resource::new_opaque(contents : Json) -> Resource {
  opaque_specification.create_resource(contents)
}

///|
/// Retrieve this resource's (specification-specific) identifier, with any
/// trailing `#` characters stripped.
pub fn Resource::id(self : Resource) -> String? {
  match self.specification.id_of(self.contents) {
    None => None
    Some(id) => Some(rstrip_hash(id))
  }
}

///|
/// Retrieve this resource's subresources. Each is interpreted by detecting its
/// specification, defaulting to this resource's specification.
pub fn Resource::subresources(self : Resource) -> Array[Resource] {
  self.specification
  .subresources_of(self.contents)
  .map(each => {
    let specification = Specification::detect(each, default=self.specification) catch {
      _ => self.specification
    }
    specification.create_resource(each)
  })
}

///|
/// Retrieve this resource's (specification-specific) anchors.
pub fn Resource::anchors(self : Resource) -> Array[Anchor] {
  self.specification.anchors_in(self.contents)
}

///|
/// Resolve the given JSON pointer (the fragment of a reference, e.g.
/// `/definitions/foo`) within this resource.
///
/// As upstream, the pointer (minus its first character) is first
/// percent-decoded with `@urllib.unquote`, then split on `/`; each segment
/// indexing into an object has `~1` replaced by `/` and then `~0` by `~`,
/// while segments indexing into arrays (and strings) are parsed as Python
/// integers (so negative indices count from the end, as in Python).
///
/// Raises `PointerToNowhere` if the pointer points to a location not present
/// in the document.
pub fn Resource::pointer(
  self : Resource,
  pointer : String,
  resolver : Resolver,
) -> Resolved raise {
  if pointer == "" {
    return { contents: self.contents, resolver, }
  }
  let mut contents = self.contents
  let mut resolver = resolver
  let mut segments : Array[Segment] = []
  let decoded = @urllib.unquote(pointer.view(start_offset=1).to_owned())
  for raw in decoded.split("/") {
    let raw = raw.to_owned()
    let (segment, next) = match contents {
      Array(items) => {
        guard py_int(raw) is Some(index) else {
          raise PointerToNowhere(reference=pointer, resource=self)
        }
        let len = items.length()
        let i = if index < 0 { index + len } else { index }
        guard i >= 0 && i < len else {
          raise PointerToNowhere(reference=pointer, resource=self)
        }
        (Index(index), items[i])
      }
      String(s) => {
        // Python strings are sequences of code points, too.
        guard py_int(raw) is Some(index) else {
          raise PointerToNowhere(reference=pointer, resource=self)
        }
        let chars = s.iter().to_array()
        let len = chars.length()
        let i = if index < 0 { index + len } else { index }
        guard i >= 0 && i < len else {
          raise PointerToNowhere(reference=pointer, resource=self)
        }
        (Index(index), Json::string(chars[i].to_string()))
      }
      Object(obj) => {
        let key = raw
          .replace_all(old="~1", new="/")
          .replace_all(old="~0", new="~")
        guard obj.get(key) is Some(value) else {
          raise PointerToNowhere(reference=pointer, resource=self)
        }
        (Key(key), value)
      }
      _ => raise PointerToNowhere(reference=pointer, resource=self)
    }
    contents = next
    segments.push(segment)
    let last = resolver
    resolver = self.specification.maybe_in_subresource(
      segments,
      resolver,
      self.specification.create_resource(contents),
    )
    if !physical_equal(resolver, last) {
      segments = []
    }
  }
  { contents, resolver, }
}

///|
/// Resources are equal when their contents are equal and their specifications
/// are equal.
pub impl Eq for Resource with fn equal(self, other) {
  self.contents == other.contents && self.specification == other.specification
}

///|
/// `Resource(contents=..., _specification=<Specification name='...'>)`, as
/// Python's `repr`.
pub impl Show for Resource with fn output(self, logger) {
  logger.write_string(
    "Resource(contents=\{py_repr(self.contents)}, _specification=\{self.specification})",
  )
}

///|
/// Python's `str.rstrip("#")`.
fn rstrip_hash(s : String) -> String {
  let mut end = s.length()
  while end > 0 && s[end - 1] == '#' {
    end -= 1
  }
  s.view(end_offset=end).to_owned()
}
