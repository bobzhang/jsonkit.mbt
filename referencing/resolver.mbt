///|
/// A reference resolved to its contents by a `Resolver`, along with the
/// resolver to use for resolving any references *within* those contents
/// (which carries the new base URI, the updated registry and the dynamic
/// scope).
pub(all) struct Resolved {
  contents : Json
  resolver : Resolver
}

///|
/// A reference resolver.
///
/// Resolvers help resolve references (including relative ones) by pairing a
/// fixed base URI with a `Registry`.
///
/// This object, under normal circumstances, is expected to be used by
/// *implementers of libraries* built on top of `referencing` (e.g. JSON
/// Schema implementations or other libraries resolving JSON references), not
/// directly by end-users populating registries or while writing schemas or
/// other resources.
///
/// References are resolved against the base URI, and the combined URI is then
/// looked up within the registry.
///
/// The process of resolving a reference may itself involve calculating a
/// *new* base URI for future reference resolution (e.g. if an intermediate
/// resource sets a new base URI), or may involve encountering additional
/// subresources and adding them to a new registry.
pub struct Resolver {
  priv base_uri : String
  priv registry : Registry
  priv previous : @list.List[String]
}

///|
/// Create a resolver (Python's `Resolver(base_uri=..., registry=...)`).
/// Prefer `Registry::resolver`.
pub fn Resolver::new(
  base_uri~ : String,
  registry~ : Registry,
  previous? : @list.List[String] = @list.empty(),
) -> Resolver {
  { base_uri, registry, previous, }
}

///|
/// The base URI against which references are resolved.
pub fn Resolver::base_uri(self : Resolver) -> String {
  self.base_uri
}

///|
/// The registry references are looked up in.
pub fn Resolver::registry(self : Resolver) -> Registry {
  self.registry
}

///|
/// The previous base URIs (most recent first), i.e. the URIs in the dynamic
/// scope (Python's `_previous`).
pub fn Resolver::previous(self : Resolver) -> @list.List[String] {
  self.previous
}

///|
/// Resolve the given reference to the resource it points to.
///
/// Raises (as `ReferencingError`s):
///
/// * `Unresolvable` (or `PointerToNowhere`, `NoSuchAnchor`, `InvalidAnchor`,
///   see `ReferencingError::is_unresolvable`) if the reference isn't
///   resolvable: `NoSuchAnchor` if the reference is to a URI where a resource
///   exists but contains a plain name fragment which does not exist within
///   the resource, `PointerToNowhere` if the reference is to a URI where a
///   resource exists but contains a JSON pointer to a location within the
///   resource that does not exist.
/// * `CannotDetermineSpecification` if a retrieved resource raised it.
///
/// It may also raise `@urllib.ValueError` for malformed URIs, or any error
/// raised by custom specification / anchor callbacks.
pub fn Resolver::lookup(self : Resolver, reference : String) -> Resolved raise {
  let (uri, fragment) = if reference.has_prefix("#") {
    (self.base_uri, reference.view(start_offset=1).to_owned())
  } else {
    let defragged = @urllib.urldefrag(@urllib.urljoin(self.base_uri, reference))
    (defragged.url, defragged.fragment)
  }
  let retrieved = self.registry.get_or_retrieve(uri) catch {
    NoSuchResource(..) | Unretrievable(..) => raise Unresolvable(reference~)
    error => raise error
  }
  if fragment.has_prefix("/") {
    let resolver = self.evolve(registry=retrieved.registry, base_uri=uri)
    return retrieved.value.pointer(fragment, resolver)
  }
  if fragment != "" {
    let retrieved = retrieved.registry.anchor(uri, fragment)
    let resolver = self.evolve(registry=retrieved.registry, base_uri=uri)
    return retrieved.value.resolve(resolver)
  }
  let resolver = self.evolve(registry=retrieved.registry, base_uri=uri)
  { contents: retrieved.value.contents, resolver, }
}

///|
/// Create a resolver for a subresource (which may have a new base URI).
///
/// Returns this very resolver (physically) if the subresource has no ID.
pub fn Resolver::in_subresource(
  self : Resolver,
  subresource : Resource,
) -> Resolver raise @urllib.ValueError {
  match subresource.id() {
    None => self
    Some(id) => { ..self, base_uri: @urllib.urljoin(self.base_uri, id), }
  }
}

///|
/// In specs with such a notion, return the URIs in the dynamic scope (most
/// recent first), each paired with this resolver's registry.
pub fn Resolver::dynamic_scope(self : Resolver) -> Iter[(String, Registry)] {
  self.previous.iter().map(uri => (uri, self.registry))
}

///|
/// Evolve, appending to the dynamic scope.
fn Resolver::evolve(
  self : Resolver,
  base_uri~ : String,
  registry~ : Registry,
) -> Resolver {
  let previous = if self.base_uri != "" &&
    (self.previous.is_empty() || base_uri != self.base_uri) {
    @list.cons(self.base_uri, self.previous)
  } else {
    self.previous
  }
  { base_uri, registry, previous, }
}

///|
/// `Resolver(_base_uri='...', _registry=<Registry (...)>)`, as Python's `repr`.
pub impl Show for Resolver with fn output(self, logger) {
  logger.write_string(
    "Resolver(_base_uri=\{py_str_repr(self.base_uri)}, _registry=\{self.registry})",
  )
}
